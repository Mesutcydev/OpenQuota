import Foundation

/// Featherless: organization credit balance (admin keys only).
struct FeatherlessProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "featherless",
        name: "Featherless",
        subtitle: "Organization credit balance",
        symbol: "leaf",
        tintHex: "2E9E6B",
        credentialTitle: "Admin API key",
        credentialHint: "rc_…",
        category: .balance,
        docsURL: URL(string: "https://featherless.ai/account/api-keys"),
        caveat: "Needs a key from an organization admin. Updates every few minutes.")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.featherless.ai/credits/balance")!,
            headers: ["Authorization": "Bearer \(key)"])
        guard let object = JSON.object(data),
              let available = JSON.number(object, "available_usd")
        else { throw ProviderError.decoding }
        var metrics = [UsageMetric(
            id: "balance", title: "Available", remaining: available, unit: .usd,
            caption: "balance minus in-flight requests", isHeadline: true)]
        if let reserved = JSON.number(object, "reserved_usd"), reserved > 0 {
            metrics.append(UsageMetric(id: "reserved", title: "Reserved", used: reserved, unit: .usd))
        }
        return ProviderReading(label: nil, metrics: metrics)
    }
}
