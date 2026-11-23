import Foundation

/// AI/ML API: USD balance from the v2 billing endpoint.
struct AIMLProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "aimlapi",
        name: "AI/ML API",
        subtitle: "Prepaid balance remaining",
        symbol: "square.grid.3x3.fill",
        tintHex: "0E7CF2",
        category: .balance,
        docsURL: URL(string: "https://aimlapi.com/app/keys"))

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.aimlapi.com/v2/billing")!,
            headers: ["Authorization": "Bearer \(key)"])
        let object = JSON.object(data)
        guard let balance = JSON.number(object, "current_balance")
                ?? JSON.number(object, "data.current_balance")
        else { throw ProviderError.decoding }
        let currency = (JSON.string(object, "currency") ?? "USD").uppercased()
        return ProviderReading(label: nil, metrics: [UsageMetric(
            id: "balance", title: "Balance", remaining: balance, unit: .usd,
            currencyCode: currency, isHeadline: true)])
    }
}
