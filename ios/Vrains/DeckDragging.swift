import SwiftUI
import Observation
import UniformTypeIdentifiers

enum DeckDragContent { static let type = UTType(exportedAs:"com.exodia.deck-card") }

enum DeckDragSource {
    case deck(DeckCard,DeckZone)
    case search(CatalogCard,DeckCard)
    var artwork:DeckCard {switch self {case .deck(let artwork,_),.search(_,let artwork):artwork}}
    var fromSearch:Bool {if case .search = self {return true};return false}
}

private final class WeakDeckView {
    weak var view:UIView?
    init(_ view:UIView){self.view=view}
}

@Observable @MainActor final class DeckDragState {
    private(set) var source:DeckDragSource?
    @ObservationIgnored weak var dropArea:UIView?
    @ObservationIgnored weak var strip:UIView?
    @ObservationIgnored private var cards:[DeckCard:WeakDeckView]=[:]
    @ObservationIgnored private var searchAreas:[ObjectIdentifier:WeakDeckView]=[:]
    func register(_ view:UIView,card:DeckCard){cards[card]=WeakDeckView(view)}
    func registerSearch(_ view:UIView){searchAreas[ObjectIdentifier(view)]=WeakDeckView(view)}
    func containsDeckDrop(_ point:CGPoint,in window:UIWindow)->Bool {
        guard let area=dropArea,area.window === window else{return false}
        return area.convert(area.bounds,to:window).contains(point)
    }
    func containsSearchDrop(_ point:CGPoint,in window:UIWindow)->Bool {
        searchAreas.values.contains { holder in
            guard let v=holder.view,v.window === window else{return false}
            return v.convert(v.bounds,to:window).contains(point)
        }
    }
    func stripScroll()->UIScrollView? {
        var view=strip?.superview
        while let current=view {if let scroll=current as? UIScrollView {return scroll};view=current.superview}
        return nil
    }
    func insertion(at point:CGPoint,in window:UIWindow)->(DeckCard?,CGFloat,CGRect)? {
        guard containsDeckDrop(point,in:window),let strip,strip.window === window else{return nil}
        let items=cards.compactMap { card,holder -> (DeckCard,CGRect)? in
            guard let view=holder.view,view.window === window,source?.fromSearch == true || source?.artwork != card else{return nil}
            return (card,view.convert(view.bounds,to:window))
        }.sorted{$0.1.midX<$1.1.midX}
        let target=items.first{$0.1.midX>point.x}
        let rect=strip.convert(strip.bounds,to:window)
        return (target?.0,target.map{$0.1.minX-6} ?? items.last.map{$0.1.maxX+6} ?? rect.minX+4,rect)
    }
    private var identifier:UUID?
    @ObservationIgnored private var retainedSource:AnyObject?
    func begin(_ source:DeckDragSource,id:UUID,retaining owner:AnyObject) {self.source=source;identifier=id;retainedSource=owner}
    func consumed() {source=nil}
    func end(id:UUID) {guard identifier==id else{return};source=nil;identifier=nil;retainedSource=nil}
}

