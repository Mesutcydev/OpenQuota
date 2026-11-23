import Foundation

/// OpenCode Go is a flat-rate subscription with three nested usage windows —
/// a 5-hour rolling window worth 20% of the month, a weekly window worth 50%,
/// and the month itself. The API reports each as a percentage consumed with a
/// reset time, so there is no dollar figure to show.
///
/// Note: `/zen/go/v1/usage` is not part of OpenCode's published API reference,
/// so decoding is deliberately forgiving — every field is optional and a
/// missing window is skipped rather than treated as an error.
struct OpenCodeProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "opencode",
        name: "OpenCode Go",
        subtitle: "Subscription windows: 5-hour, weekly, monthly",
        symbol: "chevron.left.forwardslash.chevron.right",
        tintHex: "64748B",
        tintHexDark: "94A3B8",
        credentialTitle: "API key",
        credentialHint: "OpenCode Zen workspace key",
        keyPrefix: nil,
        category: .plan,
        docsURL: URL(string: "https://opencode.ai/auth"),
        caveat: "Shows Go subscription windows. OpenCode Zen's credit balance is "
              + "not exposed to API keys, so prepaid credit cannot be shown.")

    private struct Report: Decodable {
        struct Window: Decodable {
            let status: String?
            let percent: Double?
            let resetsAt: String?
        }
        let usage: [String: Window]?
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let url = URL(string: "https://opencode.ai/zen/go/v1/usage")!
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let report = try? decoder.decode(Report.self, from: data),
              let windows = report.usage, !windows.isEmpty
        else { throw ProviderError.decoding }

        // Ordered deliberately: the 5-hour window is the one that actually
        // interrupts you, so it leads.
        let ordered: [(key: String, title: String, caption: String)] = [
            ("rolling", "5-hour window", "20% of the monthly allowance"),
            ("weekly", "This week", "50% of the monthly allowance"),
            ("monthly", "This month", "full monthly allowance"),
        ]

        var metrics: [UsageMetric] = []
        var notes: [String] = []

        for (index, window) in ordered.enumerated() {
            guard let value = windows[window.key], let percent = value.percent else { continue }
            metrics.append(UsageMetric(
                id: window.key,
                title: window.title,
                used: percent,
                limit: 100,
                remaining: max(100 - percent, 0),
                unit: .percent,
                resetsAt: value.resetsAt.flatMap(AnthropicProvider.parse),
                caption: window.caption,
                isHeadline: index == 0))

            if let status = value.status, status.lowercased() != "ok" {
                notes.append("\(window.title) status: \(status).")
            }
        }

        guard !metrics.isEmpty else { throw ProviderError.decoding }
        // If the rolling window was absent, promote whatever came first.
        if !metrics.contains(where: \.isHeadline) { metrics[0].isHeadline = true }

        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
