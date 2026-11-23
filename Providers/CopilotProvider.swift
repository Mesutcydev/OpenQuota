import Foundation

/// GitHub Copilot premium requests, from GitHub's documented billing usage
/// API (`/users/{login}/settings/billing/premium_request/usage`).
///
/// The API reports what was used and what was billed, not the plan's
/// allowance, so the allowance comes from the plan picked at connect time.
/// Only covers a Copilot plan the user pays for personally — usage under an
/// organization or enterprise seat is reported to that org, not here.
struct CopilotProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "copilot",
        name: "GitHub Copilot",
        subtitle: "Premium requests this month",
        symbol: "chevron.left.forwardslash.chevron.right",
        tintHex: "24292F",
        tintHexDark: "C9D1D9",
        credentialTitle: "Personal access token (classic)",
        credentialHint: "ghp_…",
        keyPrefix: "ghp_",
        extraField: ExtraFieldSpec(
            label: "Plan",
            placeholder: "Copilot Pro",
            options: [
                .init(title: "Copilot Free", value: "50", caption: "50 premium requests"),
                .init(title: "Copilot Pro", value: "300", caption: "300 premium requests"),
                .init(title: "Copilot Pro+", value: "1500", caption: "1,500 premium requests"),
                .init(title: "No allowance", value: "0", caption: "show usage only"),
            ]),
        category: .plan,
        docsURL: URL(string: "https://github.com/settings/tokens"),
        caveat: "GitHub's billing API accepts classic tokens only, not fine-grained ones. "
            + "It covers a Copilot plan you pay for yourself; seats from an organization "
            + "are reported to that organization.")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let headers = [
            "Authorization": "Bearer \(key)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        let (userData, _) = try await HTTP.get(
            URL(string: "https://api.github.com/user")!, headers: headers)
        guard let login = JSON.string(JSON.object(userData), "login"),
              let escaped = login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/users/\(escaped)/settings/billing/premium_request/usage")
        else { throw ProviderError.decoding }

        let now = Date()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month], from: now)
        let (data, _) = try await HTTP.get(url, headers: headers, query: [
            URLQueryItem(name: "year", value: String(parts.year ?? 2026)),
            URLQueryItem(name: "month", value: String(parts.month ?? 1)),
        ])
        var reading = try Self.reading(
            from: data, allowance: Double(extra ?? "300"), now: now, calendar: utc)
        reading.label = login
        return reading
    }

    /// Pure decode step, separated for tests.
    static func reading(from data: Data, allowance: Double?, now: Date,
                        calendar: Calendar) throws -> ProviderReading {
        guard let object = JSON.object(data),
              let items = object["usageItems"] as? [[String: Any]] else {
            throw ProviderError.decoding
        }
        var used = 0.0, billed = 0.0
        var byModel: [String: Double] = [:]
        for item in items {
            let quantity = JSON.number(item["grossQuantity"]) ?? 0
            used += quantity
            billed += JSON.number(item["netAmount"]) ?? 0
            if let model = item["model"] as? String, !model.isEmpty {
                byModel[model, default: 0] += quantity
            }
        }

        // Allowances reset at 00:00 UTC on the 1st.
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        let reset = monthStart.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        let limit = (allowance ?? 0) > 0 ? allowance : nil

        var metrics = [UsageMetric(
            id: "premium", title: "Premium requests",
            used: used, limit: limit,
            remaining: limit.map { max($0 - used, 0) },
            unit: .requests, resetsAt: reset,
            caption: "this month", isHeadline: true)]
        if billed > 0 {
            metrics.append(UsageMetric(
                id: "overage", title: "Billed overage", used: billed,
                unit: .usd, caption: "beyond the included allowance"))
        }
        for (model, quantity) in byModel.sorted(by: { $0.value > $1.value }).prefix(4) {
            metrics.append(UsageMetric(
                id: "model-\(model)", title: model, used: quantity, unit: .requests))
        }
        return ProviderReading(label: nil, metrics: metrics)
    }
}
