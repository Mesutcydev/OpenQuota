import Foundation

/// ChatGPT Plus / Pro / Business limits for Codex — the 5-hour and weekly
/// windows — read from chatgpt.com with the user's own web session.
///
/// Not an official API. The bearer token comes from chatgpt.com's session
/// endpoint and the limits from the endpoint Codex itself uses.
struct ChatGPTSubscriptionProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "chatgpt-plan",
        name: "ChatGPT / Codex",
        subtitle: "Plus / Pro plan: Codex 5-hour and weekly limits",
        symbol: "bubble.left.and.text.bubble.right",
        tintHex: "10A37F",
        credentialTitle: "chatgpt.com session",
        credentialHint: "Sign in to connect",
        category: .plan,
        docsURL: URL(string: "https://chatgpt.com/codex/settings/usage"),
        caveat: "Signs in to chatgpt.com inside the app and keeps only the session cookies, "
            + "in the Keychain. These limits come from chatgpt.com, not a public API, so "
            + "they can stop working if OpenAI changes it. For API spend, connect the "
            + "OpenAI provider with an admin key instead.",
        webSignIn: .chatgpt)

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (sessionData, sessionResponse) = try await WebSession.get(
            URL(string: "https://chatgpt.com/api/auth/session")!, cookie: key)
        guard sessionResponse.statusCode == 200 else {
            throw WebSession.failure(sessionResponse, data: sessionData, service: "ChatGPT")
        }
        guard let session = JSON.object(sessionData),
              let token = session["accessToken"] as? String, !token.isEmpty else {
            // An expired NextAuth session answers 200 with an empty object.
            throw ProviderError.message("Your ChatGPT session has expired. Sign in again.")
        }

        var headers = ["Authorization": "Bearer \(token)"]
        if let account = JSON.string(session, "account.id") {
            headers["ChatGPT-Account-Id"] = account
        }
        let (data, response) = try await WebSession.get(
            URL(string: "https://chatgpt.com/backend-api/wham/usage")!, cookie: key, headers: headers)
        guard response.statusCode == 200 else {
            throw WebSession.failure(response, data: data, service: "ChatGPT")
        }
        return try Self.reading(from: data)
    }

    static func reading(from data: Data) throws -> ProviderReading {
        guard let object = JSON.object(data) else { throw ProviderError.decoding }
        var metrics: [UsageMetric] = []

        for (key, fallbackID) in [("primary_window", "primary"), ("secondary_window", "secondary")] {
            guard let window = JSON.value(object, "rate_limit.\(key)") as? [String: Any],
                  let used = JSON.number(window["used_percent"]) else { continue }
            let seconds = JSON.number(window["limit_window_seconds"])
            metrics.append(UsageMetric(
                id: seconds.map { "window-\(Int($0))" } ?? fallbackID,
                title: windowTitle(seconds),
                used: used, limit: 100, remaining: max(100 - used, 0),
                unit: .percent,
                resetsAt: JSON.date(window["reset_at"]),
                caption: "Codex"))
        }

        if let credits = object["credits"] as? [String: Any],
           (credits["has_credits"] as? Bool) == true,
           (credits["unlimited"] as? Bool) != true,
           let balance = JSON.number(credits["balance"]) {
            metrics.append(UsageMetric(
                id: "credits", title: "Codex credits", remaining: balance,
                unit: .credits, caption: "beyond plan limits"))
        }

        guard metrics.contains(where: { $0.fraction != nil }) else {
            throw ProviderError.message("chatgpt.com returned no Codex limits for this plan.")
        }
        ClaudeSubscriptionProvider.markTightest(&metrics)
        let plan = (object["plan_type"] as? String).map(planName)
        return ProviderReading(label: plan, metrics: metrics)
    }

    static func windowTitle(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "Usage window" }
        if seconds == 604_800 { return "Weekly limit" }
        if seconds < 86_400 { return "\(Int((seconds / 3600).rounded()))-hour window" }
        return "\(Int((seconds / 86_400).rounded()))-day window"
    }

    static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "plus": return "ChatGPT Plus"
        case "pro": return "ChatGPT Pro"
        case "team", "business": return "ChatGPT Business"
        case "enterprise": return "ChatGPT Enterprise"
        case "edu", "education": return "ChatGPT Edu"
        case "free": return "ChatGPT Free"
        case "go": return "ChatGPT Go"
        default: return "ChatGPT " + raw.capitalized
        }
    }
}
