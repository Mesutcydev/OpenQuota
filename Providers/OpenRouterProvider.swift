import Foundation

/// OpenRouter is the cleanest case: one unauthenticated-by-org call with an
/// ordinary inference key returns credits, rolling usage and the free-tier
/// request allowance.
struct OpenRouterProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "openrouter",
        name: "OpenRouter",
        subtitle: "Credit balance, rolling usage, free-tier requests",
        symbol: "arrow.triangle.branch",
        tintHex: "6366F1",
        credentialTitle: "API key",
        credentialHint: "sk-or-v1-…",
        keyPrefix: "sk-or",
        category: .balance,
        docsURL: URL(string: "https://openrouter.ai/settings/keys"))

    private struct Envelope: Decodable { let data: KeyData }

    private struct KeyData: Decodable {
        struct FreeRequests: Decodable {
            let used: Double?
            let limit: Double?
            let remaining: Double?
        }
        let label: String?
        let limit: Double?
        let limitRemaining: Double?
        let limitReset: String?
        let usage: Double?
        let usageDaily: Double?
        let usageWeekly: Double?
        let usageMonthly: Double?
        let isFreeTier: Bool?
        let freeModelDailyRequests: FreeRequests?
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let url = URL(string: "https://openrouter.ai/api/v1/key")!
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Envelope.self, from: data).data else {
            throw ProviderError.decoding
        }

        var metrics: [UsageMetric] = []

        if let limit = payload.limit, limit > 0 {
            metrics.append(UsageMetric(
                id: "credits",
                title: "Credits left",
                // `usage` is lifetime spend; against a resetting limit only
                // limit − remaining is the share consumed this period.
                used: payload.limitRemaining.map { max(limit - $0, 0) } ?? payload.usage,
                limit: limit,
                remaining: payload.limitRemaining,
                unit: .usd,
                resetsAt: payload.limitReset.flatMap(Self.parseReset),
                caption: "key credit limit",
                isHeadline: true))
        } else {
            // No cap on the key, so total spend is the only headline available.
            metrics.append(UsageMetric(
                id: "usage",
                title: "Spent on this key",
                used: payload.usage,
                unit: .usd,
                caption: "no key limit set",
                isHeadline: true))
        }

        let windows: [(String, String, Double?)] = [
            ("daily", "Today", payload.usageDaily),
            ("weekly", "This week", payload.usageWeekly),
            ("monthly", "This month", payload.usageMonthly),
        ]
        for (id, title, amount) in windows {
            guard let amount else { continue }
            metrics.append(UsageMetric(id: id, title: title, used: amount, unit: .usd))
        }

        if let free = payload.freeModelDailyRequests, let limit = free.limit, limit > 0 {
            metrics.append(UsageMetric(
                id: "free-requests",
                title: "Free model requests",
                used: free.used,
                limit: limit,
                remaining: free.remaining,
                unit: .requests,
                caption: "resets daily"))
        }

        var notes: [String] = []
        if payload.isFreeTier == true {
            notes.append("This key is on OpenRouter's free tier.")
        }

        return ProviderReading(label: payload.label, metrics: metrics, notes: notes)
    }

    /// `limit_reset` is documented only as a string, and in practice is either
    /// an ISO timestamp or a coarse window name like "daily".
    private static func parseReset(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }

        let calendar = Calendar.current
        switch raw.lowercased() {
        case "daily": return calendar.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime)
        case "weekly": return calendar.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0, weekday: 1),
            matchingPolicy: .nextTime)
        case "monthly": return calendar.nextDate(
            after: Date(), matching: DateComponents(day: 1, hour: 0, minute: 0),
            matchingPolicy: .nextTime)
        default: return nil
        }
    }
}
