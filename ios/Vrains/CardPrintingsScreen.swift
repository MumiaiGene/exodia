import SwiftUI
struct CardPrintingsScreen:View {
    @Environment(CardCatalog.self) private var catalog
    let card:CatalogCard
    @State private var records:[OfficialPrinting]=[]
    var body:some View {
        List(records){record in
            VStack(alignment:.leading,spacing:8){Text(record.packName).font(.headline);Text(record.number).font(.caption);Text(record.rarity).font(.caption.bold())}
        }.navigationTitle("卡包与罕贵度").task{records=(try? await catalog.database.officialPrintings(cid:card.cid)) ?? []}
    }
}
