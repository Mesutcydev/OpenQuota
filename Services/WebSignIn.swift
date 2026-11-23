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

    var loginURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/login")!
        case .chatgpt: return URL(string: "https://chatgpt.com/auth/login")!
        }
    }

    var host: String {
        switch self {
        case .claude: return "claude.ai"
        case .chatgpt: return "chatgpt.com"
        }
    }

    var serviceName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
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

// MARK: - Sign-in sheet

/// The provider's own login page in a private, throwaway web view. Nothing
/// typed here is read by the app; it waits for the session cookie and then
/// closes.
struct WebSignInView: View {
    let kind: WebSignInKind
    var onCredential: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            SignInWebView(kind: kind, isLoading: $isLoading) { credential in
                onCredential(credential)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                if isLoading { ProgressView().padding(.top, 12) }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Sign in with email if a Google or Apple button is refused — some "
                   + "identity providers block in-app browsers. Open Quota never sees your password.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .navigationTitle("Sign in to \(kind.serviceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

private struct SignInWebView: UIViewRepresentable {
    let kind: WebSignInKind
    @Binding var isLoading: Bool
    var onCredential: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Non-persistent: the session lives only in the Keychain afterwards,
        // not in a web data store that outlives this sheet.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebSession.userAgent
        webView.navigationDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        webView.load(URLRequest(url: kind.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let parent: SignInWebView
        private var delivered = false

        init(_ parent: SignInWebView) { self.parent = parent }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.delivered,
                      let credential = self.parent.kind.credential(from: cookies) else { return }
                self.delivered = true
                DispatchQueue.main.async { self.parent.onCredential(credential) }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            cookiesDidChange(in: webView.configuration.websiteDataStore.httpCookieStore)
            verifySession(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        /// The cookie observer alone missed completions when login moved to
        /// auth.openai.com (cookie names rotate, observer fires late), so the
        /// sheet stayed open after a successful sign-in. After every finished
        /// navigation, ask the page itself: fetch the session endpoint with
        /// the page's own cookies and finish when it reports a live session.
        /// Only chatgpt.com's own pages run the probe — the auth domain's
        /// fetch would be cross-origin and useless anyway.
        private func verifySession(in webView: WKWebView) {
            guard !delivered else { return }
            let kind = parent.kind
            switch kind {
            case .chatgpt:
                guard let host = webView.url?.host, host.hasSuffix("chatgpt.com"),
                      webView.url?.path != "/auth/login" else { return }
                let script = "fetch('/api/auth/session',{credentials:'include'})"
                    + ".then(r=>r.json()).then(s=>String(s.accessToken||''))"
                    + ".catch(()=>'')"
                webView.evaluateJavaScript(script) { [weak self] result, _ in
                    guard let self, !self.delivered,
                          let token = result as? String, !token.isEmpty else { return }
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                        cookies in
                        guard let credential = kind.credential(from: cookies) else { return }
                        self.delivered = true
                        DispatchQueue.main.async { self.parent.onCredential(credential) }
                    }
                }
            case .claude:
                break
            }
        }
    }
}
