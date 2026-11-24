import SwiftUI
import WebKit

/// Subscription plans (Claude Pro/Max, ChatGPT Plus/Pro) have no public API.
/// Their limits are readable only with the user's own web session, so these
/// providers are connected by signing in on the provider's real login page
/// inside the app and keeping the resulting session cookie in the Keychain —
/// never the password, which Open Quota never sees.
enum WebSignInKind: String, Hashable {
    case claude
    case chatgpt
    case alibaba

    var loginURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/login")!
        case .chatgpt: return URL(string: "https://chatgpt.com/auth/login")!
        case .alibaba: return URL(string: "https://account.alibabacloud.com/login/login.htm?oauth_callback=https%3A%2F%2Fmodelstudio.console.alibabacloud.com%2F&clearRedirectCookie=1")!
        }
    }

    var host: String {
        switch self {
        case .claude: return "claude.ai"
        case .chatgpt: return "chatgpt.com"
        case .alibaba: return "alibabacloud.com"
        }
    }

    var serviceName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .alibaba: return "Alibaba"
        }
    }

    /// The credential to store once signed in, or nil while the session
    /// cookie has not appeared yet.
    func credential(from cookies: [HTTPCookie]) -> String? {
        let mine = cookies.filter { $0.domain.hasSuffix(host) }
        switch self {
        case .claude:
            guard let session = mine.first(where: { $0.name == "sessionKey" }),
                  session.value.hasPrefix("sk-ant-") else { return nil }
            return session.value
        case .chatgpt:
            // NextAuth splits a large session token into .0, .1 … chunks;
            // keep every cookie for the host so the chunks and Cloudflare's
            // clearance travel together. Login now bounces through
            // auth.openai.com, so the cookie name may change without notice —
            // accept the NextAuth family and any plausible session cookie.
            let sessionNames = ["__Secure-next-auth.session-token",
                                "next-auth.session-token",
                                "__Secure-next-auth.session-token.csrf"]
            let hasSession = mine.contains {
                sessionNames.contains($0.name) || $0.name.hasPrefix("__Secure-next-auth.session-token")
                    || $0.name == "__Secure-session-token"
            }
            guard hasSession else { return nil }
            return mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        case .alibaba:
            // Keep every cookie for the host so the session travels together.
            guard !mine.isEmpty else { return nil }
            return mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }
}

/// Requests against a provider's web app rather than its API.
enum WebSession {
    /// A current mobile Safari user agent. The web apps serve their JSON to
    /// browsers; an unfamiliar agent is more likely to be challenged.
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// GET returning the body and response for any status, so each provider
    /// can tell an expired session from a Cloudflare challenge itself.
    static func get(_ url: URL, cookie: String?, headers: [String: String] = [:]) async throws
        -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderError.decoding }
            return (data, http)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ProviderError.transport(error.localizedDescription)
        }
    }

    static func isCloudflareChallenge(_ response: HTTPURLResponse, data: Data) -> Bool {
        if response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" { return true }
        guard response.statusCode == 403 || response.statusCode == 503 else { return false }
        return String(decoding: data.prefix(4096), as: UTF8.self).contains("Just a moment")
    }

    /// Maps a web-app failure to the message the card shows.
    static func failure(_ response: HTTPURLResponse, data: Data, service: String) -> ProviderError {
        if isCloudflareChallenge(response, data: data) {
            return .message("\(service) asked for a browser check. Sign in again to refresh the session.")
        }
        switch response.statusCode {
        case 401, 403:
            return .message("Your \(service) session has expired. Sign in again.")
        case 429:
            return .rateLimited
        default:
            return .server(response.statusCode, HTTP.apiMessage(from: data))
        }
    }

    /// Picks a rotated cookie value out of Set-Cookie, if the server sent one.
    static func renewedCookie(named name: String, in response: HTTPURLResponse) -> String? {
        guard let fields = response.allHeaderFields as? [String: String],
              let url = response.url else { return nil }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .first { $0.name == name }?.value
    }
}

// MARK: - Prewarming

/// The ChatGPT login page is a heavy client-rendered app; on a phone its first
/// paint can take tens of seconds, which looked like a dead white sheet. The
/// provider screen starts loading it the moment it appears, so the page is
/// usually ready by the time "Sign in" is tapped.
@MainActor
final class WebSignInPrewarmer {
    static let shared = WebSignInPrewarmer()

