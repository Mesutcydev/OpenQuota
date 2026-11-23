import Foundation

/// MiniMax Token / Coding Plan: prompts left in the current 5-hour interval
/// (and the weekly one where reported).
struct MiniMaxProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "minimax",
        name: "MiniMax Coding Plan",
        subtitle: "Plan prompts left this window",
        symbol: "waveform.path.ecg",
        tintHex: "E2416B",
        credentialTitle: "Plan API key",
        credentialHint: "Token Plan key (not pay-as-you-go)",
        extraField: ExtraFieldSpec(
            label: "Region",
            placeholder: "International",
            options: [
                .init(title: "International", value: "https://api.minimax.io",
                      caption: "minimax.io"),
                .init(title: "China", value: "https://api.minimaxi.com",
                      caption: "minimaxi.com"),
            ]),
        category: .plan,
        docsURL: URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key"),
        caveat: "Needs the Plan key from the Token Plan page; a pay-as-you-go key "
              + "has no plan quota to read.")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let base = (extra?.isEmpty == false ? extra! : "https://api.minimax.io")
        guard let url = URL(string: base + "/v1/token_plan/remains") else {
            throw ProviderError.message("Invalid region.")
        }
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])
        return try Self.reading(from: data)
    }

    static func reading(from data: Data) throws -> ProviderReading {
        guard let object = JSON.object(data) else { throw ProviderError.decoding }
        if let code = JSON.number(object, "base_resp.status_code"), code != 0 {
            throw ProviderError.message(
                JSON.string(object, "base_resp.status_msg") ?? "MiniMax returned error \(Int(code)).")
        }
        guard let models = object["model_remains"] as? [[String: Any]], !models.isEmpty else {
            throw ProviderError.decoding
        }
        // Prefer the text/coding model entry when several are listed.
        let model = models.first {
            ($0["model_name"] as? String)?.lowercased().hasPrefix("minimax-m") == true
        } ?? models[0]

        var metrics: [UsageMetric] = []
        // MiniMax names this "usage_count" but it carries the count still
        // *available* in the interval — the console shows it as remaining.
        if let total = JSON.number(model["current_interval_total_count"]), total > 0,
           let left = JSON.number(model["current_interval_usage_count"]) {
            metrics.append(UsageMetric(
                id: "interval", title: "5-hour window", used: max(total - left, 0),
                limit: total, remaining: left, unit: .requests,
                resetsAt: JSON.date(model["end_time"]), caption: "prompts",
                isHeadline: true))
        }
        if let total = JSON.number(model["current_weekly_total_count"]), total > 0,
           let left = JSON.number(model["current_weekly_usage_count"]) {
            metrics.append(UsageMetric(
                id: "weekly", title: "Weekly window", used: max(total - left, 0),
                limit: total, remaining: left, unit: .requests,
                resetsAt: JSON.date(model["weekly_end_time"]), caption: "prompts",
                isHeadline: metrics.isEmpty))
        }
        guard !metrics.isEmpty else { throw ProviderError.decoding }
        return ProviderReading(label: model["model_name"] as? String, metrics: metrics)
    }
}
