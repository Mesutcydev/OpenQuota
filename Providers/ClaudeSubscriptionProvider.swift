import Foundation

/// Claude Pro / Max / Team plan limits — the 5-hour session window and the
/// weekly windows — read from claude.ai with the user's own web session, the
/// same numbers claude.ai's Settings › Usage page shows.
///
/// Not an official API: Anthropic can change it at any time, and the card
/// then says so rather than showing wrong numbers.
struct ClaudeSubscriptionProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "claude-plan",
        name: "Claude",
        subtitle: "Pro / Max plan: 5-hour and weekly limits",
        symbol: "sparkle",
        tintHex: "D97757",
        credentialTitle: "claude.ai session",
        credentialHint: "Sign in to connect",
        category: .plan,
        docsURL: URL(string: "https://claude.ai/settings/usage"),
        caveat: "Signs in to claude.ai inside the app and keeps only the session cookie, in "
            + "the Keychain. These limits come from claude.ai itself, not a public API, so "
            + "they can stop working if claude.ai changes. For API spend, connect the "
            + "Anthropic provider with an admin key instead.",
        webSignIn: .claude)

    private static let base = "https://claude.ai/api"

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        var sessionKey = key
        let cookie = { "sessionKey=\(sessionKey)" }

        let (orgData, orgResponse) = try await WebSession.get(
            URL(string: Self.base + "/organizations")!, cookie: cookie())
        guard orgResponse.statusCode == 200 else {
            throw WebSession.failure(orgResponse, data: orgData, service: "Claude")
        }
        if let renewed = WebSession.renewedCookie(named: "sessionKey", in: orgResponse) {
            sessionKey = renewed
        }
        guard let org = Self.pickOrganization(orgData) else {
            throw ProviderError.message("No Claude organization found for this account.")
        }

        let (data, response) = try await WebSession.get(
            URL(string: Self.base + "/organizations/\(org.id)/usage")!, cookie: cookie())
        if response.statusCode != 200 {
            throw WebSession.failure(response, data: data, service: "Claude")
        }
        if let renewed = WebSession.renewedCookie(named: "sessionKey", in: response) {
            sessionKey = renewed
        }
        var reading = try Self.reading(from: data)
        reading.label = org.name
        reading.renewedCredential = sessionKey == key ? nil : sessionKey
        return reading
    }

    struct Organization: Equatable { var id: String; var name: String? }

    /// Mirrors claude.ai's own choice: the organization that can chat, not an
    /// API-only console organization.
    static func pickOrganization(_ data: Data) -> Organization? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let orgs: [(Organization, [String])] = list.compactMap { item in
            guard let id = item["uuid"] as? String else { return nil }
            return (Organization(id: id, name: item["name"] as? String),
                    item["capabilities"] as? [String] ?? [])
        }
        return (orgs.first { $0.1.contains("chat") }
            ?? orgs.first { $0.1 != ["api"] }
            ?? orgs.first)?.0
    }

    static func reading(from data: Data) throws -> ProviderReading {
        guard let object = JSON.object(data) else { throw ProviderError.decoding }

        var metrics: [UsageMetric] = []
        func window(_ key: String, id: String, title: String, caption: String) {
            guard let block = object[key] as? [String: Any],
                  let utilization = JSON.number(block["utilization"]) else { return }
            metrics.append(UsageMetric(
                id: id, title: title,
                used: utilization, limit: 100, remaining: max(100 - utilization, 0),
                unit: .percent,
                resetsAt: (block["resets_at"] as? String).flatMap(parseDate),
                caption: caption))
        }
        window("five_hour", id: "five-hour", title: "5-hour window", caption: "session limit")
        window("seven_day", id: "weekly", title: "Weekly limit", caption: "all models")
        window("seven_day_opus", id: "weekly-opus", title: "Weekly · Opus", caption: "model limit")
        window("seven_day_sonnet", id: "weekly-sonnet", title: "Weekly · Sonnet", caption: "model limit")

        // Newer accounts list model-scoped weekly limits here instead.
        for item in object["limits"] as? [[String: Any]] ?? [] {
            guard (item["kind"] as? String) == "weekly_scoped",
                  let percent = JSON.number(item["percent"]),
                  let name = JSON.string(item, "scope.model.display_name") else { continue }
            let id = "weekly-" + name.lowercased().replacingOccurrences(of: " ", with: "-")
            guard !metrics.contains(where: { $0.id == id }) else { continue }
            metrics.append(UsageMetric(
                id: id, title: "Weekly · \(name)",
                used: percent, limit: 100, remaining: max(100 - percent, 0),
                unit: .percent,
                resetsAt: (item["resets_at"] as? String).flatMap(parseDate),
                caption: "model limit"))
        }

        guard !metrics.isEmpty else {
            throw ProviderError.message("claude.ai returned no plan limits for this account.")
        }
        markTightest(&metrics)
        return ProviderReading(label: nil, metrics: metrics)
    }

    /// The card, widget and alerts lead with whichever window is closest to
    /// its cap — that is the one that will stop you.
    static func markTightest(_ metrics: inout [UsageMetric]) {
        guard let index = metrics.indices.max(by: {
            (metrics[$0].fraction ?? 0) < (metrics[$1].fraction ?? 0)
        }) else { return }
        for i in metrics.indices { metrics[i].isHeadline = (i == index) }
    }

    /// claude.ai sends microsecond precision ("…00.036205+00:00"), which
    /// ISO8601DateFormatter rejects; drop the fraction before parsing.
    static func parseDate(_ raw: String) -> Date? {
        var text = raw
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            text.removeSubrange(dot..<end)
        }
        return ISO8601DateFormatter().date(from: text)
    }
}