/// One local gesture for both sources: freeze loaded pixels, preview a gap, commit once.
struct DeckDraggableCard:UIViewRepresentable {
    let content:AnyView
    let source:DeckDragSource
    let drag:DeckDragState
    let identifier:String
    let label:String
    var insertSearch:((DeckCard?)->Void)? = nil
    var removeDeck:(()->Void)? = nil
    var hoverDeck:(()->Void)? = nil
    let open:()->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->DeckDragContainer {
        let view=DeckDragContainer(content:content)
        view.isAccessibilityElement=true;view.accessibilityTraits = .button
        let lift=UILongPressGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.cardDrag(_:)))
        lift.minimumPressDuration=0.25;lift.allowableMovement=12;view.addGestureRecognizer(lift)
        let tap=UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap));tap.require(toFail:lift);view.addGestureRecognizer(tap)
        context.coordinator.view=view
        return view
    }
    static func dismantleUIView(_ view:DeckDragContainer,coordinator:Coordinator) {coordinator.cancel()}
    func updateUIView(_ view:DeckDragContainer,context:Context) {
        context.coordinator.owner=self
        view.host.rootView=content
        view.accessibilityIdentifier=identifier;view.accessibilityLabel=label
        view.host.view.alpha=context.coordinator.lifted && !source.fromSearch ? 0:1
        if !source.fromSearch {drag.register(view,card:source.artwork)}
    }
    @MainActor final class Coordinator:NSObject {
        var owner:DeckDraggableCard
        weak var view:DeckDragContainer?
        var lifted=false
        private var id=UUID()
        private var preview:UIImageView?
        private var insertionLine:UIView?
        private var grabOffset=CGPoint.zero
        private var point=CGPoint.zero
        private var timer:Timer?
        private var lastTarget:String?
        init(_ owner:DeckDraggableCard){self.owner=owner}
        @objc func tap(){if !lifted {owner.open()}}
        func cancel() {
            timer?.invalidate();timer=nil
            preview?.removeFromSuperview();preview=nil
            insertionLine?.removeFromSuperview();insertionLine=nil
            view?.host.view.alpha=1;lifted=false;owner.drag.end(id:id)
        }
        private func updatePosition(in window:UIWindow,scroll:Bool) {
            preview?.center=CGPoint(x:point.x+grabOffset.x,y:point.y+grabOffset.y)
            guard owner.drag.containsDeckDrop(point,in:window) else {insertionLine?.isHidden=true;return}
            owner.hoverDeck?()
            if scroll,let list=owner.drag.stripScroll() {
                let rect=list.convert(list.bounds,to:window)
                let edge:CGFloat=38
                let velocity:CGFloat=point.x<rect.minX+edge ? -min(9,(rect.minX+edge-point.x)/4) : point.x>rect.maxX-edge ? min(9,(point.x-rect.maxX+edge)/4):0
                if velocity != 0 {
                    let x=max(-list.adjustedContentInset.left,min(list.contentSize.width-list.bounds.width+list.adjustedContentInset.right,list.contentOffset.x+velocity))
                    list.setContentOffset(CGPoint(x:x,y:list.contentOffset.y),animated:false)
                }
            }
            guard let (target,x,rect)=owner.drag.insertion(at:point,in:window) else {insertionLine?.isHidden=true;return}
            let visible=owner.drag.stripScroll().map{$0.convert($0.bounds,to:window)} ?? rect
            let clamped=max(visible.minX+2,min(visible.maxX-2,x))
            insertionLine?.frame=CGRect(x:clamped-1.5,y:rect.minY+3,width:3,height:rect.height-6)
            insertionLine?.isHidden=false
            let targetID=target?.id ?? "end"
            if lastTarget != targetID {UISelectionFeedbackGenerator().selectionChanged();lastTarget=targetID}
        }
        @objc func cardDrag(_ gesture:UILongPressGestureRecognizer) {
            if gesture.state == .cancelled || gesture.state == .failed {cancel();return}
            guard let view,let window=view.window else {cancel();return}
            point=gesture.location(in:window)
            switch gesture.state {
            case .began:
                view.layoutIfNeeded()
                let bitmap=UIGraphicsImageRenderer(bounds:view.bounds).image{_ in view.host.view.drawHierarchy(in:view.bounds,afterScreenUpdates:false)}
                let image=UIImageView(image:bitmap);image.frame=view.convert(view.bounds,to:window)
                grabOffset=CGPoint(x:image.center.x-point.x,y:image.center.y-point.y)
                image.isUserInteractionEnabled=false;image.accessibilityElementsHidden=true
                image.layer.shadowColor=UIColor.black.cgColor;image.layer.shadowOpacity=0.28;image.layer.shadowRadius=10
                window.addSubview(image);image.transform=CGAffineTransform(scaleX:1.08,y:1.08);preview=image
                let line=UIView();line.backgroundColor=UIColor(Design.accent);line.layer.cornerRadius=1.5;line.isUserInteractionEnabled=false;line.accessibilityElementsHidden=true;window.addSubview(line);insertionLine=line
                lifted=true;id=UUID();owner.drag.begin(owner.source,id:id,retaining:self)
                if !owner.source.fromSearch {view.host.view.alpha=0}
                UIImpactFeedbackGenerator(style:.light).impactOccurred()
                timer=Timer.scheduledTimer(withTimeInterval:1/60.0,repeats:true) { [weak self,weak window] _ in
                    MainActor.assumeIsolated {if let self,let window {self.updatePosition(in:window,scroll:true)}}
                }
                if let timer {RunLoop.main.add(timer,forMode:.common)}
                updatePosition(in:window,scroll:false)
            case .changed:updatePosition(in:window,scroll:false)
            case .ended:
                let inDeck=owner.drag.containsDeckDrop(point,in:window)
                let target=owner.drag.insertion(at:point,in:window)?.0
                let inSearch=owner.drag.containsSearchDrop(point,in:window)
                let insert=owner.insertSearch,remove=owner.removeDeck
                cancel()
                // Finish the recognizer and remove its overlay before SwiftUI changes
                // the pinned header or replaces a cell with a newly inserted card.
                DispatchQueue.main.async {
                    var transaction=Transaction();transaction.disablesAnimations=true
                    withTransaction(transaction) {if inDeck {insert?(target)} else if inSearch {remove?()}}
                }
            default:break
            }
        }
    }
}
final class DeckDragContainer:UIView {
    let host:UIHostingController<AnyView>
    init(content:AnyView) {
        host=UIHostingController(rootView:content)
        super.init(frame:.zero)
        backgroundColor = .clear;host.view.backgroundColor = .clear;host.safeAreaRegions=[]
        host.view.accessibilityElementsHidden=true
        host.view.translatesAutoresizingMaskIntoConstraints=false;addSubview(host.view)
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo:leadingAnchor),host.view.trailingAnchor.constraint(equalTo:trailingAnchor),host.view.topAnchor.constraint(equalTo:topAnchor),host.view.bottomAnchor.constraint(equalTo:bottomAnchor)])
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
}

