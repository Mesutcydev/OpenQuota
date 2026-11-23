import Foundation

/// Moonshot (Kimi) splits a prepaid balance into paid cash and free vouchers.
/// The region picked at connect time decides both the host and the currency:
/// the .ai endpoint bills in USD, the .cn one in CNY.
struct MoonshotProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "moonshot",
        name: "Moonshot (Kimi)",
        subtitle: "Prepaid balance, cash and vouchers",
        symbol: "moon.stars",
        tintHex: "5B54D6",
        credentialTitle: "API key",
        credentialHint: "sk-…",
        keyPrefix: "sk-",
        extraField: ExtraFieldSpec(
            label: "Region",
            placeholder: "International",
            options: [
                .init(title: "International", value: "https://api.moonshot.ai",
                      caption: "billed in USD"),
                .init(title: "China", value: "https://api.moonshot.cn",
                      caption: "billed in CNY"),
            ]),
        category: .balance,
        docsURL: URL(string: "https://platform.moonshot.ai/console/api-keys"))

    private struct Envelope: Decodable {
        struct Balance: Decodable {
            let availableBalance: Double?
            let voucherBalance: Double?
            let cashBalance: Double?
        }
        let data: Balance?
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let base = (extra?.isEmpty == false ? extra! : "https://api.moonshot.ai")
        let currency = base.hasSuffix(".cn") ? "CNY" : "USD"
        guard let url = URL(string: base + "/v1/users/me/balance") else {
            throw ProviderError.message("Invalid region.")
        }

        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let balance = try? decoder.decode(Envelope.self, from: data).data else {
            throw ProviderError.decoding
        }

        var metrics = [UsageMetric(
            id: "available",
            title: "Available",
            remaining: balance.availableBalance,
            unit: .usd,
            currencyCode: currency,
            caption: "cash + vouchers",
            isHeadline: true)]

        if let cash = balance.cashBalance {
            metrics.append(UsageMetric(
                id: "cash", title: "Cash", remaining: cash,
                unit: .usd, currencyCode: currency))
        }
        if let voucher = balance.voucherBalance, voucher > 0 {
            metrics.append(UsageMetric(
                id: "voucher", title: "Vouchers", remaining: voucher,
                unit: .usd, currencyCode: currency, caption: "free credit"))
        }

        var notes: [String] = []
        if let available = balance.availableBalance, available <= 0 {
            notes.append("Balance is exhausted — calls will be rejected.")
        }
        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
