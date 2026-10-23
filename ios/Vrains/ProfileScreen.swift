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
            Section("Exodia") { profileRow("关于 Exodia",subtitle:"版本、数据来源与隐私",icon:"info.circle",destination:.about) }
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
                    CompactBackButton().accessibilityIdentifier("profile.close")
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
                    HStack(spacing: 12) { CompactBackButton(hitSize:44,action:{dismiss()}).accessibilityIdentifier("jhs.binding.back"); Text("登录集换社").font(.headline); Spacer() }
                    if tokenLogin {
                        TokenLoginFields(identifier: "jhs.token") { token in try jhs.importToken(token); dismiss() }
                    } else { bindingContent }
                }
            }.navigationTitle(jhs.isBound ? "集换社":"").navigationBarTitleDisplayMode(.inline)
                .toolbar { if jhs.isBound { ToolbarItem(placement:.topBarLeading){ CompactBackButton(hitSize:44,action:{dismiss()}).accessibilityIdentifier("jhs.binding.back") } } }
                .toolbar(jhs.isBound ? .visible : .hidden, for: .navigationBar)
                .scrollDismissesKeyboard(.interactively)
        }.presentationDragIndicator(.visible).presentationCornerRadius(34)
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
        if tokenLogin {
            VStack(alignment: .leading, spacing: 27) {
                HStack(spacing: 12) { CompactBackButton(); Text("登录一起来决斗").font(.headline); Spacer() }
                TokenLoginFields(identifier: "login.token") { token in try await account.importToken(token); dismiss() }
                Spacer()
            }.padding(26).background(Design.canvas)
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                HStack(spacing: 12) {
                    CompactBackButton()
                    Text("登录一起来决斗").font(.headline)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("手机号").font(.system(size: 12, weight: .semibold)).foregroundStyle(Design.secondary)
                    HStack(spacing: 14) {
                        Text("+86").font(.system(size: 15, weight: .medium))
                        Rectangle().fill(Design.secondary.opacity(0.2)).frame(width: 1, height: 20)
                        TextField("请输入手机号", text: $phone)
                            .keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .focused($focusedField, equals: .phone)
                            .accessibilityIdentifier("login.phone")
                            .onChange(of: phone) { _, value in
                                let cleaned = String(value.filter(\.isNumber).prefix(11))
                                if cleaned != value { phone = cleaned }
                                errorMessage = nil
                            }
                    }.padding(18).background(Design.field,in:RoundedRectangle(cornerRadius:18))
                    Text("验证码").font(.system(size: 12, weight: .semibold)).foregroundStyle(Design.secondary).padding(.top, 4)
                    HStack(spacing: 8) {
                        TextField("请输入短信验证码", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .code)
                            .accessibilityIdentifier("login.code")
                            .onChange(of: code) { _, value in
                                let cleaned = String(value.filter { $0.isASCII && $0.isNumber })
                                if value != cleaned { code = cleaned }
                                errorMessage = nil
                            }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, Int(ceil(account.resendAt.timeIntervalSince(context.date))))
                            Button { sendCode() } label: {
                                if isSending { ProgressView().tint(Design.accent) }
                                else { Text(remaining > 0 ? "\(remaining)s 后重发" : didSendCode ? "重新获取" : "获取验证码").font(.system(size: 12, weight: .semibold)) }
                            }.foregroundStyle(Design.accent)
                                .disabled(isSending || isLoggingIn || remaining > 0)
                                .accessibilityIdentifier("login.sendCode")
                        }
                    }.padding(18).frame(minHeight:58).background(Design.field,in:RoundedRectangle(cornerRadius:18))
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(Design.accent)
                        .accessibilityIdentifier("login.error")
                }
                if didSendCode {
                    Label("验证码已发送", systemImage: "checkmark.message")
                        .font(.system(size: 12)).foregroundStyle(Color(hex: 0x4D8775))
                        .accessibilityIdentifier("login.codeSent")
                }
                Button { login() } label: {
                    HStack { Spacer(); if isLoggingIn { ProgressView() } else { Text("登录") }; Spacer() }.padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(isSending || isLoggingIn).accessibilityIdentifier("login.submit")
                HStack(alignment: .top, spacing: 9) {
                    Button { agreed.toggle() } label: {
                        Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(agreed ? Design.accent : Design.secondary.opacity(0.6))
                            .frame(width: 28, height: 28)
                    }.buttonStyle(.plain).accessibilityLabel("同意用户协议与隐私政策")
                        .accessibilityIdentifier("login.agreement")
                        .accessibilityValue(agreed ? "已同意" : "未同意")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("我已阅读并同意").foregroundStyle(Design.secondary)
                        HStack(spacing: 4) {
                            Button("用户协议") { legalPage = .terms }
                            Text("与").foregroundStyle(Design.secondary)
                            Button("隐私政策") { legalPage = .privacy }
                        }.foregroundStyle(Design.ink)
                    }.font(.system(size: 11)).padding(.top, 3)
                }
            }.padding(26).padding(.bottom, 15)
        }.background(Design.canvas).scrollDismissesKeyboard(.interactively)
            .presentationDragIndicator(.visible).presentationCornerRadius(34)
            .sheet(item: $legalPage) { ProfileDestinationSheet(destination: $0) }
            .onDisappear { operation?.cancel() }
    }
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