struct DeckSearchDropRegion:ViewModifier {
    let session:DeckEditingSession?
    let drag:DeckDragState?
    @ViewBuilder func body(content:Content)->some View {
        if session != nil,let drag {
            content.contentShape(Rectangle()).background {DeckSearchAreaReporter(drag:drag)}
        } else {content}
    }
}

struct DeckSearchDraggableTile:View {
    @Environment(CardCatalog.self) private var catalog
    @Environment(AppStore.self) private var store
    let card:CatalogCard
    let format:CardFormat?
    let drag:DeckDragState
    let session:DeckEditingSession
    let open:()->Void
    @State private var imageID:Int64=1
    var body:some View {
        DeckDraggableCard(content:AnyView(CardGridArtwork(card:card,ciid:imageID,format:format).environment(catalog).environment(store)),source:.search(card,DeckCard(cid:card.cid,ciid:imageID)),drag:drag,identifier:"cards.grid.\(card.cid)",label:card.name,insertSearch:{target in _ = session.insertFromSearch(card,ciid:imageID,before:target)},hoverDeck:{let zone=session.searchDropZone(for:card);if session.zone != zone {session.zone=zone}},open:open)
            .aspectRatio(NeuronCardLayout.aspect,contentMode:.fit)
            .task(id:card.cid) {imageID=(try? await NeuronArtworkStore.shared.variants(cid:card.cid).first?.ciid) ?? 1}
    }
}


struct DeckDropAreaReporter:UIViewRepresentable {
    let drag:DeckDragState
    func makeUIView(context:Context)->UIView {
        let view=UIView();view.isUserInteractionEnabled=false;view.accessibilityElementsHidden=true;drag.dropArea=view;return view
    }
    func updateUIView(_ view:UIView,context:Context){drag.dropArea=view}
}

struct DeckCardStripReporter:UIViewRepresentable {
    let drag:DeckDragState
    func makeUIView(context:Context)->UIView {let view=UIView();view.isUserInteractionEnabled=false;drag.strip=view;return view}
    func updateUIView(_ view:UIView,context:Context){drag.strip=view}
}
struct DeckSearchAreaReporter:UIViewRepresentable {
    let drag:DeckDragState
    func makeUIView(context:Context)->UIView {let view=UIView();view.isUserInteractionEnabled=false;view.accessibilityElementsHidden=true;drag.registerSearch(view);return view}
    func updateUIView(_ view:UIView,context:Context){drag.registerSearch(view)}
}
