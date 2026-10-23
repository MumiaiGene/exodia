import SwiftUI
import Photos
import UniformTypeIdentifiers

/// One physical card per cell, preserving the deck's order and artwork IDs.
enum DeckImageLayout {
    static let width:CGFloat=1200
    static let columns=10
    static let gap:CGFloat=4
    static let titleHeight:CGFloat=80
    static let headerHeight:CGFloat=52
    static let cardWidth=(width-gap*CGFloat(columns+1))/CGFloat(columns)
    static let cardHeight=cardWidth*86/59
    static func rows(_ count:Int)->Int {max(1,(count+columns-1)/columns)}
    static func sectionHeight(_ count:Int)->CGFloat {headerHeight+gap+CGFloat(rows(count))*(cardHeight+gap)}
    static func size(for deck:Deck)->CGSize {CGSize(width:width,height:ceil(titleHeight+[deck.mainArtworks,deck.extraArtworks,deck.sideArtworks].reduce(0){$0+sectionHeight($1.count)}))}
}

@MainActor enum DeckImageRenderer {
    static func render(_ deck:Deck,load:(DeckCard) async -> UIImage?) async throws -> UIImage {
        var images:[DeckCard:UIImage]=[:]
        for artwork in Set(deck.mainArtworks+deck.extraArtworks+deck.sideArtworks) {
            try Task.checkCancellation()
            images[artwork]=await load(artwork)
        }
        try Task.checkCancellation()
        let size=DeckImageLayout.size(for:deck)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true;format.preferredRange = .standard
        let back=backPrint
        return UIGraphicsImageRenderer(size:size,format:format).image { renderer in
            let context=renderer.cgContext
            gradient(context,rect:CGRect(origin:.zero,size:size),colors:[UIColor(rgb:0x05385E),UIColor(rgb:0x00141E)])
            gradient(context,rect:CGRect(x:0,y:0,width:size.width,height:80),colors:[UIColor(rgb:0x074C7B),UIColor(rgb:0x00345C)])
            UIColor(rgb:0x27C8EF).setFill();context.fill(CGRect(x:0,y:0,width:5,height:80))
            text(deck.name,in:CGRect(x:16,y:13,width:size.width-32,height:58),size:42)
            var y=DeckImageLayout.titleHeight
            for (title,cards) in [("主卡组",deck.mainArtworks),("额外卡组",deck.extraArtworks),("副卡组",deck.sideArtworks)] {
                let header=CGRect(x:2,y:y+2,width:size.width-4,height:48)
                gradient(context,rect:header,colors:[UIColor(rgb:0x020E1C),UIColor(rgb:0x003254)])
                UIColor(rgb:0xB4E9F3).setStroke();context.setLineWidth(3);context.stroke(header)
                back?.draw(in:CGRect(x:14,y:y+12,width:21,height:30))
                text("\(title)：\(cards.count)",in:CGRect(x:48,y:y+7,width:size.width-60,height:40),size:30)
                let top=y+DeckImageLayout.headerHeight+DeckImageLayout.gap
                for (index,artwork) in cards.enumerated() {
                    let rect=CGRect(x:DeckImageLayout.gap+CGFloat(index%10)*(DeckImageLayout.cardWidth+DeckImageLayout.gap),y:top+CGFloat(index/10)*(DeckImageLayout.cardHeight+DeckImageLayout.gap),width:DeckImageLayout.cardWidth,height:DeckImageLayout.cardHeight)
                    (images[artwork] ?? back)?.draw(in:rect)
                }
                y += DeckImageLayout.sectionHeight(cards.count)
            }
        }
    }
    static func render(_ deck:Deck) async throws -> UIImage {
        let artworks=Array(Set(deck.mainArtworks+deck.extraArtworks+deck.sideArtworks))
        let bytes=await withTaskGroup(of:(DeckCard,Data?).self,returning:[DeckCard:Data].self) {group in
            var result:[DeckCard:Data]=[:],next=0
            func enqueue(_ artwork:DeckCard) {group.addTask {(artwork,try? await NeuronArtworkStore.shared.data(cid:artwork.cid,ciid:artwork.ciid))}}
            while next<min(6,artworks.count) {enqueue(artworks[next]);next+=1}
            while let (artwork,data)=await group.next() {
                if let data {result[artwork]=data}
                if next<artworks.count,!Task.isCancelled {enqueue(artworks[next]);next+=1}
            }
            return result
        }
        return try await render(deck) {artwork in bytes[artwork].flatMap(UIImage.init(data:))}
    }

