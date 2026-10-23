import Foundation

#if DEBUG
actor TestJHSAPITransport:APITransport {
    private(set) var requests:[URLRequest]=[]
    func data(for request:URLRequest) async throws -> (Data,HTTPURLResponse) {
        requests.append(request);let path=request.url?.path ?? "",body=String(data:request.httpBody ?? Data(),encoding:.utf8) ?? ""
        let value:String
        switch path {
        case "/api/market/auth/send-sms": value="{\"message\":\"success\"}"
        case "/api/market/auth/login-or-signup":
            value=body.contains("12345") ? "{\"token\":\"jhs-ui-test-session\",\"user_id\":77,\"username\":\"测试集换社账号\"}" : "{\"code\":400,\"message\":\"验证码不正确\"}"
        default: throw URLError(.unsupportedURL)
        }
        return (Data(value.utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
}

/// Explicitly selected by UI tests only. Production always uses NetworkTransport.
actor TestAPITransport: APITransport {
    private var rejectWithdrawalOnce = ProcessInfo.processInfo.arguments.contains("--uitesting-withdraw-failure-once")
    let expired: Bool
    let offline: Bool
    private var failSecondPageOnce: Bool
    private(set) var requests: [URLRequest] = []
    private var reportedDuel = false
    private var pairingVisits = 0
    private var signedMatches = Set<String>()
    init(expired: Bool = false, offline: Bool = false, failSecondPageOnce: Bool = false) {
        self.expired = expired; self.offline = offline; self.failSecondPageOnce = failSecondPageOnce
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        let path = request.url!.path
        var value: String
        if path == "/api/ct.do" {
            value = "{\"currentTime\":\(Int64(Date.now.timeIntervalSince1970 * 1000))}"
        } else if expired, request.value(forHTTPHeaderField: "Authorization") != nil {
            value = "{\"code\":10313,\"msg\":\"登录已过期\"}"
        } else {
            switch path {
            case "/address":
                value = #"{"code":200,"data":{"res":{"res":[{"name":"北京市","cityList":[{"id":1,"code":"110000","name":"北京市"}]},{"name":"上海市","cityList":[{"id":774,"code":"310000","name":"上海市"}]}]}}}"#
            case "/v1/shop":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let params = Dictionary(uniqueKeysWithValues: (URLComponents(string: "?" + body)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let page = Int(params["page"] ?? "1") ?? 1
                if page == 2, failSecondPageOnce { failSecondPageOnce = false; throw URLError(.timedOut) }
                let ids = Array((1...11).filter { params["public_level"] != "1" || $0 == 1 }.dropFirst((page - 1) * 10).prefix(10))
                let rows = ids.map { "{\"id\":\($0),\"name\":\"测试卡店 \($0)\",\"userId\":63882,\"address\":\"上海市 测试街道\",\"time\":\"每天10:00-22:00\",\"publicLevel\":1}" }.joined(separator: ",")
                let count = params["public_level"] == "1" ? 1 : 11
                value = "{\"code\":200,\"data\":{\"count\":\(count),\"level_list\":{\"-1\":\"零售商\",\"0\":\"普通公认店\",\"1\":\"一星公认店\"},\"shop\":[\(rows)]}}"
            case "/v1/points/ranking":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let params = Dictionary(uniqueKeysWithValues: (URLComponents(string: "?" + body)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let page = Int(params["page"] ?? "1") ?? 1
                let type = params["type"] ?? "1"
                let rows = (0..<11).dropFirst((page - 1) * 10).prefix(10).map { index in
                    "{\"rank\":\(index < 2 ? 1 : index + 1),\"nickName\":\"测试榜单\(type)-\(index)\",\"avatar\":\"\",\"points\":\(300-index)}"
                }.joined(separator: ",")
                let personal = request.value(forHTTPHeaderField: "Authorization") != nil && type == "1"
                    ? "{\"rank\":7,\"points\":120,\"nickName\":\"测试决斗者\"}"
                    : "{\"rank\":0,\"points\":0}"
                value = "{\"code\":200,\"data\":{\"count\":11,\"season_id\":11,\"allSeason\":[{\"id\":11,\"name\":\"2026第二赛季\"}],\"personal\":\(personal),\"res\":[\(rows)]}}"
            case "/v1/match":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let params = Dictionary(uniqueKeysWithValues: (URLComponents(string: "?" + body)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let selectedType = params["type"].flatMap { $0.isEmpty ? nil : Int($0.filter(\.isNumber)) }
                let status = Int(params["status"] ?? "2") ?? 2
                let keyword = params["keywords"] ?? ""
                let simplified = params["condition"] == "[\"1\"]"
                let all = Array(901...921).filter { id in
                    let name = id == 901 ? "测试巡回赛" : "测试比赛 \(id)"
                    return (selectedType == nil || selectedType == (id == 901 ? 4 : id == 903 ? 2 : 1))
                        && (keyword.isEmpty || name.contains(keyword)) && (!simplified || id == 903)
                }
                let page = Int(params["page"] ?? "1") ?? 1
                let start = (page - 1) * 20
                let pageIDs = Array(all.dropFirst(start).prefix(20))
                let timestamp = Int(Date.now.timeIntervalSince1970)
                let events = pageIDs.map { id -> String in
                    let type = id == 901 ? 4 : id == 903 ? 2 : 1
                    let distance = id == 901 ? 7 * 86400 : id == 902 ? 3600 : (id - 900) * 3600
                    let name = id == 901 ? "测试巡回赛" : "测试比赛 \(id)"
                    let state = status == 2 ? "可报名" : status == 3 ? "进行中" : "已结束"
                    return "{\"id\":\(id),\"name\":\"\(name)\",\"type\":\(type),\"statusId\":\(status),\"address\":\"上海 · 测试卡牌空间\",\"startAt\":\"2026-10-18 14:00\",\"startAtTimestamp\":\(timestamp + (status == 8 ? -distance : distance)),\"bottom\":{\"title\":{\"text\":\"\(state)\",\"alreadySignedUp\":1000,\"signUpTotal\":1000}}}"
                }.joined(separator: ",")
                value = "{\"code\":200,\"data\":{\"count\":\(all.count),\"matchTypeView\":{\"0\":\"全部\",\"1\":\"娱乐赛\",\"2\":\"积分赛\",\"3\":\"特殊赛\",\"4\":\"巡回赛\",\"5\":\"邀请赛\"},\"matchs\":[\(events)]}}"
                if selectedType == 20 { value = "{\"code\":200,\"data\":{\"count\":0}}" }
            case "/v1/news":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let page = URLComponents(string: "?" + body)?.queryItems?.first(where: { $0.name == "page" })?.value ?? "1"
                if page == "2", failSecondPageOnce {
                    failSecondPageOnce = false
                    throw URLError(.timedOut)
                }
                let ids = page == "1" ? Array(501...510) : [510, 511]
                let articles = ids.map { "{\"id\":\($0),\"title\":\"测试动态 \($0)\",\"author\":\"新闻作者\",\"time_desc\":\"今天\",\"view\":12}" }.joined(separator: ",")
                value = "{\"code\":200,\"data\":{\"count\":11,\"banner\":[{\"title\":\"测试置顶新闻\",\"url\":{\"type\":\"information\",\"id\":\"501\"}},{\"title\":\"测试活动 banner\",\"url\":{\"type\":\"duel_kingdom\",\"id\":\"6\"}}],\"news\":[\(articles)]}}"
            case "/v1/msg/send": value = "{\"code\":200,\"msg\":\"发送成功\",\"data\":{}}"
            case "/v1/user/login":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let valid = body.split(separator: "&").contains("code=12345") || body.split(separator: "&").contains("code=123456")
                value = valid ? "{\"code\":200,\"data\":{\"id\":96,\"token\":\"ui-test-session\"}}" : "{\"code\":10100,\"msg\":\"验证码不正确\"}"
            case "/v1/user/info":
                value = "{\"code\":200,\"data\":{\"user\":{\"nickName\":\"测试决斗者\",\"view_id\":\"EX0096\",\"phone\":\"13800138000\",\"selectRole\":\"player\",\"isReal\":true,\"signature\":\"为热爱而决斗。\"}}}"
            case "/v1/personal/center":
                value = "{\"code\":\"200\",\"data\":{\"totalNums\":12,\"matchTotal\":[{\"tag\":\"ec\",\"name\":\"娱乐赛\",\"num\":4},{\"tag\":\"ig\",\"name\":\"积分赛\",\"num\":8}]}}"
            case "/v1/match/against/resultview/901":
                value = "{\"code\":200,\"data\":{\"againstResultOff\":[{\"title\":\"决赛\",\"result\":[{\"anickname\":\"决赛选手甲\",\"bnickname\":\"决赛选手乙\",\"aresult\":1,\"bresult\":3}]}]}}"
            case "/v1/match/against/swiss/rank/901":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let params = URLComponents(string: "?" + body)?.queryItems ?? []
                let round = params.first { $0.name == "round" }?.value == "2" ? 2 : 1
                value = "{\"code\":200,\"data\":{\"count\":1,\"againstResultSwiss\":[{\"sid\":96,\"rank\":1,\"nickname\":\"测试决斗者\",\"score\":\(round * 3)}],\"currentUser\":{\"sid\":96,\"rank\":1,\"nickname\":\"测试决斗者\",\"score\":\(round * 3)},\"filter\":[{\"rounds\":1,\"statusId\":4,\"title\":\"瑞士轮第 1 轮\"},{\"rounds\":2,\"statusId\":4,\"title\":\"瑞士轮第 2 轮\"}],\"selectFilter\":{\"rounds\":\(round),\"title\":\"瑞士轮第 \(round) 轮\"}}}"
            case let path where path.hasPrefix("/v1/match/grades/"):
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let valid = request.httpMethod == "GET" && request.httpBody == nil &&
                    request.value(forHTTPHeaderField: "Authorization") != nil &&
                    query.contains { $0.name == "grade" && ["1", "2", "3"].contains($0.value ?? "") } &&
                    query.contains { $0.name == "statusid" && ["4", "5"].contains($0.value ?? "") }
                if valid { reportedDuel = true }
                value = valid ? #"{"code":200,"data":{},"msg":"提交成功！"}"# : #"{"code":10100,"msg":"成绩参数错误"}"#
            case let path where path.hasPrefix("/v1/match/against/index/"):
                let body = String(data:request.httpBody ?? Data(),encoding:.utf8) ?? ""
                let components = URLComponents(string:"https://test/?" + body)
                let round = components?.queryItems?.first { $0.name == "round" }?.value ?? "1"
                let stage = components?.queryItems?.first { $0.name == "status_id" }?.value ?? "4"
                if round.isEmpty, stage.isEmpty { pairingVisits += 1 }
                let id = stage == "5" ? 503 : round == "2" ? 502 : 501
                value = "{\"code\":200,\"data\":{\"count\":1,\"role\":\"player\",\"selectFilter\":{\"statusId\":4,\"rounds\":1},\"filter\":[{\"title\":\"瑞士轮第 1 轮\",\"statusId\":4,\"rounds\":1},{\"title\":\"瑞士轮第 2 轮\",\"statusId\":4,\"rounds\":2},{\"title\":\"决赛\",\"statusId\":5,\"rounds\":1}],\"res\":[{\"id\":\(id),\"a_nickname\":\"测试决斗者\",\"b_nickname\":\"对手\",\"a_id\":96,\"b_id\":101,\"desk_name\":\"第1桌\",\"status_view\":\"成绩有效\",\"status_id\":3,\"a_result\":1,\"b_result\":3}]}}"
                if ProcessInfo.processInfo.arguments.contains("--uitesting-grade-submission"), id == 501 {
                    value = value.replacingOccurrences(of: "\"status_id\":3,\"a_result\":1,\"b_result\":3",
                        with: reportedDuel ? "\"status_id\":2,\"a_result\":3,\"b_result\":0" : "\"status_id\":1,\"a_result\":0,\"b_result\":0")
                        .replacingOccurrences(of: "成绩有效", with: reportedDuel ? "成绩审核中" : "成绩待填报")
                }
                if ProcessInfo.processInfo.arguments.contains("--uitesting-refresh-duels"), pairingVisits > 1, id == 501 {
                    value = value.replacingOccurrences(of: "\"status_id\":1,\"a_result\":0,\"b_result\":0", with: "\"status_id\":3,\"a_result\":1,\"b_result\":3")
                        .replacingOccurrences(of: "成绩待填报", with: "成绩有效")
                }
                if ProcessInfo.processInfo.arguments.contains("--uitesting-grade-submission"), id != 501 {
                    value = value.replacingOccurrences(of: "\"a_result\":1,\"b_result\":3",
                        with: id == 502 ? "\"a_result\":2,\"b_result\":2" : "\"a_result\":4,\"b_result\":4")
                }
                if ProcessInfo.processInfo.arguments.contains("--uitesting-dense-duels"),
                   var envelope = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                   var data = envelope["data"] as? [String: Any],
                   let template = (data["res"] as? [[String: Any]])?.first {
                    data["res"] = (0..<12).map { index in
                        var row = template
                        row["id"] = id * 100 + index
                        row["desk_name"] = "第\(index + 1)桌"
                        row["a_nickname"] = "很长的选手昵称·测试决斗者\(index + 1)"
                        if stage == "4", index > 0 { row["a_id"] = 9000 + index; row["b_id"] = 8000 + index }
                        return row
                    }
                    data["count"] = 12
                    envelope["data"] = data
                    value = String(data: try JSONSerialization.data(withJSONObject: envelope), encoding: .utf8)!
                }
            case "/v1/match/order/index":
                let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems ?? []
                let valid = request.httpMethod == "GET" && query.contains { $0.name == "type" && $0.value == "1" } && query.contains { $0.name == "status" && $0.value == "-2" }
                value = valid ? #"{"code":200,"data":{"count":1,"res":[{"id":58221,"order_id":160242,"name":"YCS 中国 2025","cost":80,"status":7,"type":1,"image":"https://source.windoent.com/images/default_avatar.jpg"}],"orderStatusMap":[{"7":"超时未付款"}]}}"# : #"{"code":10100,"msg":"订单查询参数错误"}"#
            case "/v1/personal/management/player":
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let ended = body.split(separator: "&").contains("status=8")
                let active = body.split(separator: "&").contains("status=3")
                let row = ended ? #"{"id":102,"name":"测试已结束赛事","statusId":8,"isBackup":true}"# : active ? #"{"id":901,"name":"测试巡回赛","statusId":3}"# : #"{"id":101,"name":"测试已报名赛事","statusId":2}"#
                value = "{\"code\":200,\"data\":{\"count\":1,\"res\":[\(row)]}}"
            case "/v1/new/personal/match":
                value = "{\"code\":200,\"data\":{\"res\":[{\"match_id\":101,\"name\":\"测试个人赛事\",\"address\":\"测试赛场\",\"startAt\":\"2026-10-18 14:00\",\"bottom_status\":\"已报名\"}]}}"
            case "/v1/notice/center/unread": value = "{\"code\":200,\"data\":{\"count\":2}}"
            case "/v1/notice/center":
                let page = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
                let ids = Array((1...21).dropFirst((page - 1) * 20).prefix(20))
                let notices = ids.map { "{\"id\":\($0),\"title\":\"测试通知 \($0)\",\"content\":\"赛程更新\"}" }.joined(separator: ",")
                value = "{\"code\":200,\"data\":{\"count\":21,\"list\":[\(notices)]}}"
            default:
                if path.hasPrefix("/v1/match/info/") {
                    let id = request.url!.lastPathComponent
                    let signed = signedMatches.contains(id)
                    let name = id == "901" ? "测试巡回赛" : "测试比赛 \(id)"
                    let live = ProcessInfo.processInfo.arguments.contains("--uitesting-live-match")
                    let participant = signed || (live && !ProcessInfo.processInfo.arguments.contains("--uitesting-not-participant")) || id == "102"
                    let detailStatus = live ? 3 : id == "102" ? 8 : 2
                    let pending = ProcessInfo.processInfo.arguments.contains("--uitesting-pending-registration")
                    let signCount = ProcessInfo.processInfo.arguments.contains("--uitesting-full-match") ? 32 : 12
                    let checkedIn = ProcessInfo.processInfo.arguments.contains("--uitesting-checked-in")
                    let bottom = pending ? #","bottom":{"title":{"text":"待开放"}}"# : ""
                    value = "{\"code\":200,\"data\":{\"info\":{\"id\":\(id),\"Status\":\(detailStatus),\"Type\":1,\"Condition\":2,\"IsOnlinePayment\":2,\"Rounds\":3,\"Winning\":4,\"IsDeck\":true,\"basic_info\":{\"name\":\"\(name)\",\"start_at\":\"2026-10-21 18:30\",\"customer_name\":\"测试卡店 1\",\"address_info\":\"上海市测试赛场\"},\"desc_info\":{\"rule_display\":\"瑞士轮3轮出4强\",\"cost_int\":2500,\"join_condition\":\"25元购买1包卡包\",\"contact\":\"店铺联系信息\",\"prize_desc\":\"<p>冠军奖品</p>\",\"remarks\":\"<p>测试比赛说明</p>\"},\"player\":{\"sign_count\":\(signCount),\"player_count\":32},\"privacy\":\"<p>请遵守赛事规则</p>\"},\"isSignup\":\(participant),\"isArrive\":\(checkedIn)\(bottom)}}"
                } else if path.hasPrefix("/v1/match/signup/") {
                    if request.httpMethod == "DELETE", rejectWithdrawalOnce {
                        rejectWithdrawalOnce = false
                        value = "{\"code\":40001,\"msg\":\"测试原因：当前比赛暂不允许退赛\",\"data\":{}}"
                    } else {
                        if request.httpMethod == "DELETE" { signedMatches.remove(request.url!.lastPathComponent) }
                        else { signedMatches.insert(request.url!.lastPathComponent) }
                        value = "{\"code\":200,\"data\":{}}"
                    }
                } else                 if path.hasPrefix("/v1/news/info/") {
                    value = "{\"code\":200,\"data\":{\"info\":{\"title\":\"测试新闻正文\",\"author\":\"新闻作者\",\"time_desc\":\"今天\",\"details\":\"<p>这是一条完整的新闻动态。</p>\"}}}"
                } else {
                    value = "{\"code\":200,\"data\":{}}"
                }
            }
        }
        return (Data(value.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
