import SwiftUI
import WebKit

struct NewsDetailScreen: View {
    @Environment(NewsStore.self) private var news
    let id: String
    @State private var detail: NewsDetail?
    @State private var loading = false
    @State private var errorMessage: String?
    var body: some View {
        Group {
            if let detail {
                NewsRichText(document: NewsHTML.document(detail))
                    .accessibilityIdentifier("news.detail.body")
            } else {
                VStack(spacing: 20) {
                    if loading { ProgressView("正在加载动态").tint(Design.accent) }
                    if let errorMessage { NewsLoadError(message: errorMessage) { Task { await load() } }.padding(24) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Design.canvas)
            }
        }.navigationTitle("动态详情").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).glassNavigationBack().task(id: id) { await load() }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            let result = try await news.api.newsDetail(id: id)
            try Task.checkCancellation()
            detail = result
        } catch is CancellationError { }
        catch { errorMessage = error is URLError ? "暂时无法加载正文，请检查网络后重试。" : error.localizedDescription }
    }
}

enum NewsHTML {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func document(_ detail: NewsDetail) -> String {
        let metadata = [detail.author, detail.timeDescription, detail.views.map { "\($0) 次阅读" }].compactMap { $0 }.map(escape).joined(separator: " · ")
        let content = detail.html
            .replacingOccurrences(of: "(?is)<(script|iframe|object|embed)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)^\\s*(<p>\\s*(<br\\s*/?>|&nbsp;|\\s)*</p>\\s*)+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<img\\b", with: "<img referrerpolicy=\"no-referrer\"", options: .regularExpression)
        let fallback = detail.coverURL.map { "<img src=\"\(escape($0.absoluteString))\">" } ?? "<p>暂无正文。</p>"
        return """
        <!doctype html><html lang="zh-CN"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
        <meta name="referrer" content="no-referrer">
        <style>
        :root { color-scheme: light dark; --canvas: #f2f2f7; --ink: #20212a; --body: #34343f; --secondary: #85858f; }
        @media (prefers-color-scheme: dark) { :root { --canvas: #000000; --ink: #f2f2f7; --body: #e5e5ea; --secondary: #aeaeb2; } }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 26px 22px 36px; background: var(--canvas); font-family: -apple-system, sans-serif; overflow-wrap: anywhere; }
        .eyebrow { font-size: 10px; font-weight: 600; letter-spacing: 3px; color: #e74762; margin-bottom: 18px; }
        h1 { font-size: 27px; line-height: 1.42; letter-spacing: -0.7px; color: var(--ink); margin: 0 0 16px; }
        .meta { font-size: 11px; line-height: 1.8; color: var(--secondary); margin-bottom: 28px; }
        .content, .content * { color: var(--body) !important; background-color: transparent !important; font-family: -apple-system, sans-serif !important; line-height: 1.85 !important; }
        .content { font-size: 16px; }
        .content p { margin: 0 0 18px; }
        .content img, .content video { display: block !important; max-width: 100% !important; height: auto !important; margin: 18px auto !important; border-radius: 16px; }
        .content table { width: 100% !important; font-size: 13px; }
        .content a { color: #e74762 !important; }
        </style></head><body><div class="eyebrow">EXODIA / 动态</div>
        <h1>\(escape(detail.title))</h1><div class="meta">\(metadata)</div>
        <article class="content">\(content.isEmpty ? fallback : content)</article></body></html>
        """
    }
}

struct NewsRichText: UIViewRepresentable {
    let document: String
    @Environment(\.openURL) private var openURL
    func makeCoordinator() -> Coordinator { Coordinator(openURL: openURL) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(Design.canvas)
        view.scrollView.backgroundColor = UIColor(Design.canvas)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        view.backgroundColor=UIColor(Design.canvas);view.scrollView.backgroundColor=UIColor(Design.canvas)
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        view.loadHTMLString(document, baseURL: NewsImageURL.base)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let openURL: OpenURLAction
        var lastDocument: String?
        init(openURL: OpenURLAction) { self.openURL = openURL }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            if action.navigationType == .linkActivated {
                if url.scheme == "https" || url.scheme == "http" { openURL(url) }
                decisionHandler(.cancel)
            } else if url.scheme == "about" || url == NewsImageURL.base {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
