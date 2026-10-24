import SwiftUI

struct BanlistEntry:Codable,Identifiable,Sendable {
    let cid:Int64
    let name:String
    let status:Int
    let change:String
    var icon:String? = nil
    var changeIcon:String? {
        let names=["1":"icon_unlim_forb","2":"icon_unlim_limit","3":"icon_unlim_slim","11":"icon_forb_limit","12":"icon_forb_slim","13":"icon_forb_unlim","21":"icon_limit_forb","22":"icon_limit_slim","23":"icon_limit_unlim","31":"icon_slim_forb","32":"icon_slim_limit","33":"icon_slim_unlim"]
        if let value=names[change] {return value}
        if let icon {let name=icon.replacingOccurrences(of:".png",with:"");if names.values.contains(name){return name}}
        let parts=change.components(separatedBy:"-")
        let words=["禁止":"forb","限制":"limit","准限制":"slim","解除":"unlim","解除限制":"unlim"]
        if parts.count==2,let old=words[parts[0]],let new=words[parts[1]] {let value="icon_"+old+"_"+new;if names.values.contains(value){return value}}
        return nil
    }
    var isChanged:Bool {changeIcon != nil}
    var id:Int64 {cid}
    var changeDescription:String {
        if let icon=changeIcon,icon.hasPrefix("icon_unlim_"),status<3 {return "新"+["禁止","限制","准限制"][status]}
        let codes=["1":"新禁止","2":"新限制","3":"新准限制","11":"禁止 → 限制","12":"禁止 → 准限制","13":"禁止 → 解除限制","21":"限制 → 禁止","22":"限制 → 准限制","23":"限制 → 解除限制","31":"准限制 → 禁止","32":"准限制 → 限制","33":"准限制 → 解除限制"]
        if let text=codes[change]{return text}
        if change.isEmpty,isChanged {return "新"+["禁止","限制","准限制","解除限制"][status]}
        return change.components(separatedBy:"-").map{$0 == "解除" ? "解除限制":$0}.joined(separator:" → ")
    }
}
struct BanlistSnapshot:Codable,Sendable {
    let format:String
    let date:String
    let versions:[String]
    let entries:[BanlistEntry]
}
enum BanlistStatus:Int,CaseIterable,Identifiable {
    case forbidden,limited,semiLimited,released
    var id:Int {rawValue}
    var title:String {["禁止","限制","准限制","解除限制"][rawValue]}
    var explanation:String {["禁止投入卡组","主卡组、额外卡组与副卡组合计最多 1 张","主卡组、额外卡组与副卡组合计最多 2 张","已解除限制，合计最多 3 张"][rawValue]}
}

