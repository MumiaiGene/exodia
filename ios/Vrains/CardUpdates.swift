import Foundation
import Observation
import CryptoKit

enum CardDigest {
 static func sha256(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
 static func md5(_ data:Data)->String { Insecure.MD5.hash(data:data).map{String(format:"%02x",$0)}.joined() }
}

enum OfficialHTML {
    static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex=try? NSRegularExpression(pattern:pattern,options:[.dotMatchesLineSeparators]) else { return [] }
        let source=text as NSString
        return regex.matches(in:text,range:NSRange(location:0,length:source.length)).map { match in
            (1..<match.numberOfRanges).map { match.range(at:$0).location == NSNotFound ? "" : source.substring(with:match.range(at:$0)) }
        }
    }
    static func clean(_ text: String) -> String {
        var value=text.replacingOccurrences(of:"&lt;br&gt;",with:"\n").replacingOccurrences(of:"<br>",with:"\n").replacingOccurrences(of:"&lt;hr&gt;",with:"\n")
        value=value.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
        for (a,b) in [("&amp;","&"),("&quot;","\""),("&#39;","'"),("&times;","×"),("&nbsp;"," "),("&lt;","<"),("&gt;",">"),("&ldquo;","“"),("&rdquo;","”"),("&lsquo;","‘"),("&rsquo;","’")] { value=value.replacingOccurrences(of:a,with:b) }
        if let regex=try? NSRegularExpression(pattern:#"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            let original=value as NSString
            for match in regex.matches(in:value,range:NSRange(location:0,length:original.length)).reversed() {
                let token=original.substring(with:match.range(at:1))
                let code=token.hasPrefix("x") ? UInt32(token.dropFirst(),radix:16) : UInt32(token)
                if let code,let scalar=UnicodeScalar(code),let range=Range(match.range,in:value) { value.replaceSubrange(range,with:String(scalar)) }
            }
        }
        return value.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func chineseTranslation(cid: Int64, html: String, pendulum: Bool) throws -> [String:String] {
        guard html.contains("class=\"CardText\""),
              groups(#"<meta[^>]+http-equiv=["']Content-Language["'][^>]+content=["']cn["']"#,in:html).count==1,
              let pageCID=groups(#"<meta[^>]+property=["']og:url["'][^>]+content=["'][^"']*cid=([0-9]+)"#,in:html).first?.first.flatMap(Int64.init),pageCID==cid,
              let title=groups(#"<meta[^>]+(?:name|property)=["'](?:title|og:title)["'][^>]+content=["']([^"']+)"#,in:html).first?.first else { throw CardCatalogError.invalidData }
        let section=html.components(separatedBy:"<!-- ///CardDetail_packlist")[0]
        let texts=groups(#"<div class="text_linebreak">(.*?)</div>"#,in:section).map { clean($0[0]) }
        let name=clean(title.components(separatedBy:" | ")[0]),desc=texts.dropFirst(pendulum ? 1:0).first ?? ""
        let pdesc=pendulum ? texts.first ?? "" : ""
        guard !name.isEmpty,!desc.isEmpty,(!pendulum || !pdesc.isEmpty) else { throw CardCatalogError.invalidData }
        return ["name":name,"text":desc,"pdesc":pdesc]
    }
    static func rawCard(cid: Int64, japanese html: String, chinese: String?, supplement: Data?, existing: Data? = nil) throws -> Data {
        guard html.contains("class=\"CardText\""),
              groups(#"<meta[^>]+property=["']og:url["'][^>]+content=["'][^"']*cid=([0-9]+)"#,in:html).first?.first.flatMap(Int64.init)==cid,
              let title=groups(#"<meta[^>]+(?:name|property)=["'](?:title|og:title)["'][^>]+content=["']([^"']+)"#,in:html).first?.first else { throw CardCatalogError.invalidData }
        let previous=existing.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
        var raw=previous ?? ["cid":cid,"id":0]
        if let fetched=supplement.flatMap({try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}) {
            raw.merge(fetched) { _,new in new }
        }
        raw["cid"]=cid;raw["jp_name"]=clean(title.components(separatedBy:" | ")[0])
        let ruby=groups(#"<span class="ruby">(.*?)</span>"#,in:html).first?.first;raw["jp_ruby"]=ruby.map(clean) ?? raw["jp_name"]
        func texts(_ value: String) -> [String] { groups(#"<div class="text_linebreak">(.*?)</div>"#,in:value.components(separatedBy:"<!-- ///CardDetail_packlist")[0]).map { clean($0[0]) } }
        let all=texts(html),pendulum=html.contains("class=\"CardText pen\"")
        let desc=all.dropFirst(pendulum ? 1:0).first ?? "",pdesc=pendulum ? all.first ?? "" : ""
        var translated=raw["text"] as? [String:Any] ?? [:]
        let freshChinese=chinese.flatMap { try? chineseTranslation(cid:cid,html:$0,pendulum:pendulum) }
        let preservedChinese=(previous?["official_cn"] as? [String:String]) ?? raw["official_cn"] as? [String:String]
        if let cn=freshChinese ?? preservedChinese {
            raw["sc_name"]=cn["name"];raw["official_cn"]=cn
            translated["desc"]=cn["text"];translated["pdesc"]=cn["pdesc"] ?? ""
        }
        if (translated["desc"] as? String ?? "").isEmpty { translated["desc"]=desc }
        if (translated["pdesc"] as? String ?? "").isEmpty { translated["pdesc"]=pdesc }
        let preferred=["sc_name","nwbbs_n","jp_name"].compactMap { raw[$0] as? String }.first ?? "卡牌 \(cid)";raw["display_name"]=preferred
        var data=raw["data"] as? [String:Any] ?? ["ot":1,"setcode":0]
        let vals=groups(#"<span class="item_box_value">\s*([^<]+)</span>"#,in:html).map { clean($0[0]) }
        let species=groups(#"<p class="species">(.*?)</p>"#,in:html).first?.first.map(clean) ?? ""
        let monster = !species.isEmpty
        func number(_ value: String) -> Int64? { value.contains("?") ? -2 : groups(#"([0-9]+)"#,in:value).first?.first.flatMap(Int64.init) }
        let types: [(String,Int64)] = [("通常",16),("効果",32),("融合",64),("儀式",128),("スピリット",512),("ユニオン",1024),("デュアル",2048),("チューナー",4096),("シンクロ",8192),("トークン",16384),("エクシーズ",8388608),("ペンデュラム",16777216),("リンク",67108864),("速攻",65536),("永続",131072),("装備",262144),("フィールド",524288),("カウンター",1048576),("リバース",2097152),("トゥーン",4194304),("特殊召喚",33554432)]
        let effect=groups(#"<span class="item_box_value">\s*([^<]+)</span>"#,in:html).first?.first ?? ""
        var bits: Int64 = monster ? 1 : effect.contains("罠") ? 4 : 2
        for (name,flag) in types where (monster ? species : effect).contains(name) && (monster || flag != 16 && flag != 32) { bits |= flag }
        data["type"]=bits
        if monster {
            guard vals.count>=4,let level=number(vals[1]),let atk=number(vals[2]) else { throw CardCatalogError.invalidData }
            let races=["戦士","魔法使い","天使","悪魔","アンデット","機械","水","炎","岩石","鳥獣","植物","昆虫","雷","ドラゴン","獣","獣戦士","恐竜","魚","海竜","爬虫類","サイキック","幻神獣","創造神","幻竜","サイバース","幻想魔"]
            let race=species.components(separatedBy:"／")[0].trimmingCharacters(in:.whitespacesAndNewlines)
            guard let index=races.firstIndex(where: { race == $0+"族" }) else { throw CardCatalogError.invalidData }
            data["race"]=Int64(1)<<index;data["attribute"]=["地属性":1,"水属性":2,"炎属性":4,"風属性":8,"光属性":16,"闇属性":32,"神属性":64][vals[0]] ?? 0
            data["atk"]=atk;data["def"]=number(vals[3]) ?? 0;var packed=level
            if bits & CardVocabulary.link != 0 {
                let arrows=groups(#"class="icon_img_set link([1-9]+)"#,in:html).first?.first ?? ""
                let map: [Character:Int64]=["1":1,"2":2,"3":4,"4":8,"6":32,"7":64,"8":128,"9":256];data["def"]=arrows.reduce(0) { $0+(map[$1] ?? 0) }
            }
            if pendulum,let scale=vals.first(where:{$0.contains("ペンデュラムスケール")}).flatMap(number) { packed |= scale<<24 | scale<<16 }
            data["level"]=packed
        } else { data["race"]=0;data["attribute"]=0;data["atk"]=0;data["def"]=0;data["level"]=0 }
        raw["data"]=data
        if (translated["types"] as? String ?? "").isEmpty { translated["types"]=monster ? species+"\n"+vals.prefix(4).joined(separator:" · ") : effect }
        raw["text"]=translated
        let printingSection=html.components(separatedBy:"<!-- ///CardDetail_packlist").dropFirst().first?.components(separatedBy:"id=\"relationCard\"").first ?? ""
        let printings=printingSection.components(separatedBy:"<div class=\"t_row").flatMap { row -> [[String:Any]] in
            guard let pid=groups(#"pid=([0-9]+)"#,in:row).first?.first,
                  let number=groups(#"<div class="card_number">(.*?)</div>"#,in:row).first?.first.map(clean),
                  let pack=groups(#"<div class="pack_name[^\"]*"[^>]*>(.*?)</div>"#,in:row).first?.first.map(clean) else{return []}
            let date=groups(#"<div class="time">\s*([0-9-]+)"#,in:row).first?.first ?? ""
            return groups(#"<div class="lr_icon[^"]*\brid_([0-9]+)\b[^"]*"[^>]*>\s*<p>(.*?)</p>\s*<span[^>]*>(.*?)</span>"#,in:row).map { ["pid":pid,"number":number,"pack":pack,"date":date,"rid":$0[0],"rarity":clean($0[1]),"rarity_name":clean($0[2])] }
        }
        raw["official_ja"]=["text":desc,"pdesc":pdesc,"notes":all.first(where:{$0.contains("公式のデュエルでは使用できません")}) ?? "","printings":printings]
        return try JSONSerialization.data(withJSONObject:raw,options:[.sortedKeys])
    }
}


enum CatalogSource:String,CaseIterable,Identifiable,Sendable {
    case packs,cnPacks,ocg,tcg,chinese,neuron,cards,translations,jhs
    var id:String {rawValue}
    var title:String {switch self {
        case .packs:"OCG 日文卡包与收录"
        case .cnPacks:"简中卡包与官方名称、文本"
        case .ocg:"OCG 禁限卡表"
        case .tcg:"TCG 禁限卡表"
        case .chinese:"简中禁限卡表"
        case .neuron:"Neuron 卡图"
        case .cards:"官方卡牌资料"
        case .translations:"NW 译名与文本"
        case .jhs:"集换社收录与版本"
    }}
    var origin:String {switch self {
        case .packs,.ocg,.tcg,.cards:"游戏王官方数据库"
        case .chinese,.cnPacks:"游戏王简中官方数据库"
        case .neuron:"Neuron"
        case .translations:"百鸽数据库"
        case .jhs:"集换社"
    }}
    static func banlist(_ format:CardFormat)->Self {switch format {case .ocg:.ocg;case .tcg:.tcg;case .simplified:.chinese}}
}
enum CatalogSourcePhase:String,Sendable {
    case waiting="待检查",checking="检查中",current="无更新",available="有更新",updating="更新中",complete="已更新",failed="失败",dependent="随资料更新",cancelled="已取消",pending="待补齐"
}
struct CatalogSourceStatus:Sendable {
    var phase:CatalogSourcePhase = .waiting
    var detail=""
}
struct CatalogSourceEvent:Sendable {
    let source:CatalogSource
    let phase:CatalogSourcePhase
    let detail:String
}
typealias CatalogSourceObserver = @Sendable (CatalogSourceEvent) async -> Void

struct BanlistVersionRequest:Sendable {let format:CardFormat;let date:String}
struct CatalogUpdatePlan:Sendable {
    let packs:[CollectionPack]
    let banlists:[BanlistSnapshot]
    let neuron:NeuronUpdateProbe
    let estimatedBytes:Int64
    var history:[BanlistVersionRequest]=[]
    var jhsRetryIDs:[Int64]=[]
    var nwRetryIDs:[Int64]=[]
    var officialTextRetryIDs:[Int64]=[]
    var coreChanges:Bool {!packs.isEmpty || !banlists.isEmpty || !history.isEmpty || neuron.hasChanges}
    var hasChanges:Bool {coreChanges || !jhsRetryIDs.isEmpty || !nwRetryIDs.isEmpty || !officialTextRetryIDs.isEmpty}
    var affectedSources:[CatalogSource] {
        var result:[CatalogSource]=[]
        if packs.contains(where:{$0.locale=="ja"}) {result.append(.packs)}
        if packs.contains(where:{$0.locale=="cn"}) || !officialTextRetryIDs.isEmpty {result.append(.cnPacks)}
        for format in CardFormat.allCases where banlists.contains(where:{$0.format==format.rawValue}) || history.contains(where:{$0.format==format}) {result.append(.banlist(format))}
        if neuron.hasChanges {result.append(.neuron)}
        if coreChanges {result += [.cards,.translations,.jhs]}
        else if !jhsRetryIDs.isEmpty {result.append(.jhs)}
        if !nwRetryIDs.isEmpty && !result.contains(.translations) {result.append(.translations)}
        return result
    }
    var itemLabels:[String] {
        affectedSources.map {source in
            switch source {
            case .packs: "OCG 日文卡包与收录：\(packs.filter{$0.locale=="ja"}.count) 个卡包"
            case .cnPacks: "简中卡包与官方名称、文本：\(packs.filter{$0.locale=="cn"}.count) 个卡包 · \(officialTextRetryIDs.count) 张待补齐"
            case .neuron: "Neuron 卡图：\(neuron.version)"
            case .cards: "官方卡牌资料：按本次新增或变更卡牌补齐"
            case .translations: "NW 名称与文本：随变更卡牌更新 · \(nwRetryIDs.count) 张待补齐"
            case .jhs: "集换社收录与版本："+(jhsRetryIDs.isEmpty ? "随变更卡牌更新":"重试 \(jhsRetryIDs.count) 张待补齐卡牌")
            default: source.title+"："+(banlists.first(where:{CatalogSource.banlist(CardFormat(rawValue:$0.format) ?? .ocg)==source})?.date ?? "补齐历史版本")
            }
        }
    }
    var sizeLabel:String {ByteCountFormatter.string(fromByteCount:estimatedBytes,countStyle:.file)}
}
protocol CatalogArtworkSource:Sendable {
    func probe()async throws->NeuronUpdateProbe
    func check(force:Bool)async throws->Bool
    func cardTexts()async throws->[NeuronCardText]
    func synchronize(progress:@escaping @Sendable(String)async->Void)async throws->Bool
}
extension CatalogArtworkSource {
    func synchronize(progress:@escaping @Sendable(String)async->Void)async throws->Bool {try await check(force:true)}
}
extension NeuronArtworkStore:CatalogArtworkSource {}
struct CatalogJHSRefresh:Sendable {
    let cid:Int64
    let records:[CardPrinting]
    let method:String
    let detail:String
    var complete:Bool {!records.isEmpty}
}
struct CatalogTranslationRefresh:Sendable {
    let cid:Int64
    var official:[String:String]?=nil
    var nw:[String:String]?=nil
    var supplement:Data?=nil
    var requiresOfficial=false
}
protocol CatalogJHSSource:Sendable {func search(keyword:String)async throws->[CardPrinting]}
struct CatalogJHSClient:CatalogJHSSource {
    func search(keyword:String)async throws->[CardPrinting] {try await PrintingSearch.search(keyword:keyword)}
}
actor CardUpdater {
    let transport:any APITransport
    let artwork:any CatalogArtworkSource
    let jhs:any CatalogJHSSource
    init(transport:any APITransport=NetworkTransport(),artwork:any CatalogArtworkSource=NeuronArtworkStore.shared,jhs:any CatalogJHSSource=CatalogJHSClient()){self.transport=transport;self.artwork=artwork;self.jhs=jhs}
    func refreshJHS(cid:Int64,passcode:Int64?,names:[CardName],known:Set<Int64>)async throws->CatalogJHSRefresh {
        let exact=passcode.map{$0>0 && $0<=99999999} ?? false
        let keyword=exact ? String(format:"%08lld",passcode!):(names.first{$0.source=="jp_name"}?.name ?? names.first?.name ?? "")
        guard !keyword.isEmpty else {return .init(cid:cid,records:[],method:"pending",detail:"暂无可用于查询的卡密或名称")}
        do {
            let all=try await jhs.search(keyword:keyword)
            let valid=all.filter{$0.sourceCardID.map{$0>0} == true && $0.versionID>0 && !$0.number.isEmpty && !$0.rarity.isEmpty}
            guard valid.count==all.count else {throw CardCatalogError.invalidData}
            let ids=Set(valid.compactMap(\.sourceCardID))
            let selected:[CardPrinting]
            if !known.isEmpty {selected=valid.filter{known.contains($0.sourceCardID!)}}
            else if ids.count==1 && (exact || valid.allSatisfy{$0.matches(names:names)}) {selected=valid}
            else {selected=[]}
            guard !selected.isEmpty else {return .init(cid:cid,records:[],method:"pending",detail:all.isEmpty ? "集换社尚无版本，下次继续补齐":"版本身份尚不能确认，下次继续核对")}
            return .init(cid:cid,records:selected,method:known.isEmpty ? (exact ? "passcode_unique":"exact_name_unique"):"verified_card_id",detail:"已读取 \(selected.count) 条版本")
        } catch is CancellationError {throw CancellationError()}
        catch {try Task.checkCancellation();return .init(cid:cid,records:[],method:"pending",detail:"本次查询失败，下次继续补齐")}
    }
    private func fetch(_ url:URL)async throws->Data {
        var request=URLRequest(url:url);request.timeoutInterval=15;request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 Vrains",forHTTPHeaderField:"User-Agent")
        let (data,response)=try await transport.data(for:request)
        guard response.statusCode==200,!data.isEmpty,data.count<8*1024*1024 else{throw CardCatalogError.invalidData};return data
    }
    private func optionalFetch(_ url:URL)async throws->Data? {
        do {return try await fetch(url)}
        catch is CancellationError {throw CancellationError()}
        catch {try Task.checkCancellation();return nil}
    }
    private func translation(cid:Int64,pendulum:Bool,requiresOfficial:Bool,needsNW:Bool=true)async throws->CatalogTranslationRefresh {
        var update=CatalogTranslationRefresh(cid:cid,requiresOfficial:requiresOfficial)
        // Probe the official locale directly; a third-party sc_name is not evidence of availability.
        let url=URL(string:"\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/card_search.action?ope=2&cid=\(cid)&request_locale=cn")!
        if let bytes=try await optionalFetch(url) {
            update.official=try? OfficialHTML.chineseTranslation(cid:cid,html:String(decoding:bytes,as:UTF8.self),pendulum:pendulum)
        }
        if update.official==nil && needsNW {
            let url=URL(string:"\(PrivateConfiguration.value("translationOrigin"))/api/v0/?search=\(cid)")!
            if let bytes=try await optionalFetch(url),let root=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
               let row=(root["result"] as? [[String:Any]])?.first(where:{($0["cid"] as? NSNumber)?.int64Value==cid}) {
                update.supplement=try JSONSerialization.data(withJSONObject:row)
                if let name=row["nwbbs_n"] as? String,let text=row["text"] as? [String:Any],let desc=text["desc"] as? String {
                    update.nw=["name":name,"text":desc,"pdesc":text["pdesc"] as? String ?? "","types":text["types"] as? String ?? ""]
                }
            }
        }
        return update
    }
    func check(database:CardDatabase,observe:CatalogSourceObserver?=nil)async throws->CatalogUpdatePlan {
        await observe?(.init(source:.packs,phase:.checking,detail:"比对官网卡包目录"))
        let catalog=try await fetch(CollectionService.catalogURL("ja"))
        let remote=try CollectionParser.japanese(String(decoding:catalog,as:UTF8.self))
        let local=try await database.collectionPacks(locale:"ja"),known=Dictionary(uniqueKeysWithValues:local.map{($0.id,$0)})
        let complete=try await database.completePackIDs(locale:"ja")
        // Public listings may precede release. Pack existence alone is not membership completeness.
        var changed=remote.filter{known[$0.id]==nil || known[$0.id]?.date != $0.date || !complete.contains($0.id)}
        await observe?(.init(source:.packs,phase:changed.isEmpty ? .current:.available,detail:changed.isEmpty ? "已校验官网目录与本地收录状态":"发现 \(changed.count) 个新增或待补齐卡包"))
        await observe?(.init(source:.cnPacks,phase:.checking,detail:"比对简中官网卡包目录"))
        let cnRemote=try CollectionParser.chinese(try await fetch(CollectionService.catalogURL("cn")))
        let cnLocal=try await database.collectionPacks(locale:"cn"),cnKnown=Dictionary(uniqueKeysWithValues:cnLocal.map{($0.id,$0)})
        let cnComplete=try await database.completePackIDs(locale:"cn")
        let formatter=DateFormatter();formatter.calendar=Calendar(identifier:.gregorian);formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(identifier:"Asia/Shanghai");formatter.dateFormat="yyyy-MM-dd"
        let today=formatter.string(from:.now)
        let cnChanged=cnRemote.filter{$0.date<=today && (cnKnown[$0.id]==nil || cnKnown[$0.id]?.date != $0.date || !cnComplete.contains($0.id))}
        changed+=cnChanged
        let nwRetry=try await database.pendingNWCardIDs(),officialRetry=try await database.pendingOfficialTextIDs()
        await observe?(.init(source:.cnPacks,phase:cnChanged.isEmpty && officialRetry.isEmpty ? .current:.available,detail:"\(cnChanged.count) 个卡包 · \(officialRetry.count) 张官方名称与文本待补齐"))
        await observe?(.init(source:.translations,phase:nwRetry.isEmpty ? .dependent:.available,detail:nwRetry.isEmpty ? "随变更卡牌查询名称与文本":"\(nwRetry.count) 张名称或文本待补齐"))
        var bans:[BanlistSnapshot]=[],history:[BanlistVersionRequest]=[]
        for format in CardFormat.allCases {
            let source=CatalogSource.banlist(format)
            await observe?(.init(source:source,phase:.checking,detail:"比对当期与历史版本"))
            let bytes=try await fetch(BanlistRepository.url(format:format))
            let snapshot=try format == .simplified ? BanlistParser.chinese(bytes):BanlistParser.html(String(decoding:bytes,as:UTF8.self),format:format)
            let previous=try await database.banlist(format:format)
            let existingDates=Set(previous?.versions ?? [])
            history += snapshot.versions.filter{$0 != snapshot.date && !existingDates.contains($0)}.map{BanlistVersionRequest(format:format,date:$0)}
            let old=previous?.entries.sorted{$0.cid<$1.cid}.map{"\($0.cid):\($0.status)"}
            let new=snapshot.entries.sorted{$0.cid<$1.cid}.map{"\($0.cid):\($0.status)"}
            let changed=previous?.date != snapshot.date || old != new
            if changed {bans.append(snapshot)}
            let missing=history.filter{$0.format==format}.count
            await observe?(.init(source:source,phase:changed || missing>0 ? .available:.current,detail:"当期 \(snapshot.date)"+(missing>0 ? " · 待补 \(missing) 期历史":"")))
        }
        await observe?(.init(source:.neuron,phase:.checking,detail:"检查资源版本与卡图目录"))
        let probe=try await artwork.probe()
        let version=try await database.state("neuron_data_version")
        let neuron=NeuronUpdateProbe(version:probe.version,estimatedBytes:probe.estimatedBytes,hasChanges:probe.hasChanges || NeuronArtworkStore.newer(probe.version,than:version))
        await observe?(.init(source:.neuron,phase:neuron.hasChanges ? .available:.current,detail:"远端版本 \(neuron.version) · 卡图完整保存到 App"))
        let jhsRetry=try await database.pendingJHSCardIDs()
        await observe?(.init(source:.jhs,phase:jhsRetry.isEmpty ? .dependent:.available,detail:jhsRetry.isEmpty ? "随变更卡牌更新；内置资料为构建时基线":"\(jhsRetry.count) 张卡牌等待继续补齐"))
        // HTML is estimated at 150 KB per card, 100 cards per new pack. Japanese artwork payloads are included in the Neuron estimate.
        let estimate=Int64(changed.count)*15_000_000+Int64(bans.count+history.count)*200_000+neuron.estimatedBytes+Int64(jhsRetry.count+nwRetry.count+officialRetry.count)*200_000
        return .init(packs:changed,banlists:bans,neuron:neuron,estimatedBytes:max(estimate,neuron.hasChanges ? 1_000_000:0),history:history,jhsRetryIDs:jhsRetry,nwRetryIDs:nwRetry,officialTextRetryIDs:officialRetry)
    }
    func install(_ plan:CatalogUpdatePlan,database:CardDatabase,progress:@escaping @Sendable(String)async->Void,observe:CatalogSourceObserver?=nil)async throws {
        var banlists=plan.banlists
        for version in plan.history {
            await observe?(.init(source:.banlist(version.format),phase:.updating,detail:"补齐历史版本 "+version.date))
            await progress("补齐历史禁限卡表 "+version.date)
            let bytes=try await fetch(BanlistRepository.url(format:version.format,date:version.date))
            banlists.append(try BanlistParser.html(String(decoding:bytes,as:UTF8.self),format:version.format,date:version.date))
            try await Task.sleep(for:.milliseconds(400))
        }
        var ids=Set<Int64>(),cnIDs=Set<Int64>(),members:[String:[CollectionCard]]=[:]
        for pack in plan.packs {
            await observe?(.init(source:pack.locale == "cn" ? .cnPacks:.packs,phase:.updating,detail:pack.name))
            await progress("读取卡包："+pack.name)
            let url=URL(string:"\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/card_search.action?ope=1&sess=1&pid=\(pack.id)&rp=99999&request_locale=\(pack.locale)")!
            let cards=try CollectionParser.japaneseCards(String(decoding:try await fetch(url),as:UTF8.self))
            members[pack.locale+":"+pack.id]=cards
            if pack.locale == "cn" {cnIDs.formUnion(cards.map(\.id))}
            else {ids.formUnion(cards.map(\.id))}
        }
        let knownCN=try await database.banlistCards(cids:Array(cnIDs))
        ids.formUnion(cnIDs.filter{knownCN[$0]==nil})
        if plan.neuron.hasChanges {
            await observe?(.init(source:.neuron,phase:.updating,detail:"下载目录与卡牌映射 \(plan.neuron.version)"))
            await progress("更新 Neuron 卡图目录")
            _ = try await artwork.synchronize(progress:progress)
            let changed=try await database.changedNeuronCards(artwork.cardTexts())
            ids.formUnion(changed)
        }
        for snapshot in banlists {
            let existing=try await database.banlistCards(cids:snapshot.entries.map(\.cid))
            ids.formUnion(snapshot.entries.map(\.cid).filter{existing[$0]==nil})
        }
        var payloads:[Data]=[],translations:[CatalogTranslationRefresh]=[]
        for (index,cid) in ids.sorted().enumerated() {
            try Task.checkCancellation();await progress("更新卡牌资料 \(index+1)/\(ids.count)")
            await observe?(.init(source:.cards,phase:.updating,detail:"\(index+1) / \(ids.count) 张卡牌"))
            let url=URL(string:"\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/card_search.action?ope=2&cid=\(cid)&request_locale=ja")!
            let html=String(decoding:try await fetch(url),as:UTF8.self)
            await observe?(.init(source:.translations,phase:.updating,detail:"读取 CID \(cid) 的名称与文本"))
            let update=try await translation(cid:cid,pendulum:html.contains("class=\"CardText pen\""),requiresOfficial:cnIDs.contains(cid) || plan.officialTextRetryIDs.contains(cid))
            let bytes=try OfficialHTML.rawCard(cid:cid,japanese:html,chinese:nil,supplement:update.supplement)
            var raw=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
            if let official=update.official {raw["official_cn"]=official;raw["sc_name"]=official["name"]}
            else {raw.removeValue(forKey:"sc_name")}
            payloads.append(try JSONSerialization.data(withJSONObject:raw));translations.append(update)
            try await Task.sleep(for:.milliseconds(400))
        }
        let textIDs=cnIDs.union(plan.nwRetryIDs).union(plan.officialTextRetryIDs).subtracting(ids)
        for cid in textIDs.sorted() {
            let officialComplete=try await database.hasCompleteOfficialText(cid:cid)
            let chineseComplete=try await database.hasCompleteChineseText(cid:cid)
            guard !officialComplete && (cnIDs.contains(cid) || plan.officialTextRetryIDs.contains(cid) || !chineseComplete) else{continue}
            try Task.checkCancellation()
            await progress("补齐名称与文本：CID \(cid)")
            await observe?(.init(source:cnIDs.contains(cid) || plan.officialTextRetryIDs.contains(cid) ? .cnPacks:.translations,phase:.updating,detail:"补齐 CID \(cid) 的名称与文本"))
            let details=try await database.details(cid:cid)
            translations.append(try await translation(cid:cid,pendulum:details.card.isPendulum,requiresOfficial:cnIDs.contains(cid) || plan.officialTextRetryIDs.contains(cid),needsNW:!chineseComplete))
            try await Task.sleep(for:.milliseconds(400))
        }
        let existingCards=try await database.banlistCards(cids:Array(ids))
        var fresh:[Int64:(Int64?,[CardName])]=[:]
        for bytes in payloads {
            let card=try JSONDecoder().decode(YGOSourceCard.self,from:bytes)
            let raw=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
            let names=["jp_name","sc_name","nwbbs_n"].compactMap {key -> CardName? in (raw[key] as? String).map{CardName(source:key,name:$0)}}
            var translatedNames=names
            if let update=translations.first(where:{$0.cid==card.cid}),let name=update.official?["name"] ?? update.nw?["name"] {translatedNames.append(CardName(source:update.official==nil ? "nwbbs_n":"sc_name",name:name))}
            fresh[card.cid]=(card.id>0 ? card.id:existingCards[card.cid]?.passcode,translatedNames)
        }
        var jhsUpdates:[CatalogJHSRefresh]=[]
        let jhsIDs=ids.union(plan.jhsRetryIDs).sorted()
        for (index,cid) in jhsIDs.enumerated() {
            try Task.checkCancellation()
            await progress("更新集换社收录 \(index+1)/\(jhsIDs.count)")
            await observe?(.init(source:.jhs,phase:.updating,detail:"\(index+1) / \(jhsIDs.count) 张卡牌"))
            let input:(Int64?,[CardName])
            if let value=fresh[cid] {input=value}
            else {let details=try await database.details(cid:cid);input=(details.card.passcode,details.names)}
            let known=try await database.verifiedJHSIDs(cid:cid)
            jhsUpdates.append(try await refreshJHS(cid:cid,passcode:input.0,names:input.1,known:known))
        }
        try Task.checkCancellation()
        await progress("校验并保存资料")
        try await database.applyUpdate(cards:payloads,packs:plan.packs,members:members,banlists:banlists,neuronVersion:plan.neuron.version,jhs:jhsUpdates,translations:translations)
    }
}

@MainActor
struct LaunchUpdateCheckSchedule {
    static let lastAttemptKey = "exodia.catalog.lastAutomaticUpdateAttempt"
    private let defaults: UserDefaults
    private let enabled: Bool
    init(defaults: UserDefaults = .standard, enabled: Bool = CardCatalog.automaticUpdateChecksEnabled,
         arguments: [String] = ProcessInfo.processInfo.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.enabled = enabled && !arguments.contains("--uitesting") && !arguments.contains("--verify-saved-account")
            && environment["XCTestConfigurationFilePath"] == nil && environment["XCTestBundlePath"] == nil
            && environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }
    func beginCheck(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        if let last = defaults.object(forKey: Self.lastAttemptKey) as? Date {
            guard last <= date, !calendar.isDate(last, inSameDayAs: date) else { return false }
        }
        // Claim the day before awaiting network work, including failed or cancelled attempts.
        defaults.set(date, forKey: Self.lastAttemptKey)
        return true
    }
}

@Observable @MainActor
final class CardCatalog {
    #if DEBUG
    static let automaticUpdateChecksEnabled = false
    #else
    static let automaticUpdateChecksEnabled = true
    #endif
    let database:CardDatabase
    let updater:CardUpdater
    private(set) var metadata:CardMetadata?
    private(set) var isUpdating=false
    private(set) var progress=""
    private(set) var revision=0
    private(set) var artworkRevision=0
    private(set) var artworkMessage:String?
    private(set) var pendingUpdate:CatalogUpdatePlan?
    var showUpdatePrompt=false
    var showUpdateFailure=false
    private(set) var sourceStatuses:[CatalogSource:CatalogSourceStatus]=[:]
    private(set) var localSources:[CatalogSource:String]=[:]
    private(set) var activeSource:CatalogSource?
    private(set) var isChecking=false
    private(set) var startupResolved=false
    private var installTask:Task<Void,Error>?
    private let launchChecks: LaunchUpdateCheckSchedule
    var canCancelUpdate:Bool {installTask != nil}
    var message:String?
    var selectedFormat=CardFormat(rawValue:UserDefaults.standard.string(forKey:"exodia.selectedCardFormat") ?? "") ?? .ocg {
        didSet{UserDefaults.standard.set(selectedFormat.rawValue,forKey:"exodia.selectedCardFormat")}
    }
    init(database:CardDatabase=CardDatabase(),transport:any APITransport=NetworkTransport(),artwork:any CatalogArtworkSource=NeuronArtworkStore.shared,jhs:any CatalogJHSSource=CatalogJHSClient(),launchChecks:LaunchUpdateCheckSchedule=LaunchUpdateCheckSchedule()) {
        self.database=database;updater=CardUpdater(transport:transport,artwork:artwork,jhs:jhs)
        self.launchChecks=launchChecks
    }
    func prepare()async {
        do{metadata=try await database.metadata();localSources=try await database.updateSourceOverview()}catch{message=error.localizedDescription}
    }
    func checkAtLaunch()async {
        startupResolved=false
        guard !isUpdating else { return }
        guard launchChecks.beginCheck() else {
            skipUpdate()
            return
        }
        await update()
    }
    func update(force:Bool=true)async {
        guard !isUpdating else{return}
        isUpdating=true;isChecking=true;progress="检查资料更新";message=nil;activeSource=nil
        pendingUpdate=nil;showUpdatePrompt=false;showUpdateFailure=false
        sourceStatuses=[:]
        sourceStatuses[.jhs] = .init(phase:.dependent,detail:"随变更卡牌更新；未查到的版本会持续补齐")
        sourceStatuses[.cards] = .init(phase:.dependent,detail:"根据卡包、禁限卡表及 Neuron 变更补齐")
        sourceStatuses[.translations] = .init(phase:.dependent,detail:"随变更卡牌查询；缺少名称、正文或灵摆文本时持续补齐")
        defer{isUpdating=false;isChecking=false;progress="";activeSource=nil}
        do {
            let plan=try await updater.check(database:database) {[weak self] event in await self?.receive(event)}
            try await database.recordCheck();metadata=try await database.metadata()
            if plan.hasChanges {
                pendingUpdate=plan
                for source in plan.affectedSources where [.cards,.translations,.jhs].contains(source) {sourceStatuses[source] = .init(phase:.available,detail:"按本次变更卡牌补齐；数量在下载目录后确定")}
                showUpdatePrompt=true
            }
            else{pendingUpdate=nil;startupResolved=true;message="资料已是最新。"}
        } catch {
            if let source=activeSource {sourceStatuses[source] = .init(phase:.failed,detail:"检查失败，可重试；本机资料仍可使用")}
            message="暂时无法检查资料更新。可重试或使用本机资料进入。";showUpdateFailure=true}
    }
    func skipUpdate(){showUpdatePrompt=false;showUpdateFailure=false;pendingUpdate=nil;startupResolved=true}
    func installPending()async {
        guard let plan=pendingUpdate,!isUpdating else{return}
        showUpdatePrompt=false;isUpdating=true;progress="准备更新"
        for source in plan.affectedSources {sourceStatuses[source] = .init(phase:.updating,detail:"等待下载或校验")}
        let task=Task {try await updater.install(plan,database:database,progress:{[weak self] status in await self?.setProgress(status)},observe:{[weak self] event in await self?.receive(event)})}
        installTask=task
        defer{installTask=nil;isUpdating=false;progress="";activeSource=nil}
        do {
            try await task.value
            for source in plan.affectedSources {sourceStatuses[source] = .init(phase:.complete,detail:"已校验并保存到本机")}
            let unresolved=try await database.pendingJHSCardIDs()
            if !unresolved.isEmpty {sourceStatuses[.jhs] = .init(phase:.pending,detail:"\(unresolved.count) 张卡牌尚未查到或核实版本，下次继续补齐")}
            let nwPending=try await database.pendingNWCardIDs(),cnPending=try await database.pendingOfficialTextIDs()
            if !nwPending.isEmpty {sourceStatuses[.translations] = .init(phase:.pending,detail:"\(nwPending.count) 张名称或文本待补齐，下次继续尝试")}
            if !cnPending.isEmpty {sourceStatuses[.cnPacks] = .init(phase:.pending,detail:"\(cnPending.count) 张官方简中名称或文本待补齐，下次继续尝试")}
            localSources=try await database.updateSourceOverview()
            metadata=try await database.metadata();revision+=1;artworkRevision+=1;pendingUpdate=nil;startupResolved=true;message=unresolved.isEmpty ? "资料更新完成。":"资料已更新，仍有 \(unresolved.count) 张卡牌的集换社版本待补齐，下次继续尝试。"
            if !nwPending.isEmpty || !cnPending.isEmpty {message="资料已更新，仍有名称或文本待补齐，下次检查更新时继续尝试。"}
        } catch {
            for source in plan.affectedSources {sourceStatuses[source] = .init(phase:task.isCancelled ? .cancelled:.failed,detail:"未提交本次资料，本机版本已保留")}
            if task.isCancelled {message="已取消更新，本机资料已保留。";skipUpdate()}
            else {message="更新未完成，本机资料已保留。";showUpdateFailure=true}
        }
    }
    func cancelUpdate(){installTask?.cancel()}
    func retryUpdate()async {showUpdateFailure=false;if pendingUpdate != nil{await installPending()}else{await update()}}
    private func receive(_ event:CatalogSourceEvent) {
        sourceStatuses[event.source] = .init(phase:event.phase,detail:event.detail)
        if event.phase == .checking || event.phase == .updating {
            activeSource=event.source
            progress=(event.phase == .checking ? "正在检查：":"正在更新：")+event.source.title
        }
    }
    private func setProgress(_ value:String){progress=value}
    func artworkCacheCleared(){artworkRevision+=1}
    func printingsChanged(){revision+=1}
}
