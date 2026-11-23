import Foundation

/// OpenAI's cost and usage endpoints live under the organization admin API
/// and need an admin key (`sk-admin-…`), not a project key.
struct OpenAIProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "openai",
        name: "OpenAI",
        subtitle: "Organization spend and token usage",
        symbol: "circle.hexagongrid",
        tintHex: "10A37F",
        credentialTitle: "Admin API key",
        credentialHint: "sk-admin-…",
        keyPrefix: "sk-admin",
        category: .spend,
        docsURL: URL(string: "https://platform.openai.com/settings/organization/admin-keys"),
        caveat: "Needs an organization admin key. Project keys are rejected by "
              + "the cost endpoint. ChatGPT Plus/Pro quotas are not part of this API.")

    private struct CostPage: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                struct Amount: Decodable {
                    let value: Double?
                    let currency: String?
                }
                let amount: Amount?
            }
            let startTime: Double?
            let results: [Result]
        }
        let data: [Bucket]
    }

    /// The spend figures one cost page decodes to. Unlike Anthropic, values
    /// arrive as whole dollars already — no scaling here, and the tests pin
    /// that exact distinction.
    struct CostSummary: Equatable {
        var monthTotal: Double
        var todayTotal: Double
        var weekTotal: Double
        var currency: String
    }

    /// Pure decode + aggregate: no network, no clock.
    static func summarize(
        costData: Data,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> CostSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let page = try? decoder.decode(CostPage.self, from: costData) else {
            throw ProviderError.decoding
        }

        var monthTotal = 0.0
        var todayTotal = 0.0
        var weekTotal = 0.0
        var currency = "USD"
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart

        for bucket in page.data {
            // Unlike Anthropic, these amounts are already in whole dollars.
            let bucketTotal = bucket.results.compactMap { $0.amount?.value }.reduce(0, +)
            if let code = bucket.results.first?.amount?.currency { currency = code.uppercased() }
            monthTotal += bucketTotal

            guard let start = bucket.startTime.map({ Date(timeIntervalSince1970: $0) })
            else { continue }
            if start >= dayStart { todayTotal += bucketTotal }
            if start >= weekStart { weekTotal += bucketTotal }
        }

        return CostSummary(
            monthTotal: monthTotal, todayTotal: todayTotal,
            weekTotal: weekTotal, currency: currency)
    }

    private struct UsagePage: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                let inputTokens: Double?
                let outputTokens: Double?
            }
            let results: [Result]
        }
        let data: [Bucket]
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let headers = ["Authorization": "Bearer \(key)"]
        var calendar = Calendar(identifier: .gregorian)
        // Cost and usage reports bucket on UTC midnight; local-day windows
        // would read "Today" as $0 west of UTC.
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dayStart = calendar.startOfDay(for: now)

        let (data, _) = try await HTTP.get(
            URL(string: "https://api.openai.com/v1/organization/costs")!,
            headers: headers,
            query: [
                URLQueryItem(name: "start_time", value: String(Int(monthStart.timeIntervalSince1970))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31"),
            ])

        let summary = try Self.summarize(costData: data, now: now, calendar: calendar)

        var metrics = [
            UsageMetric(
                id: "month-cost", title: "Spent this month", used: summary.monthTotal,
                unit: .usd, currencyCode: summary.currency,
                caption: "since \(AnthropicProvider.monthLabel(monthStart))", isHeadline: true),
            UsageMetric(
                id: "today-cost", title: "Today", used: summary.todayTotal,
                unit: .usd, currencyCode: summary.currency),
            UsageMetric(
                id: "week-cost", title: "Last 7 days", used: summary.weekTotal,
                unit: .usd, currencyCode: summary.currency),
        ]

        if let tokens = try? await tokensToday(headers: headers, since: dayStart) {
            metrics.append(UsageMetric(
                id: "today-tokens", title: "Tokens today", used: tokens,
                unit: .tokens, caption: "input + output"))
        }

        return ProviderReading(label: nil, metrics: metrics)
    }

    private func tokensToday(headers: [String: String], since dayStart: Date) async throws -> Double {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.openai.com/v1/organization/usage/completions")!,
            headers: headers,
            query: [
                URLQueryItem(name: "start_time", value: String(Int(dayStart.timeIntervalSince1970))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(UsagePage.self, from: data)
        return page.data.flatMap(\.results).reduce(0) {
            $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0)
        }
    }
}
