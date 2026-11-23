import Foundation

/// SiliconFlow returns a prepaid balance split into topped-up credit and a
/// total that includes promotional grants. Amounts arrive as decimal strings.
struct SiliconFlowProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "siliconflow",
        name: "SiliconFlow",
        subtitle: "Prepaid balance and granted credit",
        symbol: "cpu",
        tintHex: "7C3AED",
        credentialTitle: "API key",
        credentialHint: "sk-…",
        keyPrefix: "sk-",
        extraField: ExtraFieldSpec(
            label: "Region",
            placeholder: "International",
            options: [
                .init(title: "International", value: "https://api.siliconflow.com", caption: nil),
                .init(title: "China", value: "https://api.siliconflow.cn", caption: nil),
            ]),
        category: .balance,
        docsURL: URL(string: "https://cloud.siliconflow.com/account/ak"))

    private struct Envelope: Decodable {
        struct User: Decodable {
            let name: String?
            let email: String?
            let balance: String?
            let chargeBalance: String?
            let totalBalance: String?
            let status: String?
        }
        let data: User?
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let base = (extra?.isEmpty == false ? extra! : "https://api.siliconflow.com")
        guard let url = URL(string: base + "/v1/user/info") else {
            throw ProviderError.message("Invalid region.")
        }

        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let user = try? decoder.decode(Envelope.self, from: data).data else {
            throw ProviderError.decoding
        }

        let currency = base.contains("siliconflow.cn") ? "CNY" : "USD"
        var metrics = [UsageMetric(
            id: "total",
            title: "Total balance",
            remaining: user.totalBalance.flatMap(Double.init),
            unit: .usd,
            currencyCode: currency,
            caption: "topped up + granted",
            isHeadline: true)]

        if let charge = user.chargeBalance.flatMap(Double.init), charge > 0 {
            metrics.append(UsageMetric(
                id: "charge", title: "Topped up", remaining: charge, unit: .usd,
                currencyCode: currency))
        }
        if let granted = user.balance.flatMap(Double.init), granted > 0 {
            metrics.append(UsageMetric(
                id: "granted", title: "Granted", remaining: granted,
                unit: .usd, currencyCode: currency, caption: "promotional credit"))
        }

        var notes: [String] = []
        if let status = user.status, status.lowercased() != "normal" {
            notes.append("Account status: \(status).")
        }

        let label = user.name ?? user.email
        return ProviderReading(label: label, metrics: metrics, notes: notes)
    }
}
