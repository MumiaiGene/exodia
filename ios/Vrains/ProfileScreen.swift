import SwiftUI

struct ProfileScreen: View {
    @AppStorage(TokenLogin.preferenceKey) private var tokenLogin = false
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(JHSAccountStore.self) private var jhs
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogin = false
    @State private var showingLogout = false
    @State private var showingJHSBinding = false
    @State private var showingCart = false
    @State private var showingPreorders = false
    @State private var info: ProfileDestination?

    var body: some View {
        List {
            Section { accountCard }
            if let message=account.sessionMessage {
                Section { Label(message,systemImage:"exclamationmark.circle").foregroundStyle(Design.accent).accessibilityIdentifier("profile.sessionMessage") }
            }
            if account.isLoggedIn {
                Section("一起来决斗") {
                    personalMatchCard
                    profileRow("比赛订单",subtitle:"",icon:"receipt",destination:.orders)
                    profileRow("消息中心",subtitle:account.unreadCount.map{"\($0) 条未读消息"} ?? "赛事通知",icon:"bell",destination:.messages)
                }
            }
            Section("集换社") {
                jhsRow
                Button { showingCart=true } label: { Label("购物车",systemImage:"cart") }.accessibilityIdentifier("profile.jhs.cart")
                Button {showingPreorders=true} label:{Label("预购清单",systemImage:"list.bullet.clipboard")}.accessibilityIdentifier("profile.jhs.preorders")
            }
            Section("Vrains") { profileRow("关于 Vrains",subtitle:"版本、数据来源与隐私",icon:"info.circle",destination:.about) }
            if account.isLoggedIn {
                Section {
                    Button("退出“一起来决斗”账号",role:.destructive){showingLogout=true}
                        .frame(maxWidth:.infinity,alignment:.center).accessibilityIdentifier("profile.logout")
                }
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Design.canvas)
            .refreshable { await account.refresh() }
            .navigationTitle("个人").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    ModalCloseButton().accessibilityIdentifier("profile.close")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button { info = .settings } label: { Image(systemName:"gearshape").fontWeight(.semibold) }
                        .accessibilityLabel("设置").accessibilityIdentifier("profile.settings")
                }
            }
            .sheet(isPresented: $showingLogin) { LoginSheet() }
            .sheet(isPresented:$showingJHSBinding) { JHSBindingSheet() }
            .sheet(isPresented:$showingCart) { JHSCartScreen() }
            .sheet(isPresented:$showingPreorders) { JHSPreordersScreen() }
            .sheet(item: $info) { destination in
                switch destination {
                case .cards: CardBrowserScreen(favoritesMode: true)
                case .cardData: CardDataScreen()
                case .profile: ProfileDetailsSheet()
                case .personalMatches: PersonalMatchesSheet()
                case .messages: MessagesSheet()
                case .orders: MatchOrdersSheet()
                default: ProfileDestinationSheet(destination: destination)
                }
            }
            .confirmationDialog("退出当前账号？", isPresented: $showingLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    do { try account.signOut() } catch { account.sessionMessage = error.localizedDescription }
                }
                Button("取消", role: .cancel) { }
            }
    }
    private var personalMatchCard: some View {
        Button { info = .personalMatches } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("参加比赛总场数：\(account.statistics?.total.map(String.init) ?? "—")", systemImage: "calendar.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                if let statistics = account.statistics {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(statistics.topCategories) { category in
                            let kind = MatchKind.catalog.first { $0.id == category.typeID } ?? MatchKind(id: category.typeID, title: category.name)
                            VStack(spacing: 8) {
                                Text(category.count.map(String.init) ?? "—").font(.title2.bold()).monospacedDigit().foregroundStyle(kind.tint)
                                Text(kind.id == 20 ? "YCSC" : category.name).font(.caption).foregroundStyle(Design.ink).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
            }.foregroundStyle(Design.ink).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("profile.row.我的比赛")
    }
    private var accountCard:some View {
        Button { account.isLoggedIn ? (info = .profile):(showingLogin = true) } label:{
            HStack(spacing:16) {
                ZStack {
                    Circle().fill(Color(uiColor:.tertiarySystemFill))
                    Image(systemName:account.isLoggedIn ? "person.fill":"person").font(.system(size:27)).foregroundStyle(Design.secondary)
                    if let url=account.profile?.avatarURL { AsyncImage(url:url){image in image.resizable().scaledToFill()}placeholder:{Color.clear}.clipShape(Circle()) }
                }.frame(width:66,height:66)
                VStack(alignment:.leading,spacing:5) {
                    Text(account.displayName).font(.title3.bold()).foregroundStyle(Design.ink).accessibilityIdentifier("profile.title")
                    Text(account.isLoggedIn ? account.maskedPhone:"登录“一起来决斗”账号").font(.subheadline).foregroundStyle(Design.secondary)
                    if let signature=account.profile?.signature { Text(signature).font(.caption).foregroundStyle(Design.secondary).lineLimit(1) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }.padding(.vertical,8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(account.isLoggedIn ? "profile.account":"profile.login")
    }
    private var jhsRow:some View {
        Button { if tokenLogin || account.isLoggedIn || jhs.isBound { showingJHSBinding=true } else { showingLogin=true } } label:{
            HStack(spacing:14) {
                Image(systemName:"link.circle.fill").font(.system(size:25)).foregroundStyle(.orange).frame(width:30)
                VStack(alignment:.leading,spacing:4) {
                    Text(jhs.isBound ? "集换社":"绑定集换社").foregroundStyle(Design.ink)
                    Text(jhs.isBound ? "已绑定 · \(jhs.maskedPhone)":tokenLogin ? "使用 token 登录":account.isLoggedIn ? "使用当前账号手机号验证":"先登录“一起来决斗”账号")
                        .font(.caption).foregroundStyle(Design.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("profile.jhs.bind")
    }
    private func profileRow(_ title: String, subtitle: String, icon: String, destination: ProfileDestination) -> some View {
        Button { info = destination } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular)).foregroundStyle(Design.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.body).foregroundStyle(Design.ink)
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(Design.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Design.secondary.opacity(0.6))
            }.frame(minHeight:50).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("profile.row.\(destination.id)")
    }
}

struct JHSBindingSheet:View {
    @AppStorage(TokenLogin.preferenceKey) private var tokenLogin = false
    @Environment(AccountStore.self) private var account
    @Environment(JHSAccountStore.self) private var jhs
    @Environment(\.dismiss) private var dismiss
    @State private var code=""
    @State private var didSend=false
    @State private var errorMessage:String?
    @State private var operation:Task<Void,Never>?
    @State private var confirmingUnbind=false
    @FocusState private var codeFocused:Bool
    private var phone:String?{account.session?.phone}
    var body:some View {
        NavigationStack {
            Form {
                if jhs.isBound { boundContent } else {
                    if tokenLogin {
                        TokenLoginFields(identifier: "jhs.token") { token in try jhs.importToken(token); dismiss() }
                    } else { bindingContent }
                }
            }.navigationTitle(jhs.isBound ? "集换社":"登录集换社").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction){ ModalCloseButton(action:{dismiss()}).accessibilityIdentifier("jhs.binding.back") } }
                .scrollDismissesKeyboard(.interactively)
        }.presentationDragIndicator(.visible)
            .confirmationDialog("解除集换社绑定？",isPresented:$confirmingUnbind,titleVisibility:.visible) {
                Button("解除绑定",role:.destructive){do{try jhs.unbind();dismiss()}catch{errorMessage=error.localizedDescription}}
                Button("取消",role:.cancel){}
            }
            .onDisappear{operation?.cancel()}
    }
    @ViewBuilder private var boundContent:some View {
        Section("当前绑定") {
            LabeledContent("状态",value:"已绑定")
            LabeledContent("手机号",value:jhs.maskedPhone)
            if let name=jhs.session?.username { LabeledContent("集换社账号",value:name) }
        }
        if let errorMessage { Section { Text(errorMessage).foregroundStyle(Design.accent).accessibilityIdentifier("jhs.bind.error") } }
        Section { Button("解除集换社绑定",role:.destructive){confirmingUnbind=true}.accessibilityIdentifier("jhs.unbind") }
    }
    @ViewBuilder private var bindingContent:some View {
        Section("验证手机号") {
            LabeledContent("当前账号",value:masked(phone))
            TimelineView(.periodic(from:.now,by:1)){context in
                let remaining=max(0,Int(ceil(jhs.resendAt.timeIntervalSince(context.date))))
                Button {
                    sendCode()
                } label:{
                    HStack { Text(remaining>0 ? "\(remaining)s 后重新获取":didSend ? "重新获取验证码":"获取集换社验证码");Spacer();if jhs.isSending{ProgressView()} }
                }.disabled(phone==nil || jhs.isSending || remaining>0).accessibilityIdentifier("jhs.bind.sendCode")
            }
        }
        Section("短信验证码") {
            TextField("4至8位验证码",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode).focused($codeFocused)
                .onChange(of:code){_,value in let cleaned=String(value.filter{ $0.isASCII && $0.isNumber }.prefix(8));if cleaned != value{code=cleaned};errorMessage=nil}
                .accessibilityIdentifier("jhs.bind.code")
            if didSend { Label("验证码已发送",systemImage:"checkmark.message").font(.footnote).foregroundStyle(.green).accessibilityIdentifier("jhs.bind.codeSent") }
            if let errorMessage { Label(errorMessage,systemImage:"exclamationmark.circle").font(.footnote).foregroundStyle(Design.accent).accessibilityIdentifier("jhs.bind.error") }
        }
        Section { Button { bind() } label:{HStack{Spacer();if jhs.isBinding{ProgressView()}else{Text("登录")};Spacer()}}
            .disabled(jhs.isBinding || code.count<4).accessibilityIdentifier("jhs.bind.submit") }
    }
    private func sendCode() {
        errorMessage=nil;guard let phone else{errorMessage=JHSAuthError.invalidPhone.localizedDescription;return}
        operation=Task{@MainActor in do{try await jhs.sendCode(phone:phone);didSend=true;codeFocused=true}catch is CancellationError{}catch{errorMessage=AccountStore.message(for:error)}}
    }
    private func bind() {
        errorMessage=nil;guard let phone else{errorMessage=JHSAuthError.invalidPhone.localizedDescription;return}
        operation=Task{@MainActor in do{try await jhs.bind(phone:phone,code:code);dismiss()}catch is CancellationError{}catch{errorMessage=AccountStore.message(for:error)}}
    }
    private func masked(_ value:String?)->String {
        guard let value,value.count==11 else{return "手机号不可用"};return "\(value.prefix(3)) ···· \(value.suffix(4))"
    }
}

struct LoginSheet: View {
    @AppStorage(TokenLogin.preferenceKey) private var tokenLogin = false
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var agreed = false
    @State private var isSending = false
    @State private var isLoggingIn = false
    @State private var didSendCode = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?
    @State private var legalPage: ProfileDestination?
    @FocusState private var focusedField: Field?
    private enum Field { case phone, code }

    var body: some View {
        NavigationStack {
            loginContents.navigationTitle("登录一起来决斗").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { ModalCloseButton().accessibilityIdentifier("login.close") } }
        }.presentationDragIndicator(.visible)
            .sheet(item:$legalPage) { ProfileDestinationSheet(destination:$0) }
            .onDisappear { operation?.cancel() }
    }
    @ViewBuilder private var loginContents: some View {
        Form {
            if tokenLogin {
                Section {TokenLoginFields(identifier:"login.token") {token in try await account.importToken(token);dismiss()}}
            } else {
                Section("手机号") {
                    HStack(spacing:12) {
                        Text("+86").foregroundStyle(.secondary)
                        TextField("请输入手机号",text:$phone)
                            .keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .focused($focusedField,equals:.phone).accessibilityIdentifier("login.phone")
                            .onChange(of:phone) {_,value in
                                let cleaned=String(value.filter {$0.isASCII && $0.isNumber}.prefix(11))
                                if value != cleaned {phone=cleaned};errorMessage=nil
                            }
                    }
                }
                Section("验证码") {
                    HStack(spacing:8) {
                        TextField("请输入短信验证码",text:$code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($focusedField,equals:.code).accessibilityIdentifier("login.code")
                            .onChange(of:code) {_,value in
                                let cleaned=String(value.filter {$0.isASCII && $0.isNumber})
                                if value != cleaned {code=cleaned};errorMessage=nil
                            }
                        TimelineView(.periodic(from:.now,by:1)) {context in
                            let remaining=max(0,Int(ceil(account.resendAt.timeIntervalSince(context.date))))
                            Button {sendCode()} label: {
                                if isSending {ProgressView()}
                                else {Text(remaining > 0 ? "\(remaining) 秒后重发" : didSendCode ? "重新获取" : "获取验证码").font(.subheadline.weight(.semibold))}
                            }.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large).frame(minHeight:44)
                                .disabled(isSending || isLoggingIn || remaining > 0).accessibilityIdentifier("login.sendCode")
                        }
                    }
                }
                if let errorMessage {Section {Label(errorMessage,systemImage:"exclamationmark.circle").foregroundStyle(Design.accent).accessibilityIdentifier("login.error")}}
                if didSendCode {Section {Label("验证码已发送",systemImage:"checkmark.message").accessibilityIdentifier("login.codeSent")}}
                Section {
                    Toggle("我已阅读并同意",isOn:$agreed).accessibilityIdentifier("login.agreement")
                    HStack(spacing:8) {
                        Button {legalPage = .terms} label:{Text("用户协议").frame(minHeight:44).contentShape(Rectangle())}
                        Text("及").foregroundStyle(.secondary)
                        Button {legalPage = .privacy} label:{Text("隐私政策").frame(minHeight:44).contentShape(Rectangle())}
                    }.buttonStyle(.borderless).font(.subheadline)
                }
                Section {
                    Button {login()} label: {
                        HStack {Spacer();if isLoggingIn {ProgressView()} else {Text("登录")};Spacer()}
                    }.primaryActionStyle().disabled(isSending || isLoggingIn).accessibilityIdentifier("login.submit")
                }
            }
        }.scrollContentBackground(.hidden).background(Design.canvas).scrollDismissesKeyboard(.interactively)
    }

    private func sendCode() {
        errorMessage = nil
        focusedField = nil
        guard AccountStore.validPhone(phone) else { errorMessage = APIError.invalidPhone.localizedDescription; return }
        let requestedPhone = phone
        isSending = true
        operation = Task { @MainActor in
            defer { isSending = false }
            do {
                try await account.sendCode(phone: requestedPhone)
                didSendCode = true
            } catch is CancellationError { }
            catch { errorMessage = AccountStore.message(for: error) }
        }
    }
    private func login() {
        errorMessage = nil
        focusedField = nil
        guard agreed else { errorMessage = "请先阅读并同意用户协议与隐私政策。"; return }
        let loginPhone = phone
        let loginCode = code
        isLoggingIn = true
        operation = Task { @MainActor in
            defer { isLoggingIn = false }
            do {
                try await account.signIn(phone: loginPhone, code: loginCode)
                dismiss()
            } catch is CancellationError { }
            catch { errorMessage = AccountStore.message(for: error) }
        }
    }
}

private struct VrainsInformationSection: Identifiable {
    let title: String
    let text: String
    var id: String { title }
}

private enum VrainsInformation {
    static let terms: [VrainsInformationSection] = [
        .init(title:"服务范围",text:"本协议适用于 Vrains 的使用。Vrains 提供卡牌检索、卡组编辑与分享、资料更新、比赛信息、账号连接、商品查询及预购匹配。决斗页面标注为演示的功能不连接真实玩家。"),
        .init(title:"账号与第三方服务",text:"登录一起来决斗或绑定集换社时，你授权 Vrains 使用所填写的登录信息访问对应服务。两个账号分别管理，适用各服务的账号规则。请使用你有权访问的账号，并妥善保管登录凭据。"),
        .init(title:"比赛操作",text:"在你确认后，Vrains 会向一起来决斗发送报名、退赛或成绩提交请求。参赛资格、审核、费用和退款由比赛主办方及服务提供方决定；需要支付时，应在相应服务中完成。提交结果以服务端确认及比赛记录为准。"),
        .init(title:"商品与匹配",text:"预购清单用于记录想购买的版本，匹配用于比较符合条件的购买方案，不会自动下单或付款。加入购物车需由你主动操作；价格、库存、品相和运费以集换社的最新信息及实际结算结果为准。"),
        .init(title:"本机数据与分享",text:"卡组、收藏、预购清单和匹配记录保存在本机，不会因登录账号自动同步到其他设备。卸载 App 或移除本机数据可能导致记录丢失。请在分享卡组或图片前确认内容，并自行保存需要保留的数据。"),
        .init(title:"内容与权利",text:"卡牌图片、名称、效果和第三方内容的权利归相应权利人所有。Vrains 展示数据来源；第三方内容的更新、准确性及可用性由各来源决定。你通过 Vrains 编辑或分享内容时，应遵守适用的法律及相关服务规则。"),
        .init(title:"网络与服务变更",text:"网络或第三方服务异常可能造成查询和操作失败。结果不明确时，请先核对记录，再决定是否重试。Vrains 的功能或本协议更新后，可在 App 中查看新的说明。")
    ]
    static let privacy: [VrainsInformationSection] = [
        .init(title:"账号信息",text:"你主动登录一起来决斗时，手机号和短信验证码通过加密网络连接发送至一起来决斗服务。绑定集换社时，绑定手机号和集换社验证码发送至集换社服务。两个服务的登录凭据分别使用，不相互交换。"),
        .init(title:"登录凭据",text:"登录凭据及绑定账号信息保存在设备的系统安全存储中，不写入普通偏好设置或日志。退出账号或解除绑定会删除对应凭据，不影响另一个服务的登录。"),
        .init(title:"本机记录",text:"卡组、收藏、预购清单、匹配记录及已下载的卡牌资料保存在本机。分享或导出仅在你主动操作时进行。"),
        .init(title:"位置权限",text:"在你允许后，Vrains 使用设备位置获取所在城市，便于浏览附近比赛和店铺。你也可以手动选择地区，或在系统设置中关闭位置权限。"),
        .init(title:"照片与通知",text:"保存分享图片时会请求相册写入权限；开启匹配完成通知时会请求通知权限。你可以在系统设置中调整这些权限。"),
        .init(title:"其他信息",text:"Vrains 不读取通讯录，不保存账号密码，不包含广告或分析 SDK。第三方服务收到的信息由各服务按其隐私规则处理。")
    ]
}

enum ProfileDestination: String, Identifiable {
    case cards = "我的收藏", matches = "关注的比赛", decks = "我的卡组"
    case settings = "设置", about = "关于 Vrains", terms = "用户协议", privacy = "隐私政策"
    case orders = "比赛订单"
    case profile = "个人资料", personalMatches = "我的比赛", messages = "消息中心", cardData = "卡牌数据"
    var id: String { rawValue }
}

struct ProfileDestinationSheet: View {
    @AppStorage(TokenLogin.preferenceKey) private var tokenLogin = false
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(JHSAccountStore.self) private var jhs
    @Environment(CardCatalog.self) private var catalog
    let destination: ProfileDestination
    @State private var showingCardData = false
    @State private var copiedService: String?
    var body: some View {
        Group {
        if destination == .settings { settingsView }
        else { NavigationStack { ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch destination {
                case .profile, .personalMatches, .messages, .orders, .cards, .cardData:
                    Text("请从个人页面打开。")
                case .matches:
                    let matches = Tournament.samples.filter { store.followedMatches.contains($0.id) }
                    if matches.isEmpty { EmptyState(icon: "calendar", title: "期待下一场相遇", subtitle: "在比赛页关注感兴趣的赛事。") }
                    ForEach(matches) { match in MatchRow(match: match, isFollowed: true) }
                case .decks:
                    ForEach(store.myDecks) { deck in
                        HStack(spacing: 16) {
                            Artwork(kind: deck.kind, compact: true).frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 8) { Text(deck.name).font(.headline); Text("\(deck.cards) 张卡牌").font(.caption).foregroundStyle(Design.secondary) }
                        }
                    }
                case .settings: EmptyView()
                case .about:
                    information("Vrains", text: "查找卡牌、管理卡组、浏览比赛与店铺，并连接一起来决斗和集换社账号。")
                    if let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String {
                        information("版本",text:version)
                    }
                    information("数据来源",text:"卡牌、卡包和禁限卡表来自游戏王官方数据库；日文卡图来自 Neuron；中文卡名与文本优先采用游戏王官方简中资料，缺失部分参考百鸽数据库收录的 NWBBS 等译名与中文文本。新闻、账号和比赛信息由一起来决斗提供，集换社提供在售商品、版本及购物车服务。")
                    information("本机数据",text:"卡组、收藏、预购清单和匹配记录保存在本机。决斗页面当前为演示模式。")
                case .terms:
                    ForEach(VrainsInformation.terms) { section in information(section.title,text:section.text) }
                case .privacy:
                    ForEach(VrainsInformation.privacy) { section in information(section.title,text:section.text) }
                }
            }.padding(24)
        }.background(Design.canvas)
            .navigationTitle(destination.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { ModalCloseButton().accessibilityIdentifier("navigation.back") } }
        } }
        }.presentationDragIndicator(.visible)
            .sheet(isPresented: $showingCardData) { CardDataScreen() }
    }
    private var settingsView: some View {
        NavigationStack {
            Form {
                Section {
                    LocationPermissionView()
                    Picker("禁限卡表", selection: Binding(get: { catalog.selectedFormat }, set: { catalog.selectedFormat = $0 })) {
                        ForEach(CardFormat.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("settings.banlist").accessibilityValue(catalog.selectedFormat.title)
                    Button { showingCardData = true } label: {
                        HStack {
                            Text("卡牌数据与更新").foregroundStyle(Design.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }.accessibilityIdentifier("settings.cardData")
                }
                Section {
                    DisclosureGroup("高级设置") {
                        Toggle("使用 token 登录", isOn: $tokenLogin).accessibilityIdentifier("settings.tokenLogin")
                        Button("复制一起来决斗 token") { copyToken(account.session?.token, service: "一起来决斗") }
                            .disabled(account.session == nil).accessibilityIdentifier("settings.copyMatchToken")
                        Button("复制集换社 token") { copyToken(jhs.session?.token, service: "集换社") }
                            .disabled(jhs.session == nil).accessibilityIdentifier("settings.copyJHSToken")
                        if let copiedService { Text("已复制\(copiedService) token").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }.scrollContentBackground(.hidden).background(Design.canvas)
                .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { ModalCloseButton().accessibilityIdentifier("navigation.back") } }
        }
    }
    private func copyToken(_ token: String?, service: String) {
        guard let token else { return }
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: token]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
        copiedService = service
    }
    private func information(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(Design.ink)
            Text(text).font(.subheadline).lineSpacing(7).foregroundStyle(Design.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenLoginFields: View {
    let identifier: String
    let submit: (String) async throws -> Void
    @State private var token = ""
    @State private var loading = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SecureField("输入 token", text: $token)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .privacySensitive().accessibilityIdentifier(identifier)
                .textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.footnote).foregroundStyle(Design.accent) }
            Button {
                loading = true; error = nil
                operation = Task { @MainActor in
                    defer { loading = false }
                    do { try await submit(token); token = "" }
                    catch is CancellationError { }
                    catch { self.error = AccountStore.message(for: error) }
                }
            } label: {
                HStack { Spacer(); if loading { ProgressView() } else { Text("登录") }; Spacer() }
            }.primaryActionStyle().disabled(loading || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(identifier + ".submit")
        }.onDisappear { operation?.cancel(); token = "" }
    }
}

struct JHSCartScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JHSAccountStore.self) private var jhs
    @State private var store=JHSCartStore()
    @State private var binding=false
    @State private var removing:JHSCartItem?
    @State private var previewImage:JHSArtworkPreviewItem?
    var body:some View {
        NavigationStack {
            List {
                if !jhs.isBound {
                    ContentUnavailableView {Label("登录集换社后查看购物车",systemImage:"cart")} actions:{Button("绑定集换社"){binding=true}}
                } else if store.loading && store.sellers.isEmpty {
                    ProgressView("正在加载购物车").frame(maxWidth:.infinity)
                } else if let error=store.error,store.sellers.isEmpty {
                    ContentUnavailableView {Label("购物车加载失败",systemImage:"exclamationmark.triangle")} description:{Text(error)} actions:{Button("重试"){Task{await load()}}}
                } else if store.sellers.isEmpty {
                    ContentUnavailableView("购物车是空的",systemImage:"cart",description:Text("可在卡牌在售列表中添加商品。"))
                } else {
                    ForEach(store.sellers) {seller in sellerSection(seller)}
                    if let error=store.error {
                        Section {Text(error).foregroundStyle(.secondary);Button("重新加载"){Task{await store.loadMore()}}}
                    } else if store.hasMore {
                        ProgressView().frame(maxWidth:.infinity).task{await store.loadMore()}
                    }
                    Section {LabeledContent(store.hasMore ? "已加载商品合计":"商品合计",value:store.sellers.reduce(0){$0+$1.total}.formatted(.currency(code:"CNY")))}
                        footer:{Text("不含失效商品和运费，以集换社结算时为准。")}
                }
            }.navigationTitle("购物车").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.topBarLeading){ModalCloseButton(hitSize:44,action:{dismiss()})}}
                .refreshable {if store.changing.isEmpty{await load()}}
                .task(id:jhs.session?.token){await load()}
                .sheet(isPresented:$binding){JHSBindingSheet()}
                .fullScreenCover(item:$previewImage){JHSArtworkPreview(url:$0.url)}
                .alert("从购物车移除？",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),presenting:removing) {item in
                    Button("移除",role:.destructive){removing=nil;Task{await store.change(item,to:0,confirmedRemoval:true)}}
                    Button("取消",role:.cancel){removing=nil}
                } message:{item in Text("将“\(item.name)”的数量减为 0，并从购物车移除。")}
                .alert("未能更新购物车",isPresented:Binding(get:{store.writeError != nil},set:{if !$0{store.writeError=nil}})) {Button("好",role:.cancel){}} message:{Text(store.writeError ?? "")}
                .accessibilityIdentifier("jhs.cart.list")
        }
    }
    private func sellerSection(_ seller:JHSCartSeller)->some View {
        Section {
            Button {Task{await store.toggle(seller.id)}} label:{
                HStack(alignment:.top,spacing:12) {
                    VStack(alignment:.leading,spacing:6) {
                        Text(seller.name).font(.headline).foregroundStyle(.primary)
                        Text("\(seller.count) 件商品").font(.caption).foregroundStyle(.secondary)
                        Text(seller.total,format:.currency(code:"CNY")).font(.subheadline).foregroundStyle(.primary)
                        if seller.invalidCount>0 {Text("\(seller.invalidCount) 件商品已失效").font(.caption).foregroundStyle(.red)}
                        if seller.insufficientCount>0 {Text("\(seller.insufficientCount) 件商品库存不足").font(.caption).foregroundStyle(.orange)}
                    }
                    Spacer()
                    Image(systemName:store.expanded.contains(seller.id) ? "chevron.up":"chevron.down").foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("jhs.cart.seller.\(seller.id)")
            if store.expanded.contains(seller.id) {
                if store.loadingSellers.contains(seller.id) {ProgressView("正在加载商品")}
                else if let error=store.sellerErrors[seller.id] {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("重试加载商品"){Task{await store.loadItems(seller.id)}}
                } else if let rows=store.items[seller.id] {
                    if rows.isEmpty{Text("该卖家购物车已清空").foregroundStyle(.secondary)}
                    ForEach(rows){item in itemRow(item)}
                }
            }
        }
    }
    private func itemRow(_ item:JHSCartItem)->some View {
        HStack(alignment:.top,spacing:12) {
            Button {
                if let url=item.imageURL{previewImage=JHSArtworkPreviewItem(url:url)}
            } label:{
                AsyncImage(url:item.imageURL){image in image.resizable().scaledToFit()} placeholder:{Image(systemName:"photo").foregroundStyle(.secondary)}.frame(width:54,height:78).contentShape(Rectangle())
            }.buttonStyle(.borderless).disabled(item.imageURL==nil)
                .accessibilityLabel("查看\(item.name)卡图").accessibilityIdentifier("jhs.cart.image.\(item.id)")
            VStack(alignment:.leading,spacing:5) {
                Text(item.name).font(.headline).accessibilityIdentifier("jhs.cart.item.\(item.id)")
                Text([item.number,item.rarity].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                if item.isInvalid {Text("商品已失效").font(.caption).foregroundStyle(.red)}
                else if let stock=item.stock,item.quantity>stock {Text("库存不足，仅剩 \(stock) 张").font(.caption).foregroundStyle(.orange)}
                if let price=item.price {Text(price,format:.currency(code:"CNY")).foregroundStyle(item.isInvalid ? .secondary:.primary)}
                if let remark=item.remark {Text(remark).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("jhs.cart.remark.\(item.id)")}
                HStack(spacing:0) {
                    quantityButton("minus",label:"减少数量",id:"minus",item:item) {
                        if item.quantity==1 || item.isInvalid{removing=item}else{Task{await store.change(item,to:item.quantity-1)}}
                    }
                    Text("\(item.quantity)").monospacedDigit().frame(minWidth:32).accessibilityIdentifier("jhs.cart.quantity.\(item.id)")
                    quantityButton("plus",label:"增加数量",id:"plus",item:item){Task{await store.change(item,to:item.quantity+1)}}
                        .disabled(item.isInvalid || item.cardID==nil || item.stock.map{item.quantity >= $0}==true)
                    if store.changing.contains(item.id){ProgressView().padding(.leading,8)}
                }.disabled(!store.changing.isEmpty || store.sellerErrors[item.sellerID] != nil)
            }
        }
    }
    private func quantityButton(_ icon:String,label:String,id:String,item:JHSCartItem,action:@escaping ()->Void)->some View {
        Button(action:action){Image(systemName:icon).frame(width:44,height:44).contentShape(Rectangle())}
            .buttonStyle(.borderless).accessibilityLabel(label).accessibilityIdentifier("jhs.cart.\(id).\(item.id)")
    }
    @MainActor private func load() async {
        removing=nil
        guard let session=jhs.session else{await store.reset(client:nil);return}
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-cart") {
                await store.reset(client:UITestJHSCartClient());return
            }
            #endif
            guard let profile=try JHSProtocolProfile.resolved() else{throw JHSMarketplaceError.configuration}
            await store.reset(client:DirectJHSMarketplaceClient(profile:profile,session:session))
        } catch {await store.reset(client:nil);store.error=error.localizedDescription}
    }
}

