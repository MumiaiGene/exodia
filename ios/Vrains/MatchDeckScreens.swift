import SwiftUI

private struct MatchDeckReview:Identifiable {
    let choice:MatchDeckChoice
    let detail:RemoteDeckDetail
    let deck:Deck
    var id:String {choice.id}
}

struct MatchDeckUploadScreen:View {
    let match:MatchDetail
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var submission=MatchDeckSubmission()
    @State private var review:MatchDeckReview?
    @State private var previewing:String?
    @State private var previewError:String?
    @State private var showingLocalPicker=false
    @State private var uploadedID:String?
    @State private var previews:[String:MatchDeckReview]=[:]
    @State private var refreshing=false

    var body:some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading,spacing:8) {
                        Text(match.name).font(.headline).foregroundStyle(Design.ink)
                        if let format=match.deckFormat {DeckFormatTag(format:format)}
                    }.padding(.vertical,6)
                }
                Section {
                    ForEach(submission.choices) { choice in
                        Button {Task {await preview(choice)}} label:{
                            HStack(spacing:12) {
                                DeckListRow(deck:previews[choice.id]?.deck ?? placeholder(choice),
                                    format:previews[choice.id]?.deck.banlist.flatMap(CardFormat.init(rawValue:)))
                                if previewing==choice.id {ProgressView()}
                                else if choice.isSelected {
                                    Image(systemName:"checkmark.circle.fill").foregroundStyle(Design.accent)
                                        .accessibilityLabel("当前比赛卡组")
                                } else {
                                    Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Design.secondary)
                                }
                            }.padding(.vertical,6).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(submission.busy || submission.phase == .uncertain || previewing != nil)
                            .accessibilityIdentifier("match.deck.choice."+choice.id)
                    }
                    if submission.busy {ProgressView("正在读取比赛卡组")}
                    if submission.choices.isEmpty && !submission.busy {
                        Text("暂无可用卡组").foregroundStyle(Design.secondary)
                    }
                } header:{Text("选择卡组")} footer:{
                    Text("选择卡组，确认内容后提交。也可通过右上角 + 上传本地卡组。")
                }
                if let error=submission.error ?? previewError {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Design.secondary)
                        Button(submission.phase == .uncertain ? "刷新核对提交结果" : "重新读取卡组") {
                            Task {await reload()}
                        }.disabled(submission.busy)
                    }
                }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Design.canvas)
                .navigationTitle("上传卡组").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {ModalCloseButton().disabled(submission.busy)}
                    ToolbarItem(placement:.topBarTrailing) {
                        Button {showingLocalPicker=true} label:{Image(systemName:"plus")}
                            .accessibilityLabel("上传本地卡组")
                            .disabled(submission.busy || submission.phase == .uncertain || previewing != nil)
                    }
                }
                .task {await reload()}
                .refreshable {await reload()}
                .navigationDestination(isPresented:Binding(get:{review != nil},set:{if !$0 {review=nil}})) {
                    if let review {MatchDeckReviewScreen(match:match,review:review,submission:submission)}
                }
                .navigationDestination(isPresented:$showingLocalPicker) {
                    MatchDeckLocalPicker(match:match) {uploadedID=$0; showingLocalPicker=false}
                }
                .onChange(of:showingLocalPicker) {_,showing in
                    guard !showing else {return}
                    guard let id=uploadedID else {return}
                    uploadedID=nil
                    Task {
                        previewError=nil
                        await reload()
                        if let choice=submission.choices.first(where:{$0.id==id}) {await preview(choice)}
                        else {previewError="卡组已同步，但尚未出现在比赛可选列表中。请确认卡组环境和比赛要求后刷新。"}
                    }
                }
                .interactiveDismissDisabled(submission.busy)
                .onChange(of:account.sessionVersion) {_,_ in
                    review=nil; previews=[:]; previewing=nil; uploadedID=nil; showingLocalPicker=false
                    submission=MatchDeckSubmission()
                }
        }.tint(Design.accent)
    }

    private func placeholder(_ choice:MatchDeckChoice)->Deck {
        Deck(id:choice.id,name:choice.name,subtitle:"",kind:.blue,cards:0,isMine:false)
    }

    private func reload()async {
        guard !refreshing else {return}
        refreshing=true
        defer {refreshing=false}
        let version=account.sessionVersion
        await submission.load(matchID:match.id,account:account)
        guard version==account.sessionVersion,!submission.busy else {return}
        do {
            let session=try await RemoteDeckSession(account:account)
            let summaries=try await session.list()
            var updated:[String:MatchDeckReview]=[:]
            for choice in submission.choices {
                guard let summary=summaries.first(where:{$0.id==choice.id}),
                      let detail=try? await session.detail(summary),let deck=try? detail.deckSnapshot() else {continue}
                updated[choice.id]=MatchDeckReview(choice:choice,detail:detail,deck:deck)
            }
            guard version==account.sessionVersion else {return}
            previews=updated
        } catch {
            // The match list remains usable; opening a deck retries the authenticated detail request.
        }
    }

    private func preview(_ choice:MatchDeckChoice)async {
        guard previewing==nil,!submission.busy else {return}
        let version=account.sessionVersion
        previewing=choice.id; previewError=nil
        defer {if version==account.sessionVersion {previewing=nil}}
        do {
            let session=try await RemoteDeckSession(account:account)
            guard let summary=try await session.list().first(where:{$0.id==choice.id}) else {
                throw MatchDeckSubmissionError.missingChoice
            }
            let detail=try await session.detail(summary)
            let deck=try detail.deckSnapshot()
            guard version==account.sessionVersion else {return}
            review=MatchDeckReview(choice:choice,detail:detail,deck:deck)
        } catch {
            guard version==account.sessionVersion else {return}
            previewError=AccountStore.message(for:error)
        }
    }
}

