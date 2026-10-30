import SwiftUI

struct CollectionPack:Codable,Identifiable,Sendable {
    let id:String
    let locale:String
    let name:String
    let date:String
    let category:Int
    let group:String
}
struct CollectionRarity:Codable,Hashable,Sendable {
    let code:String;let name:String
    var colorHex:String? = nil
    var rid:String? = nil
    var identity:String { rid ?? OfficialRarityCatalog.definitions.first(where:{$0.code == code && $0.name == name})?.rid ?? (OfficialRarityCatalog.definitions.filter{$0.code == code}.count == 1 ? OfficialRarityCatalog.definitions.first{$0.code == code}?.rid:nil) ?? code }
    var displayLabel:String {
        guard let item=OfficialRarityCatalog.definitions.first(where:{$0.rid == identity}),
              OfficialRarityCatalog.definitions.filter({$0.code == item.code}).count > 1 else{return code}
        let normalized=item.name.replacingOccurrences(of:"（",with:"(").replacingOccurrences(of:"）",with:")")
        guard let begin=normalized.firstIndex(of:"("),let end=normalized[begin...].firstIndex(of:")") else{return item.code}
        return item.code+"（"+normalized[normalized.index(after:begin)..<end]+"）"
    }
    var displayOrder:Int { OfficialRarityCatalog.definitions.first(where:{$0.rid == identity})?.order ?? -1 }
    static func precedes(_ a:Self,_ b:Self)->Bool { a.displayOrder == b.displayOrder ? a.identity < b.identity:a.displayOrder > b.displayOrder }
    var isRarity:Bool {
        !code.isEmpty && code.unicodeScalars.allSatisfy{CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 +-/").contains($0)}
    }
    var color:Color {
        let hex=colorHex ?? Self.fallbackColor(code)
        let value=Int(hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0x9c9c9c
        return Color(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
    static func fallbackColor(_ code:String)->String {
        switch code {
        case "N","NR":return "#9c9c9c"
        case "R":return "#60ad91"
        case "SR":return "#6aa1cf"
        case "UR":return "#cfa15e"
        case "UTR","UL":return "#d87ce6"
        case "HR","HGR":return "#81bbba"
        case "CR","GR","PGR":return "#69b7aa"
        case "NPR","PR","P":return "#957fd5"
        default:return "#e86d6d"
        }
    }
}

/// Wraps chips using their intrinsic widths, including long official rarity codes.
struct RarityFlow:Layout {
    var spacing:CGFloat=6
    private func arrange(_ subviews:Subviews,width:CGFloat)->(CGSize,[CGPoint]) {
        var x:CGFloat=0,y:CGFloat=0,height:CGFloat=0,points:[CGPoint]=[]
        for view in subviews {
            let size=view.sizeThatFits(.unspecified)
            if x>0,x+size.width>width {x=0;y+=height+spacing;height=0}
            points.append(CGPoint(x:x,y:y));x+=size.width+spacing;height=max(height,size.height)
        }
        return (CGSize(width:width,height:y+height),points)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        arrange(subviews,width:proposal.width ?? 320).0
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let points=arrange(subviews,width:bounds.width).1
        for (index,view) in subviews.enumerated(){view.place(at:CGPoint(x:bounds.minX+points[index].x,y:bounds.minY+points[index].y),proposal:.unspecified)}
    }
}
struct RarityChip:View {
    let rarity:CollectionRarity
    var selected=false
    var filter=false
    var body:some View {
        Text(rarity.displayLabel).font(filter ? .subheadline.weight(.semibold):.caption.weight(.semibold))
            .padding(.horizontal,filter ? 13:8).padding(.vertical,filter ? 8:4)
            .foregroundStyle(selected ? Color.white:rarity.color)
            .background(rarity.color.opacity(selected ? 0.8:0.14),in:Capsule())
            .overlay(Capsule().strokeBorder(rarity.color.opacity(selected ? 1:0.55),lineWidth:1))
            .accessibilityLabel(rarity.code+"，"+rarity.name)
    }
}
struct CollectionCard:Codable,Identifiable,Sendable {
    let id:Int64;let name:String
    var rarities:[CollectionRarity]=[]
}
struct CollectionCategory:Identifiable,Equatable {
    let id:Int;let title:String
    static func options(_ locale:String)->[Self] {
        let values:[(Int,String)] = locale == "ja"
            ? [(0,"全部"),(1,"基本补充包"),(2,"预组卡组"),(3,"其他补充包"),(4,"决斗终端"),(11,"商品同捆"),(12,"书籍"),(13,"比赛"),(14,"推广"),(15,"游戏同捆")]
            : [(0,"全部"),(1,"补充"),(2,"新手"),(3,"主题"),(5,"始航牌组"),(8,"其他补充"),(11,"附录"),(13,"比赛"),(14,"推广")]
        return values.map{Self(id:$0.0,title:$0.1)}
    }
}
enum CollectionParser {
    static func japanese(_ html:String) throws ->[CollectionPack] {
        var result:[CollectionPack]=[]
        for row in html.components(separatedBy:"<div class=\"t_row").dropFirst() {
            guard let id=OfficialHTML.groups(#"pid=(\d+)"#,in:row).first?.first,
                  let date=OfficialHTML.groups(#"<div class="time">\s*(\d{4}/\d{2}/\d{2})"#,in:row).first?.first,
                  let name=OfficialHTML.groups(#"<p>(.*?)</p>"#,in:row).first?.first,
                  let raw=OfficialHTML.groups(#"\bpackc(\d+)\b"#,in:row).first?.first.flatMap(Int.init) else{continue}
            let category=raw
            let group=OfficialHTML.groups(#"<span class="ws_nowrap">(.*?)</span>"#,in:row).map{OfficialHTML.clean($0[0])}.joined(separator:" · ")
            result.append(.init(id:id,locale:"ja",name:OfficialHTML.clean(name),date:date.replacingOccurrences(of:"/",with:"-"),category:category,group:group))
        }
        guard !result.isEmpty,Set(result.map(\.id)).count == result.count else{throw CardCatalogError.invalidData};return result
    }
    static func chinese(_ data:Data) throws ->[CollectionPack] {
        let root=try object(data)
        guard let response=root["response"] as? [String:Any],let groups=response["packList"] as? [[String:Any]] else{throw CardCatalogError.invalidData}
        var result:[CollectionPack]=[]
        for group in groups {
            guard let items=group["packInfoList"] as? [[String:Any]] else{throw CardCatalogError.invalidData}
            for row in items {
                guard let id=row["packId"] as? String,let name=row["packName"] as? String,let date=row["releaseDate"] as? String,let category=row["packClass"] as? Int else{throw CardCatalogError.invalidData}
                result.append(.init(id:id,locale:"cn",name:name,date:String(date.prefix(10)),category:category,group:[row["packClassName"] as? String,row["packSubClassName"] as? String].compactMap{$0}.joined(separator:" · ")))
            }
        }
        guard !result.isEmpty,Set(result.map(\.id)).count == result.count else{throw CardCatalogError.invalidData};return result
    }
    static func object(_ data:Data) throws ->[String:Any] {
        var value=try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
        if let string=value as? String {value=try JSONSerialization.jsonObject(with:Data(string.utf8))}
        guard let root=value as? [String:Any],let result=root["result"] as? [String:Any],result["code"] as? Int == 200000 else{throw CardCatalogError.invalidData};return root
    }
    static func japaneseCards(_ html:String) throws ->[CollectionCard] {
        var result:[CollectionCard]=[],seen:Set<Int64>=[]
        let reported=OfficialHTML.groups(#"検索結果 ([0-9,]+)件"#,in:html).first?.first
            ?? OfficialHTML.groups(#"全([0-9,]+)枚"#,in:html).first?.first
            ?? OfficialHTML.groups(#"Search Results:\s*[0-9,]+\s*-\s*[0-9,]+\s*of\s*([0-9,]+)"#,in:html).first?.first
            ?? OfficialHTML.groups(#"Total of\s*([0-9,]+)\s*Card\(s\)"#,in:html).first?.first
        let total=reported.flatMap{Int($0.replacingOccurrences(of:",",with:""))}
        let rows=html.components(separatedBy:"<div class=\"t_row").dropFirst()
        var count=0
        for row in rows {
            guard let cid=OfficialHTML.groups(#"class="cid"\s+value="(\d+)""#,in:row).first?.first.flatMap(Int64.init) else{continue}
            count+=1
            let name=OfficialHTML.groups(#"<span class="card_name">(.*?)</span>"#,in:row).first?.first.map(OfficialHTML.clean) ?? "卡牌 \(cid)"
            let rarities=OfficialHTML.groups(#"<div class="lr_icon[^\"]*\brid_([0-9]+)\b[^\"]*"([^>]*)>\s*<p>(.*?)</p>\s*<span[^>]*>(.*?)</span>"#,in:row).map{item in
                CollectionRarity(code:OfficialHTML.clean(item[2]),name:OfficialHTML.clean(item[3]),colorHex:OfficialHTML.groups(#"background-color:\s*(#[0-9a-fA-F]{6})"#,in:item[1]).first?.first,rid:item[0])
            }
            guard !rarities.isEmpty else{throw CardCatalogError.invalidData}
            if seen.insert(cid).inserted {result.append(.init(id:cid,name:name,rarities:rarities.reduce(into:[]){if !$0.contains($1){$0.append($1)}}))}
            else if let index=result.firstIndex(where:{$0.id==cid}) {
                for rarity in rarities where !result[index].rarities.contains(rarity) {result[index].rarities.append(rarity)}
            }
        }
        guard !result.isEmpty,let total,count==total else{throw CardCatalogError.invalidData};return result
    }
    static func chineseCards(_ data:Data) throws ->[CollectionCard] {
        let root=try object(data)
        guard let response=root["response"] as? [String:Any],let list=response["cardList"] as? [[String:Any]],let total=response["total"] as? Int,list.count>=total,!list.isEmpty else{throw CardCatalogError.invalidData}
        var result:[CollectionCard]=[],seen:Set<Int64>=[]
        for row in list {
            guard let cid=(row["cardId"] as? NSNumber)?.int64Value,let name=row["cardName"] as? String else{throw CardCatalogError.invalidData}
            if seen.insert(cid).inserted {result.append(.init(id:cid,name:name))}
        }
        return result
    }
}

enum CollectionService {
    static func catalogURL(_ locale:String)->URL {
        if locale == "ja" {return URL(string:"\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/card_list.action?request_locale=ja")!}
        return URL(string:"\(PrivateConfiguration.value("localizedDatabaseOrigin"))/konami/packlist?openFrom=0&openEnd=\(Int64(Date().timeIntervalSince1970*1000))&mode=0&size=99999")!
    }
    static func cards(_ pack:CollectionPack,database:CardDatabase,force:Bool=false)async throws->[CollectionCard] {
        try await database.collectionCards(pack)
    }
}

struct CollectionScreen:View {
    @Environment(CardCatalog.self) private var catalog
    @State private var locale="ja"
    @State private var category=0
    @State private var ascending=false
    @State private var packs:[CollectionPack]=[]
    @State private var busy=false
    @State private var message:String?
    private var visible:[CollectionPack] {
        packs.filter{category == 0 || $0.category == category}.sorted{a,b in a.date == b.date ? a.id<b.id:ascending ? a.date<b.date:a.date>b.date}
    }
    var body:some View {
        VStack(spacing:12) {
            Picker("收录语言",selection:$locale) {Text("OCG（日文）").tag("ja");Text("简体中文").tag("cn")}.pickerStyle(.segmented).padding(.horizontal,16).accessibilityIdentifier("collection.locale")
            HStack {
                Text("排序").font(.subheadline);Spacer()
                Menu {
                    Picker("顺序",selection:$ascending) {Text("升序").tag(true);Text("降序").tag(false)}
                } label: {
                    Label("发售日",systemImage:ascending ? "arrow.up":"arrow.down").frame(minHeight:44)
                }.accessibilityLabel("卡包排序").accessibilityValue(ascending ? "发售日 · 升序":"发售日 · 降序").accessibilityIdentifier("collection.sort")
            }.padding(.horizontal,16)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {ForEach(CollectionCategory.options(locale)){item in
                    Button {category=item.id} label:{Text(item.title).font(.subheadline)}
                        .selectionActionStyle(category == item.id).accessibilityIdentifier("collection.category.\(item.id)").accessibilityAddTraits(category == item.id ? .isSelected:[])
                }}.padding(.horizontal,16)
            }.accessibilityIdentifier("collection.categories")
            HStack {Text("\(visible.count) 个卡包").accessibilityIdentifier("collection.count");Spacer();if busy {ProgressView().controlSize(.small)}}.font(.caption).foregroundStyle(Design.secondary).padding(.horizontal,20)
            if let message {Text(message).font(.caption).foregroundStyle(Design.secondary).padding(.horizontal,20)}
            List {
                ForEach(visible){pack in row(pack)}
            }.listStyle(.plain).scrollContentBackground(.hidden).accessibilityIdentifier("collection.list")
        }.padding(.top,12).background(Design.canvas).navigationTitle("收录").navigationBarTitleDisplayMode(.large)
            .task(id:"\(locale)-\(catalog.revision)"){packs=(try? await catalog.database.collectionPacks(locale:locale)) ?? [];message=nil}
            .onChange(of:locale){_,_ in category=0}
    }
    private func row(_ pack:CollectionPack)->some View {
        NavigationLink {CollectionPackScreen(pack:pack)} label:{
            HStack(spacing:12) {
                Image(systemName:"shippingbox").font(.system(size:22)).foregroundStyle(Design.accent).frame(width:36)
                VStack(alignment:.leading,spacing:6) {
                    Text(pack.name).font(.system(size:15,weight:.semibold)).foregroundStyle(Design.ink)
                    Text(pack.date+" · "+(CollectionCategory.options(pack.locale).first{$0.id == pack.category}?.title ?? pack.group)).font(.caption).foregroundStyle(Design.secondary)
                }.padding(.vertical,7)
            }
        }.listRowBackground(Design.canvas).accessibilityIdentifier("collection.pack.\(pack.id)")
    }

}

struct CollectionPackScreen:View {
    let pack:CollectionPack
    @Environment(CardCatalog.self) private var catalog
    @State private var entries:[CollectionCard]=[]
    @State private var cards:[Int64:CatalogCard]=[:]
    @State private var rarity=""
    private var rarities:[CollectionRarity] {
        var seen=Set<String>()
        return entries.flatMap(\.rarities).filter{seen.insert($0.identity).inserted}.sorted(by:CollectionRarity.precedes)
    }
    private var visible:[CollectionCard] {entries.filter{rarity.isEmpty || $0.rarities.contains{$0.identity == rarity}}}
    @State private var selected:CatalogCard?
    @State private var busy=false
    @State private var message:String?
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text(pack.name).font(.title3.bold()).padding(.horizontal,20)
            Text(pack.date+" · 收录 \(entries.count) 种卡牌").font(.caption).foregroundStyle(Design.secondary).padding(.horizontal,20).accessibilityIdentifier("collection.cards.count")
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    Button {rarity=""} label:{RarityChip(rarity:.init(code:"全部",name:"全部罕贵度",colorHex:"#9c9c9c"),selected:rarity.isEmpty,filter:true)}
                        .accessibilityIdentifier("collection.rarity.all")
                    ForEach(rarities,id:\.identity){item in
                        Button {rarity = rarity == item.identity ? "":item.identity} label:{RarityChip(rarity:item,selected:rarity == item.identity,filter:true)}
                            .accessibilityIdentifier("collection.rarity."+item.identity).accessibilityAddTraits(rarity == item.identity ? .isSelected:[])
                    }
                }.buttonStyle(.plain).padding(.horizontal,20)
            }.accessibilityIdentifier("collection.rarities")
            if let message {Text(message).font(.caption).foregroundStyle(Design.secondary).padding(.horizontal,20)}
            if busy,entries.isEmpty {ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity)}
            else {
                List(visible) {entry in
                    Button {selected=cards[entry.id]} label:{
                        HStack(alignment:.top,spacing:14) {
                            CardArtwork(cid:entry.id).frame(width:46,height:67).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:8) {
                                Text(cards[entry.id]?.name ?? entry.name).font(.system(size:15,weight:.medium)).foregroundStyle(Design.ink)
                                RarityFlow {
                                    ForEach(entry.rarities.sorted(by:CollectionRarity.precedes),id:\.identity){RarityChip(rarity:$0)}
                                }

                            }
                            Spacer()
                        }.padding(.vertical,4).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(Design.canvas).accessibilityIdentifier("collection.card.\(entry.id)")
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.padding(.top,10).background(Design.canvas).navigationTitle("卡包收录").navigationBarTitleDisplayMode(.inline)
            .task{await load()}.sheet(item:$selected){CatalogCardDetailScreen(card:$0)}

    }
    @MainActor private func install(_ values:[CollectionCard]) async {
        let local=(try? await catalog.database.banlistCards(cids:values.map(\.id))) ?? [:]
        guard !Task.isCancelled else{return};cards=local;entries=values
    }
    @MainActor private func load(force:Bool=false) async {
        busy=true;defer{busy=false};message=nil
        if let cached=try? await catalog.database.collectionCards(pack),!cached.isEmpty {await install(cached)}
        do {let values=try await CollectionService.cards(pack,database:catalog.database,force:force);try Task.checkCancellation();await install(values)}
        catch is CancellationError {} catch {message=entries.isEmpty ? "暂时无法获取卡包内容，请稍后更新。":"暂时无法更新，正在显示本地收录。"}
    }
}

// Official rid identity is independent of JHS version codes.
enum OfficialRarityCatalog {
    struct Definition:Decodable {let rid:String;let code:String;let name:String;let colorHex:String?;let order:Int}
    struct Payload:Decodable {let definitions:[Definition]}
    static let definitions:[Definition] = loadDefinitions()
    static func rarity(_ rid:String)->CollectionRarity? {
        definitions.first{$0.rid == rid}.map{CollectionRarity(code:$0.code,name:$0.name,colorHex:$0.colorHex,rid:$0.rid)}
    }
}