struct JHSPreordersScreen:View {
    @Environment(\.dismiss) private var dismiss
    @State private var store=JHSPreorderStore.shared
    @State private var selection:JHSPreorderItem?
    @State private var error:String?
    @State private var showingMatch=false
    @State private var matchJobID:UUID?
    @State private var jobs=JHSMatchJobsStore.shared
    var body:some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {JHSMatchJobsScreen()}label:{Label("匹配任务",systemImage:"clock.arrow.circlepath")}.accessibilityIdentifier("jhs.preorders.jobs")
                }
                if store.items.isEmpty {
                    ContentUnavailableView("预购清单是空的",systemImage:"list.bullet.clipboard",description:Text("在卡牌在售页点击右上角按钮，添加想购买的版本。"))
                } else {
                    ForEach(store.items) {item in
                        Button {selection=item} label:{
                            HStack(spacing:14) {
                                JHSVersionArtwork(item:item).frame(width:56,height:82)
                                VStack(alignment:.leading,spacing:7) {
                                    Text(item.name).font(.headline).foregroundStyle(.primary)
                                    Text(item.rarity).font(.caption.weight(.bold)).foregroundStyle(Design.accent)
                                    Text(item.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical,4).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("jhs.preorders.item.\(item.id)")
                        .swipeActions(edge:.trailing,allowsFullSwipe:true) {
                            Button(role:.destructive){do{try store.remove([item.id])}catch{self.error=error.localizedDescription}}label:{Image(systemName:"trash")}
                                .labelStyle(.iconOnly).accessibilityLabel("删除")
                        }
                    }
                }
            }.navigationTitle("预购清单").navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading){ModalCloseButton().accessibilityIdentifier("jhs.preorders.back")}
                    if !store.items.isEmpty{ToolbarItem(placement:.topBarTrailing){Button{showingMatch=true}label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("设置匹配").accessibilityIdentifier("jhs.preorders.match")}}
                }
                .sheet(isPresented:$showingMatch){JHSMatchBuilderScreen(items:store.items){id in showingMatch=false;matchJobID=id}}
                .navigationDestination(item:$matchJobID){id in JHSMatchJobScreen(jobID:id)}
                .alert("匹配任务保存失败",isPresented:Binding(get:{jobs.persistenceError != nil},set:{if !$0{jobs.persistenceError=nil}})){Button("好",role:.cancel){}}message:{Text(jobs.persistenceError ?? "")}
                .sheet(item:$selection){item in JHSMarketplaceScreen(cardName:item.name,printing:item.printing,cardCID:item.cardCID,artworkID:item.artworkID)}
                .alert("未能保存预购清单",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("好",role:.cancel){}}message:{Text(error ?? "")}
                .accessibilityIdentifier("jhs.preorders.list")
        }
    }
}