enum BanlistParser {
    static func html(_ html:String,format:CardFormat,date:String?=nil) throws ->BanlistSnapshot {
        let versions=OfficialHTML.groups(#"<option\s+value="(\d{4}-\d{2}-\d{2})""#,in:html).map{$0[0]}
        guard !versions.isEmpty,html.contains("forbiddenLimitedDate") else {throw CardCatalogError.invalidData}
        if let date,!versions.contains(date) {throw CardCatalogError.invalidData}
        // A requested historical date must actually be selected by the server.
        let selected=OfficialHTML.groups(#"<option\s+value="([^"]+)"[^>]*\bselected[^>]*>"#,in:html).first?.first
        if let date,selected != date {throw CardCatalogError.invalidData}
        var entries:[BanlistEntry]=[]
        let sections=["forbidden":0,"limited":1,"semi_limited":2,"release_of_restricted":3]
        for section in html.components(separatedBy:"<div id=\"list_").dropFirst() {
            let name=section.components(separatedBy:"\"")[0]
            guard let status=sections[name] else {continue}
            for row in section.components(separatedBy:"<div class=\"t_row").dropFirst() {
                guard let cid=OfficialHTML.groups(#"cid=(\d+)"#,in:row).first?.first.flatMap(Int64.init),
                      let name=OfficialHTML.groups(#"<span class="name">(.*?)</span>"#,in:row).first?.first else {continue}
                let change=OfficialHTML.groups(#"fltype_(\d+)"#,in:row).first?.first ?? ""
                entries.append(.init(cid:cid,name:OfficialHTML.clean(name),status:status,change:change))
            }
        }
        guard !entries.isEmpty,Set(entries.map(\.cid)).count == entries.count else {throw CardCatalogError.invalidData}
        return .init(format:format.rawValue,date:date ?? selected ?? versions[0],versions:versions,entries:entries)
    }
    static func chinese(_ bytes:Data) throws ->BanlistSnapshot {
        guard let root=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],root["code"] as? Int == 0,let lists=root["list"] as? [[String:Any]] else {throw CardCatalogError.invalidData}
        let statuses=["禁止卡":0,"限制卡":1,"准限制卡":2,"解除限制卡牌":3]
        var entries:[BanlistEntry]=[],date:String?
        for group in lists {
            guard let status=statuses[group["type"] as? String ?? ""],let cards=group["list"] as? [[String:Any]] else {continue}
            if let updated=group["updateTime"] as? String {date=String(updated.prefix(10))}
            for card in cards {
                guard let token=card["cardNo"] as? String,let cid=Int64(token),let name=card["cardName"] as? String else {throw CardCatalogError.invalidData}
                entries.append(.init(cid:cid,name:name,status:status,change:card["forbiddenCardType"] as? String ?? "",icon:card["forbiddenIcon"] as? String))
            }
        }
        guard let date,!entries.isEmpty,Set(entries.map(\.cid)).count == entries.count else {throw CardCatalogError.invalidData}
        return .init(format:CardFormat.simplified.rawValue,date:date,versions:[],entries:entries)
    }
}

actor BanlistRepository {
    static let shared=BanlistRepository()
    static func url(format:CardFormat,date:String?=nil)->URL {
        if format == .simplified {return URL(string:"\(PrivateConfiguration.value("localizedDatabaseOrigin"))/forbiddenCard/forbiddencard/cachelist?groupId=1")!}
        var parts=URLComponents(string:"\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/forbidden_limited.action")!
        parts.queryItems=[URLQueryItem(name:"request_locale",value:format.rawValue)]
        if let date {parts.queryItems?.append(URLQueryItem(name:"forbiddenLimitedDate",value:date))}
        return parts.url!
    }
}

struct BanlistHubScreen:View {
    @Environment(CardCatalog.self) private var catalog
    @State private var date=""
    @State private var status:BanlistStatus = .forbidden
    @State private var snapshot:BanlistSnapshot?
    @State private var cards:[Int64:CatalogCard]=[:]
    @State private var selected:CatalogCard?
    @State private var loading=false
    @State private var message:String?
    private var format:CardFormat {catalog.selectedFormat}
    private var current:BanlistSnapshot? {snapshot?.format == format.rawValue ? snapshot:nil}
    private var entries:[BanlistEntry] {(current?.entries.filter{$0.status == status.rawValue}.enumerated().sorted {a,b in a.element.isChanged == b.element.isChanged ? a.offset<b.offset:a.element.isChanged}.map(\.element)) ?? []}
    var body:some View {
        VStack(spacing:14) {
            Picker("禁限卡表",selection:Binding(get:{format},set:{catalog.selectedFormat=$0;date=""})) {
                ForEach(CardFormat.allCases){format in Text(format.title).tag(format)}
            }.pickerStyle(.segmented).accessibilityIdentifier("settings.banlist").padding(.horizontal,16)
            if let current {
                HStack {
                    if format == .simplified {
                        Label(current.date+" 适用",systemImage:"calendar").font(.subheadline)
                    } else {
                        Menu {
                            Button("最新禁限卡表") {date=""}
                            ForEach(current.versions,id:\.self) {version in Button(version){date=version}}
                        } label: {
                            Label(current.date+(date.isEmpty && current.date == current.versions.first ? " · 最新":""),systemImage:"calendar").font(.subheadline.weight(.medium))
                        }.accessibilityIdentifier("banlist.version").accessibilityLabel("禁限卡表版本").accessibilityValue(current.date)
                    }
                    Spacer()
                    if loading {ProgressView().controlSize(.small)}
                    Text("\(entries.count) 张").font(.subheadline).foregroundStyle(Design.secondary).accessibilityIdentifier("banlist.count")
                }.padding(.horizontal,20)
            }
            Picker("规制",selection:$status) {
                ForEach(BanlistStatus.allCases){Text($0.title).tag($0)}
            }.pickerStyle(.segmented).padding(.horizontal,16).accessibilityIdentifier("banlist.status")
            Text(status.explanation).font(.caption).foregroundStyle(Design.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).accessibilityIdentifier("banlist.explanation")
            if let message {Text(message).font(.caption).foregroundStyle(Design.secondary).padding(.horizontal,20).accessibilityIdentifier("banlist.message")}
            if current == nil,loading {Spacer();ProgressView();Spacer()}
            else if entries.isEmpty {ContentUnavailableView("暂无\(status.title)卡牌",systemImage:"rectangle.stack",description:Text("此版本没有列出这一类卡牌。"))}
            else {
                List(entries) {entry in
                    Button {if let card=cards[entry.cid]{selected=card}} label: {
                        HStack(spacing:14) {
                            CardArtwork(cid:entry.cid).frame(width:46,height:67).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:7) {
                                Text(cards[entry.cid]?.name ?? entry.name).font(.system(size:15,weight:.semibold)).foregroundStyle(Design.ink).lineLimit(2)
                                HStack(spacing:6) {
                                    if let change=entry.changeIcon {NeuronSprite(name:change).frame(width:64,height:16)}
                                    else if entry.status<3 {NeuronSprite(name:"03_deck_frame_"+NeuronCardLayout.limitName(entry.status)+"_3").frame(width:19,height:19)}
                                    else {NeuronSprite(name:"03_deck_limit_table_f_unlim").frame(width:64,height:16)}
                                    Text(entry.changeDescription.isEmpty ? status.title:entry.changeDescription).font(.system(size:12,weight:.medium))
                                }.foregroundStyle(Design.secondary)
                            }
                            Spacer(minLength:0)
                        }.padding(.vertical,5).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("banlist.card.\(entry.cid)")
                        .listRowBackground(Design.canvas)
                }.listStyle(.plain).scrollContentBackground(.hidden).accessibilityIdentifier("banlist.list")
            }
        }.padding(.top,12).background(Design.canvas).navigationTitle("禁限卡表").navigationBarTitleDisplayMode(.large)
            .task(id:"\(format.rawValue)-\(date)-\(catalog.revision)"){await load()}
            .sheet(item:$selected){CatalogCardDetailScreen(card:$0)}
    }
    @MainActor private func install(_ value:BanlistSnapshot) async {
        let translated=(try? await catalog.database.banlistCards(cids:value.entries.map(\.cid))) ?? [:]
        guard !Task.isCancelled else{return}
        cards=translated;snapshot=value
    }
    @MainActor private func load() async {
        let format=format,version=date.isEmpty ? nil:date
        loading=true;message=nil
        defer {if !Task.isCancelled {loading=false}}
        do {if let local=try await catalog.database.banlist(format:format,date:version){await install(local)}}
        catch is CancellationError {} catch {
            guard !Task.isCancelled else{return}
            message=current == nil ? "本机没有此版本的禁限卡表。":"暂时无法读取禁限卡表。"
        }
    }
}
