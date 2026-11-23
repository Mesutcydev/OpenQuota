import Foundation

/// LiteLLM proxy (and compatible gateways): spend against the virtual key's
/// budget, from the key's own `/key/info`.
struct LiteLLMProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "litellm",
        name: "LiteLLM proxy",
        subtitle: "Virtual key spend and budget",
        symbol: "point.3.connected.trianglepath.dotted",
        tintHex: "2563EB",
        credentialTitle: "Virtual key",
        credentialHint: "sk-…",
        extraField: ExtraFieldSpec(
            label: "Proxy URL",
            placeholder: "https://litellm.example.com",
            isURL: true),
        category: .spend,
        docsURL: URL(string: "https://docs.litellm.ai/docs/proxy/virtual_keys"))

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let root = (extra ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard root.hasPrefix("http"), let url = URL(string: root + "/key/info") else {
            throw ProviderError.message("Enter the proxy URL, e.g. https://litellm.example.com")
        }
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])
        guard let info = JSON.object(data)?["info"] as? [String: Any],
              let spend = JSON.number(info["spend"])
        else { throw ProviderError.decoding }
        let budget = JSON.number(info["max_budget"])
        let reset = (info["budget_reset_at"] as? String).flatMap(AnthropicProvider.parse)

        var metrics = [UsageMetric(
            id: "spend", title: "Spend", used: spend,
            limit: (budget ?? 0) > 0 ? budget : nil,
            remaining: budget.map { max($0 - spend, 0) },
            unit: .usd, resetsAt: reset,
            caption: budget == nil ? "no budget set" : (info["budget_duration"] as? String).map { "budget per \($0)" },
            isHeadline: true)]
        if let tpm = JSON.number(info["tpm_limit"]) {
            metrics.append(UsageMetric(id: "tpm", title: "Token limit / min", limit: tpm, unit: .tokens))
        }
        if let rpm = JSON.number(info["rpm_limit"]) {
            metrics.append(UsageMetric(id: "rpm", title: "Request limit / min", limit: rpm, unit: .requests))
        }
        var notes: [String] = []
        if let expires = (info["expires"] as? String).flatMap(AnthropicProvider.parse) {
            notes.append("Key expires \(expires.formatted(date: .abbreviated, time: .omitted)).")
        }
        return ProviderReading(label: info["key_alias"] as? String, metrics: metrics, notes: notes)
    }
}
