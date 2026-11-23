import Foundation

/// fal.ai: prepaid credit balance from the platform billing API.
struct FalProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "fal",
        name: "fal.ai",
        subtitle: "Prepaid credit balance",
        symbol: "sparkles.rectangle.stack",
        tintHex: "7C3AED",
        credentialTitle: "API key",
        credentialHint: "key_id:key_secret",
        category: .balance,
        docsURL: URL(string: "https://fal.ai/dashboard/keys"),
        caveat: "Use a key with billing read access (the Billing, Read-only or "
              + "Full preset).")

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.fal.ai/v1/account/billing")!,
            headers: ["Authorization": "Key \(key)"],
            query: [URLQueryItem(name: "expand", value: "credits")])
        guard let object = JSON.object(data),
              let balance = JSON.number(object, "credits.current_balance")
        else { throw ProviderError.decoding }
        let currency = JSON.string(object, "credits.currency")?.uppercased() ?? "USD"
        return ProviderReading(
            label: JSON.string(object, "username"),
            metrics: [UsageMetric(
                id: "balance", title: "Credit balance", remaining: balance,
                unit: .usd, currencyCode: currency, isHeadline: true)])
    }
}