    private static var backPrint:UIImage? {
        guard let url=Bundle.main.url(forResource:"BackPrint",withExtension:"png",subdirectory:"CardData") else{return nil}
        return UIImage(contentsOfFile:url.path)
    }
    private static func text(_ text:String,in rect:CGRect,size:CGFloat) {
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in:rect,withAttributes:[.font:UIFont.boldSystemFont(ofSize:size),.foregroundColor:UIColor.white,.paragraphStyle:paragraph])
    }
    private static func gradient(_ context:CGContext,rect:CGRect,colors:[UIColor]) {
        context.saveGState();context.clip(to:rect)
        if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors.map(\.cgColor) as CFArray,locations:[0,1]) {
            context.drawLinearGradient(gradient,start:rect.origin,end:CGPoint(x:rect.maxX,y:rect.maxY),options:[])
        }
        context.restoreGState()
    }
}

private extension UIColor {
    convenience init(rgb:UInt32) {self.init(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)}
}

struct DeckShareSheet:View {
    let deck:Deck
    var body:some View {
        ImageShareSheet(title:"分享卡组",objectName:deck.name,identifier:"deck.share",exportDeck:deck) {
            try await DeckImageRenderer.render(deck)
        }
    }
}

/// Shared presentation for image-sharing tasks. Exported artwork stays independent of this UI.
struct ImageShareSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title:String
    let objectName:String
    let identifier:String
    var exportDeck:Deck?=nil
    let render:@MainActor () async throws -> UIImage
    @State private var artifact:ShareImageArtifact?
    private var image:UIImage? {artifact?.image}
    @State private var sharing=false
    @State private var exporting=false
    @State private var saving=false
    @State private var failed=false
    @State private var attempt=0
    @State private var message:String?
    @State private var messageIsError=false
    @State private var needsSettings=false

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:24) {
                    if let image {
                        Image(uiImage:image).resizable().scaledToFit()
                            .accessibilityLabel("\(objectName)的分享图片").accessibilityIdentifier(identifier+".preview")
                    } else if failed {
                        ContentUnavailableView {
                            Label("图片生成失败",systemImage:"exclamationmark.triangle")
                        } description: {
                            Text("暂时无法读取卡图或资料，请检查网络后重试。")
                        } actions: {
                            Button("重新生成"){attempt+=1}.buttonStyle(.bordered)
                                .frame(minHeight:44).accessibilityIdentifier(identifier+".retry")
                        }
                    } else {
                        ProgressView("正在生成分享图片…").frame(maxWidth:.infinity,minHeight:240)
                            .accessibilityIdentifier(identifier+".loading")
                    }
                }.padding(20).frame(maxWidth:760).frame(maxWidth:.infinity)
            }
            .background(Design.canvas)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button {dismiss()} label:{Image(systemName:"xmark")}
                        .accessibilityLabel("关闭").accessibilityIdentifier(identifier+".close")
                }
                if exportDeck != nil {
                    ToolbarItem(placement:.topBarTrailing) {
                        Menu {Button {exporting=true} label:{Label("导出卡组文件",systemImage:"square.and.arrow.up.on.square")}} label:{Image(systemName:"ellipsis")}
                            .accessibilityLabel("更多").accessibilityIdentifier(identifier+".more")
                    }
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {actionArea}
        }
        .task(id:attempt) {
            failed=false
            do {let result=try await render();try Task.checkCancellation();artifact=try ShareImageArtifact.make(result)}
            catch is CancellationError {} catch {failed=true}
        }
        .sheet(isPresented:$sharing) {if let artifact {DeckImageActivity(fileURL:artifact.fileURL)}}
        .fileExporter(isPresented:$exporting,document:exportDeck.map {DeckExportDocument(deck:$0)},contentType:.json,defaultFilename:exportDeck?.name ?? "卡组") {result in
            if case .failure=result {feedback("未能导出卡组文件，请重试。",error:true)}
        }
    }
    private var actionArea:some View {
        VStack(spacing:12) {
            if let message {
                VStack(spacing:8) {
                    Label(message,systemImage:messageIsError ? "exclamationmark.circle":"checkmark.circle")
                        .font(.footnote).foregroundStyle(messageIsError ? Color.red:Design.secondary)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(identifier+".feedback")
                    if needsSettings {Button("打开系统设置") {if let url=URL(string:UIApplication.openSettingsURLString) {openURL(url)}}.frame(minHeight:44)}
                }
            }
            if image == nil {
                Text(failed ? "生成图片后即可保存或分享。":"图片生成后即可保存或分享。")
                    .font(.footnote).foregroundStyle(Design.secondary).fixedSize(horizontal:false,vertical:true)
            }
            let layout=dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:12)):AnyLayout(HStackLayout(spacing:12))
            layout {
                Button {sharing=true} label: {
                    Label("分享图片",systemImage:"square.and.arrow.up")
                        .font(.headline).frame(maxWidth:.infinity,minHeight:54)
                }.buttonStyle(.borderedProminent).tint(Design.accent).disabled(image==nil)
                    .accessibilityIdentifier(identifier+".image")
                Button {Task {await save()}} label: {
                    ZStack {
                        Label("保存图片",systemImage:"square.and.arrow.down").opacity(saving ? 0:1)
                        if saving {ProgressView().accessibilityHidden(true)}
                    }.font(.headline).frame(maxWidth:.infinity,minHeight:54)
                }.buttonStyle(.bordered).disabled(image==nil || saving)
                    .accessibilityLabel(saving ? "正在保存图片":"保存图片").accessibilityIdentifier(identifier+".save-image")
            }
        }.padding(20).frame(maxWidth:760).frame(maxWidth:.infinity).background(.bar)
    }
    private func feedback(_ value:String,error:Bool=false) {message=value;messageIsError=error}
    private func save() async {
        guard let artifact,!saving else{return};saving=true;needsSettings=false;defer {saving=false}
        let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
        guard status == .authorized || status == .limited else {
            needsSettings=true;feedback("尚未获得照片权限，请在系统设置中允许保存。",error:true);return
        }
        do {
            try await DeckPhotoWriter.save(artifact.png);feedback("已保存到相册。")
        } catch {feedback("保存失败，请重试。",error:true)}
    }
}