    /// A warmed page older than this is replaced — its CSRF state may be stale.
    private let maxAge: TimeInterval = 240
    private var warm: [WebSignInKind: (view: WKWebView, created: Date)] = [:]

    func prewarm(_ kind: WebSignInKind) {
        if let entry = warm[kind], Date().timeIntervalSince(entry.created) < maxAge { return }
        warm[kind] = (Self.makeWebView(for: kind), Date())
    }

    /// Hands over the warmed view (or a fresh one) and forgets it, so a page
    /// is never shared between two sign-ins.
    func take(_ kind: WebSignInKind) -> WKWebView {
        defer { warm[kind] = nil }
        if let entry = warm[kind], Date().timeIntervalSince(entry.created) < maxAge {
            return entry.view
        }
        return Self.makeWebView(for: kind)
    }

    static func makeWebView(for kind: WebSignInKind) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Non-persistent: the session lives only in the Keychain afterwards,
        // not in a web data store that outlives this sheet.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebSession.userAgent
        // Never flash white: the sheet's own canvas shows through until the
        // page paints.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: kind.loginURL))
        return webView
    }
}

// MARK: - Sign-in sheet

enum SignInPhase: Equatable {
    /// The first page has not painted yet.
    case loading
    /// Still nothing after a long wait — offer a retry, keep loading.
    case slow
    /// The page is on screen.
    case ready
    case failed(String)
}

/// The provider's own login page in a private, throwaway web view. Nothing
/// typed here is read by the app; it waits for the session cookie and then
/// closes.
struct WebSignInView: View {
    let kind: WebSignInKind
    var onCredential: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: SignInPhase = .loading
    @State private var progress: Double = 0
    @State private var isNavigating = true
    @State private var retryToken = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                SignInWebView(kind: kind, phase: $phase, progress: $progress,
                              isNavigating: $isNavigating, retryToken: retryToken) { credential in
                    onCredential(credential)
                    dismiss()
                }
                .opacity(phase == .ready ? 1 : 0)
                .ignoresSafeArea(edges: .bottom)

                if phase != .ready {
                    SignInLoadingPanel(kind: kind, phase: phase, progress: progress) {
                        phase = .loading
                        progress = 0
                        retryToken += 1
                    }
                    .transition(.opacity)
                }
            }
            .animation(.snappy, value: phase)
            .overlay(alignment: .top) {
                if phase == .ready && isNavigating {
                    SegmentedMeter(fraction: max(progress, 0.08), height: 3, segment: 6, gap: 2,
                                   showsSeverity: false)
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.top, Theme.Space.xs)
                        .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Sign in with email if a Google or Apple button is refused — some "
                   + "identity providers block in-app browsers. Open Quota never sees your password.")
                    .font(.mono(.caption2))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            .navigationTitle("Sign in to \(kind.serviceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }
}

