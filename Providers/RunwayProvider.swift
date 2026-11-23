import Foundation

/// Runway API: organization credit balance and monthly spend cap.
struct RunwayProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "runway",
        name: "Runway",
        subtitle: "API credit balance",
        symbol: "film.stack",
        tintHex: "3B3B45",
        tintHexDark: "9A9AA8",
        credentialTitle: "API key",
        credentialHint: "key_…",
        category: .balance,
        docsURL: URL(string: "https://dev.runwayml.com"))

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.dev.runwayml.com/v1/organization")!,
            headers: ["Authorization": "Bearer \(key)", "X-Runway-Version": "2024-11-06"])
        guard let object = JSON.object(data),
              let credits = JSON.number(object, "creditBalance")
        else { throw ProviderError.decoding }
        var metrics = [UsageMetric(
            id: "credits", title: "Credits left", remaining: credits, unit: .credits,
            caption: "≈ \(Format.currency(credits / 100))", isHeadline: true)]
        if let cap = JSON.number(object, "tier.maxMonthlyCreditSpend") {
            metrics.append(UsageMetric(
                id: "monthly-cap", title: "Monthly spend cap", limit: cap,
                remaining: cap, unit: .credits, caption: "credits per month for this tier"))
        }
        return ProviderReading(label: nil, metrics: metrics)
    }
}