enum ProfileDestination: String, Identifiable {
    case cards = "我的收藏", matches = "关注的比赛", decks = "我的卡组"
    case settings = "设置", about = "关于 Exodia", terms = "用户协议", privacy = "隐私政策"
    case orders = "比赛订单"
    case profile = "个人资料", personalMatches = "我的比赛", messages = "消息中心", cardData = "卡片数据"
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
        else { ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { GlassBackButton(); Text(destination.rawValue).font(.title2.bold()); Spacer() }
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
                    Text("为热爱而决斗。").font(.largeTitle.bold())
                    information("EXODIA / 01", text: "一个关于卡牌、构筑与相遇的原型。参考 iOS 原生应用的排版和材质，让信息轻盈，让热爱成为主角。")
                    information("数据来源", text: "账号、个人资料和个人赛事来自 Windoent 服务。其他页面仍使用原型示例资料，卡组封面为原创图形示意。")
                case .terms:
                    information("账号服务说明", text: "手机号验证码登录使用 Windoent 账号服务，会向你填写的手机号发送短信，并读取该账号的个人资料、赛事统计和通知。本 App 不提供支付或报名提交。")
                    information("本机功能", text: "卡组、收藏和赛事关注目前保存于本机。它们与账号服务中的资料和赛事数据分别管理。")
                case .privacy:
                    information("网络请求", text: "“一起来决斗”的手机号、短信验证码通过HTTPS发送至yugiohmatchapi.windoent.com。用户主动绑定集换社时，同一手机号和本次JHS验证码通过HTTPS发送至api.jihuanshe.com；两个服务不会互换token。")
                    information("安全存储", text: "两套token、账号ID和绑定手机号分别保存于本机Keychain，不写入日志或普通偏好设置。退出或解除绑定只删除对应服务的凭据；网络暂时失败时保留凭据。")
                    information("本机数据", text: "卡组、收藏与关注仍为本机数据。本 App 不访问通讯录，不保存密码，不包含广告或分析 SDK。")
                }
            }.padding(24)
        }.background(Design.canvas) }
        }.presentationDragIndicator(.visible).presentationCornerRadius(32)
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
                            Text("卡片数据与更新").foregroundStyle(Design.ink)
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
                .toolbar { ToolbarItem(placement: .topBarLeading) { CompactBackButton().accessibilityIdentifier("navigation.back") } }
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
                .padding(16).background(Design.field, in: RoundedRectangle(cornerRadius: 16))
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
            }.buttonStyle(.borderedProminent).disabled(loading || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    ContentUnavailableView("购物车是空的",systemImage:"cart",description:Text("可在卡片在售列表中添加商品。"))
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
                .toolbar {ToolbarItem(placement:.topBarLeading){CompactBackButton(hitSize:44,action:{dismiss()})}}
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
                    ContentUnavailableView("预购清单是空的",systemImage:"list.bullet.clipboard",description:Text("在卡片在售页点击右上角按钮，添加想购买的版本。"))
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
                    ToolbarItem(placement:.topBarLeading){Button{dismiss()}label:{Image(systemName:"xmark")}.accessibilityLabel("关闭").accessibilityIdentifier("jhs.preorders.back")}
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