/// What the sheet shows until the provider's page has actually painted:
/// a terminal-style status line with real load progress, then a retry.
private struct SignInLoadingPanel: View {
    let kind: WebSignInKind
    let phase: SignInPhase
    let progress: Double
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: 0) {
                Text("❯ ").foregroundStyle(Theme.brand)
                Text(kind.loginURL.host() ?? kind.host).foregroundStyle(Theme.ink)
                Text(kind.loginURL.path()).foregroundStyle(Theme.inkTertiary)
            }
            .font(.mono(.subheadline, weight: .semibold))
            .lineLimit(1)

            switch phase {
            case .failed(let message):
                status("ERR", message, color: Theme.critical)
                retryButton
            case .slow:
                SegmentedMeter(fraction: max(progress, 0.05), height: 8, showsSeverity: false)
                status("WAIT", "\(kind.host) is slow to respond. It can take up to a minute "
                       + "on a weak connection.", color: Theme.watch)
                retryButton
            default:
                SegmentedMeter(fraction: max(progress, 0.05), height: 8, showsSeverity: false)
                Text("loading the \(kind.serviceName.lowercased()) sign-in page…")
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .card()
        .padding(.horizontal, Theme.Spacing.page)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, Theme.Space.xl)
    }

    private func status(_ tag: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(tag)
                .font(.mono(.caption2, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.xxs)
                .background(color.opacity(Theme.Wash.dark), in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
            Text(text)
                .font(.mono(.caption))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var retryButton: some View {
        Button(action: retry) {
            Label("Try again", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

private struct SignInWebView: UIViewRepresentable {
    let kind: WebSignInKind
    @Binding var phase: SignInPhase
    @Binding var progress: Double
    @Binding var isNavigating: Bool
    var retryToken: Int
    var onCredential: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WebSignInPrewarmer.shared.take(kind)
        context.coordinator.attach(to: webView, retryToken: retryToken)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastRetryToken != retryToken else { return }
        context.coordinator.lastRetryToken = retryToken
        context.coordinator.reload(webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach(from: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: SignInWebView
        var lastRetryToken = 0
        private var delivered = false
        private var paintPoll: Timer?
        private var slowTimer: Timer?
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?

        init(_ parent: SignInWebView) { self.parent = parent }

        func attach(to webView: WKWebView, retryToken: Int) {
            lastRetryToken = retryToken
            webView.navigationDelegate = self
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                DispatchQueue.main.async { self?.parent.progress = value }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                let loading = view.isLoading
                DispatchQueue.main.async { self?.parent.isNavigating = loading }
            }
            startWaiting(webView)
            // A warmed page may already be signed in or painted.
            cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)
        }

        func detach(from webView: WKWebView) {
            stopTimers()
            progressObservation = nil
            loadingObservation = nil
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        }

        func reload(_ webView: WKWebView) {
            delivered = false
            webView.stopLoading()
            webView.load(URLRequest(url: parent.kind.loginURL))
            startWaiting(webView)
        }

        /// Polls until the page has drawn real content — `didFinish` alone
        /// arrives long after the login form is usable on this site, and a
        /// committed-but-unhydrated page is exactly the white screen.
        private func startWaiting(_ webView: WKWebView) {
            stopTimers()
            paintPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.checkPainted(webView)
            }
            slowTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                guard let self, self.parent.phase == .loading else { return }
                self.parent.phase = .slow
            }
        }

        private func stopTimers() {
            paintPoll?.invalidate()
            paintPoll = nil
            slowTimer?.invalidate()
            slowTimer = nil
        }

        private func checkPainted(_ webView: WKWebView) {
            guard webView.url?.scheme == "https" else { return }
            let script = "!!(document.body && document.body.innerText.trim().length > 0)"
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self, (result as? Bool) == true else { return }
                self.markReady()
            }
        }

        private func markReady() {
            stopTimers()
            if parent.phase != .ready { parent.phase = .ready }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.delivered,
                      let credential = self.parent.kind.credential(from: cookies) else { return }
                self.deliver(credential)
            }
        }

        private func deliver(_ credential: String) {
            guard !delivered else { return }
            delivered = true
            stopTimers()
            DispatchQueue.main.async { self.parent.onCredential(credential) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markReady()
            cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)
            verifySession(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            fail(error)
        }

        private func fail(_ error: Error) {
            let nsError = error as NSError
            // Cancelled loads are redirects or our own retry, not failures.
            guard nsError.code != NSURLErrorCancelled, !delivered else { return }
            // Once the page is up, a failed sub-navigation is the site's own
            // business — it shows its own error and the user can go back.
            guard parent.phase != .ready else { return }
            stopTimers()
            parent.phase = .failed("\(parent.kind.host) couldn't be reached. Check your connection, "
                                   + "then try again. (\(nsError.localizedDescription))")
        }

        /// The cookie observer alone misses completions when login bounces
        /// through auth.openai.com (cookie names rotate, the observer fires
        /// late). After every finished navigation on chatgpt.com, ask the page
        /// itself whether it has a live session. `callAsyncJavaScript` awaits
        /// the fetch — `evaluateJavaScript` would hand back an unresolved
        /// Promise and never finish the sign-in.
        private func verifySession(in webView: WKWebView) {
            guard !delivered, parent.kind == .chatgpt,
                  let host = webView.url?.host, host.hasSuffix("chatgpt.com"),
                  webView.url?.path != "/auth/login" else { return }
            let script = """
                try {
                    const response = await fetch('/api/auth/session', { credentials: 'include' });
                    const session = await response.json();
                    return String(session.accessToken || '');
                } catch (error) { return ''; }
                """
            let kind = parent.kind
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, !self.delivered,
                      case .success(let value) = result,
                      let token = value as? String, !token.isEmpty else { return }
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    guard let credential = kind.credential(from: cookies) else { return }
                    self.deliver(credential)
                }
            }
        }
    }
}