/// One opaque sRGB PNG is the source for preview, Photos, and the system share sheet.
@MainActor struct ShareImageArtifact {
    let image:UIImage
    let png:Data
    let fileURL:URL
    static func make(_ source:UIImage)throws->Self {
        guard let cg=source.cgImage,let space=CGColorSpace(name:CGColorSpace.sRGB),
              let context=CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {throw CardCatalogError.invalidData}
        let rect=CGRect(x:0,y:0,width:cg.width,height:cg.height)
        context.setFillColor(UIColor.black.cgColor);context.fill(rect)
        context.draw(cg,in:rect)
        guard let flat=context.makeImage(),let data=UIImage(cgImage:flat).pngData(),let preview=UIImage(data:data) else {throw CardCatalogError.invalidData}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("Vrains-share-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent("分享图片.png")
        try data.write(to:url,options:.atomic)
        return Self(image:preview,png:data,fileURL:url)
    }
}

struct DeckImageActivity:UIViewControllerRepresentable {
    let fileURL:URL
    func makeUIViewController(context:Context)->UIActivityViewController {UIActivityViewController(activityItems:[fileURL],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}

enum DeckPhotoWriter {
    nonisolated static func save(_ data:Data) async throws {
        // Photos executes this block on its own transaction queue, outside MainActor.
        try await PHPhotoLibrary.shared().performChanges {
            let request=PHAssetCreationRequest.forAsset()
            request.addResource(with:.photo,data:data,options:nil)
        }
    }
}
