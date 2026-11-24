import Foundation
import Observation

struct MatchDeckChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isSelected: Bool

    init(_ value: APIValue) throws {
        guard let id=value["id"].text, Self.validID(id),
              let name=value["name"].text, let selected=value["isUse"].flag else {
            throw APIError.invalidResponse
        }
        self.id=id; self.name=name; isSelected=selected
    }

    static func validID(_ value:String)->Bool {
        !value.isEmpty && value.contains(where:{$0 != "0"}) && value.allSatisfy {$0.isASCII && $0.isNumber}
    }

    static func list(_ data:APIValue)throws->[Self] {
        guard let values=data["res"].values else {throw APIError.invalidResponse}
        let choices=try values.map(Self.init)
        guard Set(choices.map(\.id)).count==choices.count,
              choices.filter(\.isSelected).count<=1 else {throw APIError.invalidResponse}
        return choices
    }
}

enum MatchDeckSubmissionError: LocalizedError {
    case unavailable, missingChoice, changedDeck, unconfirmed
    var errorDescription:String? {
        switch self {
        case .unavailable: "当前比赛不可提交卡组，请刷新比赛状态。"
        case .missingChoice: "该卡组已不在比赛可选列表中，请刷新后重新选择。"
        case .changedDeck: "卡组内容已发生变化，请重新预览后提交。"
        case .unconfirmed: "提交结果尚未确认，请刷新核对，暂勿重复提交。"
        }
    }
}

@Observable @MainActor
final class MatchDeckSubmission {
    enum Phase:Equatable {case idle, loading, ready, submitting, submitted, uncertain}
    private(set) var phase:Phase = .idle
    private(set) var choices:[MatchDeckChoice]=[]
    private(set) var submittedID:String?
    private(set) var error:String?
    private var version:UUID?
    private var pendingID:String?
    var busy:Bool {phase == .loading || phase == .submitting}

    func load(matchID:String,account:AccountStore)async {
        guard !busy else {return}
        let sessionVersion=account.sessionVersion
        if let version, version != sessionVersion {return}
        version=sessionVersion
        phase = .loading; error=nil
        do {
            choices=try await readChoices(matchID:matchID,account:account)
            try check(account)
            if let pendingID {
                guard choices.contains(where:{$0.id==pendingID && $0.isSelected}) else {
                    phase = .uncertain; error=MatchDeckSubmissionError.unconfirmed.localizedDescription
                    return
                }
                submittedID=pendingID; self.pendingID=nil; phase = .submitted
            } else {
                if let submittedID,!choices.contains(where:{$0.id==submittedID && $0.isSelected}) {self.submittedID=nil}
                phase = .ready
            }
        } catch {
            guard sessionVersion==account.sessionVersion else {return}
            phase = pendingID == nil ? .idle : .uncertain
            self.error=AccountStore.message(for:error)
        }
    }

    func submit(_ choice:MatchDeckChoice,match:MatchDetail,account:AccountStore,
                validateDeck:()async throws->Void)async {
        guard phase == .ready || phase == .submitted else {return}
        phase = .submitting; error=nil
        var dispatched=false
        do {
            try check(account)
            guard match.canSubmitDeck, MatchDeckChoice.validID(choice.id),
                  MatchDeckChoice.validID(match.id), let token=account.session?.token else {
                throw MatchDeckSubmissionError.unavailable
            }
            let latest=try await account.api.matchDetail(id:match.id,backup:match.backup,token:token)
            try check(account)
            guard latest.canSubmitDeck else {throw MatchDeckSubmissionError.unavailable}
            choices=try await readChoices(matchID:match.id,account:account)
            guard choices.contains(where:{$0.id==choice.id}) else {throw MatchDeckSubmissionError.missingChoice}
            try await validateDeck()
            try check(account)
            // This GET changes the tournament's submitted deck. Dispatch once after confirmation.
            dispatched=true; pendingID=choice.id
            do {
                _ = try await account.fetchAuthenticated("/v1/match/deck/"+match.id+"/"+choice.id)
            } catch let error as APIError {
                if case .business = error {dispatched=false; pendingID=nil}
                throw error
            }
            try check(account)
            choices=try await readChoices(matchID:match.id,account:account)
            guard choices.contains(where:{$0.id==choice.id && $0.isSelected}) else {
                throw MatchDeckSubmissionError.unconfirmed
            }
            submittedID=choice.id; pendingID=nil; phase = .submitted
        } catch {
            guard version==account.sessionVersion else {return}
            if !dispatched {pendingID=nil}
            phase = dispatched ? .uncertain : .ready
            self.error=dispatched ? MatchDeckSubmissionError.unconfirmed.localizedDescription : AccountStore.message(for:error)
        }
    }

    private func readChoices(matchID:String,account:AccountStore)async throws->[MatchDeckChoice] {
        try check(account)
        guard MatchDeckChoice.validID(matchID) else {throw APIError.invalidResponse}
        let data=try await account.fetchAuthenticated("/v1/deck/index/"+matchID)
        try check(account)
        return try MatchDeckChoice.list(data)
    }

    private func check(_ account:AccountStore)throws {
        try Task.checkCancellation()
        guard account.isLoggedIn,version==account.sessionVersion else {throw CancellationError()}
    }
}
