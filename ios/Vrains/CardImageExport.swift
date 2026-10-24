import SwiftUI
import Photos

/// The export uses the selected Japanese artwork, never a screenshot of the detail screen.
@MainActor enum CardImageRenderer {
    static let width:CGFloat=1200
    // Neuron's highlighted icon cell is 40 source pixels × 1.5. Center a 46px icon in it.
    static let iconCellWidth:CGFloat=60
    static let iconSize:CGFloat=46
    static let effectTopInset:CGFloat=105
    static let effectBottomInset:CGFloat=44
    static var iconInset:CGFloat {(iconCellWidth-iconSize)/2}

    static func render(card:CatalogCard,names:[CardName],artwork:UIImage) throws -> UIImage {
        let chinese=["sc_name","nwbbs_n"].compactMap {source in names.first {$0.source==source && !$0.name.isEmpty}?.name}.first ?? card.name
        let japanese=names.first {$0.source=="jp_name"}?.name ?? card.name
        let ruby=names.first {$0.source=="jp_ruby"}?.name ?? japanese
        var sections:[(String,String)]=[]
        if !card.pendulumDescription.isEmpty {sections.append(("灵摆效果",card.pendulumDescription))}
        sections.append(("卡牌详情",card.description.isEmpty ? "暂无公开效果文本":card.description))
        let heights=sections.map {ceil(textHeight($0.1,width:1080,size:35))+effectTopInset+effectBottomInset}
        let height=534+heights.reduce(0,+)+CGFloat(max(0,sections.count-1))*24+30
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true;format.preferredRange = .standard
        return UIGraphicsImageRenderer(size:CGSize(width:width,height:height),format:format).image {output in
            let ctx=output.cgContext
            UIColor.share(0x000715).setFill();ctx.fill(CGRect(x:0,y:0,width:width,height:height))
            asset("background")?.draw(in:CGRect(x:0,y:0,width:width,height:height),blendMode:.normal,alpha:0.24)
            for y in stride(from:CGFloat(0),to:height,by:160) {for x in stride(from:CGFloat(0),to:width,by:138) {
                asset("mesh")?.draw(in:CGRect(x:x,y:y,width:138,height:160),blendMode:.normal,alpha:0.32)
            }}
            for y in stride(from:CGFloat(0),to:height,by:32) {for x in stride(from:CGFloat(0),to:width,by:512) {
                asset("lines")?.draw(in:CGRect(x:x,y:y,width:512,height:32),blendMode:.normal,alpha:0.44)
            }}
            let cardRect=CGRect(x:44,y:44,width:302,height:440)
            UIColor.share(0x9CBACD,0.7).setFill();ctx.fill(cardRect.insetBy(dx:-5,dy:-5));artwork.draw(in:cardRect)
            let x:CGFloat=390,rw:CGFloat=766
            panel(CGRect(x:x,y:40,width:rw,height:170))
            text(ruby,CGRect(x:x+18,y:48,width:rw-36,height:32),23,tint:.share(0xD2EAF5),fit:true)
            text(japanese,CGRect(x:x+18,y:83,width:rw-36,height:50),36,bold:true,fit:true)
            text(chinese,CGRect(x:x+18,y:139,width:rw-36,height:61),42,bold:true,fit:true)
            if card.isMonster {
                parameter(CGRect(x:x,y:230,width:365,height:64))
                icon(card.attributeIcon,CGRect(x:x+iconInset,y:239,width:iconSize,height:iconSize))
                text(card.attributeTitle,CGRect(x:x+68,y:239,width:280,height:50),34,bold:true)
                parameter(CGRect(x:x+380,y:230,width:386,height:64))
                if card.levelKind == "link" {
                    let markers=ImageRenderer(content:NeuronLinkMarkers(markers:card.linkMarkers ?? 0).frame(width:46,height:46));markers.scale=1
                    markers.uiImage?.draw(in:CGRect(x:x+380+iconInset,y:239,width:iconSize,height:iconSize))
                } else {icon(card.levelKind == "rank" ? "rank":"level",CGRect(x:x+380+iconInset,y:239,width:iconSize,height:iconSize))}
                text(card.levelLabel,CGRect(x:x+449,y:239,width:200,height:50),34,bold:true)
                text(String(card.level ?? 0),CGRect(x:x+710,y:239,width:44,height:50),34)
                panel(CGRect(x:x,y:314,width:rw,height:64))
                let type=card.compactTypeLine.replacingOccurrences(of:"【",with:"").replacingOccurrences(of:"】",with:"").replacingOccurrences(of:"/",with:"／")
                text(type,CGRect(x:x+22,y:323,width:rw-44,height:50),34,bold:true,fit:true,alignment:.center)
                parameter(CGRect(x:x,y:398,width:365,height:64),stat:true)
                text("ATK",CGRect(x:x+16,y:407,width:100,height:50),35,bold:true)
                text(stat(card.attack),CGRect(x:x+220,y:407,width:130,height:50),35,alignment:.right)
                if card.levelKind != "link" {
                    parameter(CGRect(x:x+380,y:398,width:386,height:64),stat:true)
                    text("DEF",CGRect(x:x+396,y:407,width:100,height:50),35,bold:true)
                    text(stat(card.defense),CGRect(x:x+630,y:407,width:120,height:50),35,alignment:.right)
                }
            } else {
                parameter(CGRect(x:x,y:230,width:rw,height:64))
                if let typeIcon=spellTrapExportIcon(card) {
                    icon(typeIcon,CGRect(x:x+iconInset,y:239,width:iconSize,height:iconSize))
                }
                text(card.spellTrapTitle,CGRect(x:x+68,y:239,width:rw-90,height:50),34,bold:true)
            }
            var y:CGFloat=534
            for (index,section) in sections.enumerated() {
                let box=CGRect(x:30,y:y,width:1140,height:heights[index])
                UIColor.share(0x000916,0.4).setFill();ctx.fill(box.insetBy(dx:10,dy:10))
                slice("frame",box,UIEdgeInsets(top:14,left:14,bottom:14,right:14))
                text(section.0,CGRect(x:54,y:y+17,width:section.0 == "灵摆效果" ? 460:1080,height:62),42,bold:true)
                if section.0 == "灵摆效果",let left=card.leftScale,let right=card.rightScale {
                    parameter(CGRect(x:550,y:y+9,width:598,height:70))
                    icon("pendulum",CGRect(x:557,y:y+21,width:46,height:46))
                    text("灵摆刻度",CGRect(x:618,y:y+23,width:290,height:50),34,bold:true)
                    let scales=left == right ? String(left):"\(left) / \(right)"
                    text(scales,CGRect(x:946,y:y+23,width:184,height:50),34,alignment:.right)
                }
                slice("divider",CGRect(x:52,y:y+76,width:1096,height:12),UIEdgeInsets(top:2,left:8,bottom:2,right:8))
                text(section.1,CGRect(x:54,y:y+effectTopInset,width:1080,height:heights[index]-effectTopInset-effectBottomInset),35)
                y+=heights[index]+24
            }
        }
    }
    static func spellTrapExportIcon(_ card:CatalogCard)->String? {
        card.spellTrapKind == "通常" ? nil:card.spellTrapIcon
    }
    private static func asset(_ name:String)->UIImage? {CardUIImages.image(name,in:"CardShare")}
    private static func icon(_ name:String,_ rect:CGRect) {CardUIImages.image(name,in:"InterfaceIcons")?.draw(in:rect)}
    private static func panel(_ rect:CGRect) {
        // UIRectFill uses copy blending: a translucent fill replaces the flattened background.
        // Composite over the existing texture instead, matching the prototype and PNG output.
        if let context=UIGraphicsGetCurrentContext() {
            context.saveGState();context.setBlendMode(.normal)
            context.setFillColor(UIColor.share(0x03243B,0.4).cgColor);context.fill(rect)
            context.restoreGState()
        }
        slice("name",rect,UIEdgeInsets(top:4,left:4,bottom:4,right:4),alpha:0.5)
    }
    private static func parameter(_ rect:CGRect,stat:Bool=false) {
        slice(stat ? "stat":"parameter",rect,stat ? UIEdgeInsets(top:2,left:96,bottom:2,right:30):UIEdgeInsets(top:2,left:40,bottom:2,right:2),alpha:stat ? 0.8:0.65,scale:stat ? 1.15:1.5)
    }
    private static func slice(_ name:String,_ rect:CGRect,_ insets:UIEdgeInsets,alpha:CGFloat=1,scale:CGFloat=1.5) {
        guard let image=asset(name)?.cgImage else{return}
        let w=CGFloat(image.width),h=CGFloat(image.height)
        let sx:[CGFloat]=[0,insets.left,w-insets.right,w],sy:[CGFloat]=[0,insets.top,h-insets.bottom,h]
        let dx:[CGFloat]=[rect.minX,rect.minX+insets.left*scale,rect.maxX-insets.right*scale,rect.maxX]
        let dy:[CGFloat]=[rect.minY,rect.minY+insets.top*scale,rect.maxY-insets.bottom*scale,rect.maxY]
        for j in 0..<3 {for i in 0..<3 {
            let source=CGRect(x:sx[i],y:sy[j],width:sx[i+1]-sx[i],height:sy[j+1]-sy[j])
            guard source.width>0,source.height>0,let patch=image.cropping(to:source) else{continue}
            UIImage(cgImage:patch).draw(in:CGRect(x:dx[i],y:dy[j],width:dx[i+1]-dx[i],height:dy[j+1]-dy[j]),blendMode:.normal,alpha:alpha)
        }}
    }
    private static func stat(_ value:Int64?)->String {value.map {$0<0 ? "?":String($0)} ?? "—"}
    private static func attributes(_ size:CGFloat,bold:Bool=false,tint:UIColor = .white,alignment:NSTextAlignment = .left)->[NSAttributedString.Key:Any] {
        let p=NSMutableParagraphStyle();p.lineBreakMode = .byWordWrapping;p.lineSpacing=9;p.alignment=alignment
        return [.font:UIFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular),.foregroundColor:tint,.paragraphStyle:p]
    }
    static func textHeight(_ value:String,width:CGFloat,size:CGFloat)->CGFloat {
        (value as NSString).boundingRect(with:CGSize(width:width,height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes(size),context:nil).height
    }
    private static func text(_ value:String,_ rect:CGRect,_ size:CGFloat,bold:Bool=false,tint:UIColor = .white,fit:Bool=false,alignment:NSTextAlignment = .left) {
        var actual=size
        if fit {while actual>14 && ((value as NSString).size(withAttributes:attributes(actual,bold:bold)).width>rect.width || textHeight(value,width:rect.width,size:actual)>rect.height) {actual-=1}}
        (value as NSString).draw(with:rect,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes(actual,bold:bold,tint:tint,alignment:alignment),context:nil)
    }
}
private extension UIColor {
    static func share(_ hex:UInt32,_ alpha:CGFloat=1)->UIColor {UIColor(red:CGFloat(hex>>16&255)/255,green:CGFloat(hex>>8&255)/255,blue:CGFloat(hex&255)/255,alpha:alpha)}
}

struct CardShareSheet:View {
    @Environment(CardCatalog.self) private var catalog
    let card:CatalogCard
    let ciid:Int64
    var body:some View {
        ImageShareSheet(title:"分享卡牌",objectName:card.name,identifier:"card.share") {
            let details=try await catalog.database.details(cid:card.cid)
            let data=try await NeuronArtworkStore.shared.data(cid:card.cid,ciid:ciid)
            try Task.checkCancellation()
            guard let artwork=UIImage(data:data) else {throw CardCatalogError.invalidData}
            return try CardImageRenderer.render(card:details.card,names:details.names,artwork:artwork)
        }
    }
}