private struct MatchDeckReviewScreen:View {
    let match:MatchDetail
    let review:MatchDeckReview
    let submission:MatchDeckSubmission
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var confirming=false

    var body:some View {
        DeckConfirmationScreen(deckID:review.deck.id,serverDeck:review.deck,isSelectionPreview:true)
            .navigationBarBackButtonHidden(submission.busy)
            .safeAreaInset(edge:.bottom) {
                DeckActionBar {
                    Text(match.name).font(.caption).foregroundStyle(Design.secondary)
                    if let error=submission.error {Text(error).font(.footnote).foregroundStyle(Design.secondary)}
                    if submission.phase == .submitted,submission.submittedID==review.id {
                        Label("已提交“\(review.choice.name)”",systemImage:"checkmark.circle.fill")
                            .foregroundStyle(.green)
                        AccentButton(title:"完成") {dismiss()}
                    } else if submission.phase == .uncertain {
                        AccentButton(title:"刷新核对提交结果",isLoading:submission.busy) {
                            Task {await submission.load(matchID:match.id,account:account)}
                        }
                    } else {
                        AccentButton(title:submission.busy ? "正在提交" : "提交卡组",isLoading:submission.busy) {confirming=true}
                            .disabled(submission.phase != .ready && submission.phase != .submitted)
                            .accessibilityIdentifier("match.deck.submit")
                    }
                }
            }
            .confirmationDialog("提交此卡组？",isPresented:$confirming,titleVisibility:.visible) {
                Button("确认提交") {Task {await submit()}}
                Button("取消",role:.cancel) {}
            } message:{Text("将“\(review.choice.name)”提交到“\(match.name)”。提交后能否更换卡组以比赛规则为准。")}
            .interactiveDismissDisabled(submission.busy)
    }

    private func submit()async {
        await submission.submit(review.choice,match:match,account:account) {
            let session=try await RemoteDeckSession(account:account)
            guard let summary=try await session.list().first(where:{$0.id==review.id}) else {
                throw MatchDeckSubmissionError.missingChoice
            }
            let current=try await session.detail(summary)
            guard current.cards.sorted(by:cardOrder)==review.detail.cards.sorted(by:cardOrder),
                  current.summary.name==review.detail.summary.name,
                  current.summary.format==review.detail.summary.format else {
                throw MatchDeckSubmissionError.changedDeck
            }
        }
    }

    private func cardOrder(_ lhs:RemoteDeckCard,_ rhs:RemoteDeckCard)->Bool {
        if lhs.cid != rhs.cid {return (lhs.cid ?? 0)<(rhs.cid ?? 0)}
        if lhs.type != rhs.type {return lhs.type<rhs.type}
        if lhs.language != rhs.language {return lhs.language<rhs.language}
        return lhs.quantity<rhs.quantity
    }
}

private struct MatchDeckLocalPicker:View {
    let match:MatchDetail
    let onSaved:(String)->Void
    @Environment(AppStore.self) private var store
    @Environment(CardCatalog.self) private var catalog
    @State private var uploading:Deck?
    @State private var savedID:String?
    private var decks:[Deck] {
        store.myDecks.filter {deck in
            let format=deck.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat
            return format != .tcg && (match.deckFormat==nil || format==match.deckFormat)
        }
    }
    var body:some View {
        List {
            ForEach(decks) {deck in
                Button {uploading=deck} label:{
                    DeckListRow(deck:deck,format:deck.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat)
                        .padding(.vertical,6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if decks.isEmpty {Text("没有符合比赛环境的本地卡组，请先创建或调整卡组的禁限卡表。").foregroundStyle(Design.secondary)}
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Design.canvas)
            .navigationTitle("本地卡组").navigationBarTitleDisplayMode(.inline)
            .sheet(item:$uploading,onDismiss:{
                if let id=savedID {savedID=nil; onSaved(id)}
            }) {deck in
                RemoteDeckUploadScreen(deck:deck) {id in savedID=id; uploading=nil}
            }
    }
}
