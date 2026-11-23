import Foundation

/// Anthropic reports organization spend and token usage through the Admin
/// API, which needs an admin key rather than an ordinary inference key.
///
/// Note the unit trap: `cost_report` returns `amount` as a decimal string in
/// the *lowest* currency unit, so "123.45" USD is $1.23, not $123.45.
struct AnthropicProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "anthropic",
        name: "Anthropic",
        subtitle: "Organization spend and token usage",
        symbol: "sparkle",
        tintHex: "D97757",
        credentialTitle: "Admin API key",
        credentialHint: "sk-ant-admin…",
        keyPrefix: "sk-ant-admin",
        category: .spend,
        docsURL: URL(string: "https://console.anthropic.com/settings/admin-keys"),
        caveat: "Covers API organization usage. Claude Pro and Max subscription "
              + "quotas are not exposed by any Anthropic API, so they cannot be shown.")

    struct CostReport: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                let amount: String
                let currency: String
            }
            let startingAt: String
            let results: [Result]
        }
        let data: [Bucket]
    }

    /// The spend figures one cost report decodes to. All totals are dollars
    /// (converted from the API's smallest currency unit here, once).
    struct CostSummary: Equatable {
        var monthTotal: Double
        var todayTotal: Double
        var weekTotal: Double
        var currency: String
    }

    struct UsageReport: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                struct CacheCreation: Decodable {
                    let ephemeral1hInputTokens: Double?
                    let ephemeral5mInputTokens: Double?

                    // Decoded with .convertFromSnakeCase, which turns
                    // "ephemeral_1h_input_tokens" into "ephemeral1hInputTokens"
                    // before matching — explicit snake_case keys never match.
                }
                let uncachedInputTokens: Double?
                let cacheReadInputTokens: Double?
                let outputTokens: Double?
                let cacheCreation: CacheCreation?
            }
            let results: [Result]
        }
        let data: [Bucket]
    }

    /// Pure decode + aggregate: no network, no clock. `now` and `calendar`
    /// are parameters so the day/week bucketing is testable.
    static func summarize(
        costData: Data,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> CostSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let costs = try? decoder.decode(CostReport.self, from: costData) else {
            throw ProviderError.decoding
        }

        var monthTotal = 0.0
        var todayTotal = 0.0
        var weekTotal = 0.0
        var currency = "USD"
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart

        for bucket in costs.data {
            // Amounts are in cents; convert once, here, so nothing downstream
            // has to remember this.
            let bucketTotal = bucket.results
                .compactMap { Double($0.amount) }
                .reduce(0, +) / 100
            if let first = bucket.results.first { currency = first.currency }
            monthTotal += bucketTotal

            guard let start = Self.parse(bucket.startingAt) else { continue }
            if start >= dayStart { todayTotal += bucketTotal }
            if start >= weekStart { weekTotal += bucketTotal }
        }

        return CostSummary(
            monthTotal: monthTotal, todayTotal: todayTotal,
            weekTotal: weekTotal, currency: currency)
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let headers = [
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        ]
        var calendar = Calendar(identifier: .gregorian)
        // Cost and usage reports bucket on UTC midnight; local-day windows
        // would read "Today" as $0 west of UTC.
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dayStart = calendar.startOfDay(for: now)

        // The cost report caps at 31 daily buckets, which is exactly enough to
        // cover a full billing month.
        let (costData, _) = try await HTTP.get(
            URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!,
            headers: headers,
            query: [
                URLQueryItem(name: "starting_at", value: Self.rfc3339(monthStart)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31"),
            ])

        let summary = try Self.summarize(costData: costData, now: now, calendar: calendar)

        var metrics = [
            UsageMetric(
                id: "month-cost", title: "Spent this month", used: summary.monthTotal,
                unit: .usd, currencyCode: summary.currency,
                caption: "since \(Self.monthLabel(monthStart))", isHeadline: true),
            UsageMetric(
                id: "today-cost", title: "Today (UTC)", used: summary.todayTotal,
                unit: .usd, currencyCode: summary.currency),
            UsageMetric(
                id: "week-cost", title: "Last 7 days", used: summary.weekTotal,
                unit: .usd, currencyCode: summary.currency),
        ]

        // Token totals are a second call; a failure there should not sink the
        // spend figures we already have.
        if let tokens = try? await tokensToday(headers: headers, since: dayStart) {
            metrics.append(UsageMetric(
                id: "today-tokens", title: "Tokens today", used: tokens,
                unit: .tokens, caption: "input + cache + output"))
        }

        return ProviderReading(
            label: nil,
            metrics: metrics,
            notes: ["Subscription (Pro/Max) quotas are not exposed by the API — "
                  + "these figures are API organization usage."])
    }

    private func tokensToday(headers: [String: String], since dayStart: Date) async throws -> Double {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!,
            headers: headers,
            query: [
                URLQueryItem(name: "starting_at", value: Self.rfc3339(dayStart)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let report = try decoder.decode(UsageReport.self, from: data)
        return report.data.flatMap(\.results).reduce(0) { total, result in
            total
                + (result.uncachedInputTokens ?? 0)
                + (result.cacheReadInputTokens ?? 0)
                + (result.outputTokens ?? 0)
                + (result.cacheCreation?.ephemeral1hInputTokens ?? 0)
                + (result.cacheCreation?.ephemeral5mInputTokens ?? 0)
        }
    }

    static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func parse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    static func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
