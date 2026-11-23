import Foundation

/// DeepSeek exposes a prepaid balance, split into granted and topped-up
/// portions, on a plain inference key.
struct DeepSeekProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "deepseek",
        name: "DeepSeek",
        subtitle: "Prepaid balance remaining",
        symbol: "water.waves",
        tintHex: "4D6BFE",
        credentialTitle: "API key",
        credentialHint: "sk-…",
        keyPrefix: "sk-",
        category: .balance,
        docsURL: URL(string: "https://platform.deepseek.com/api_keys"))

    private struct Balance: Decodable {
        struct Info: Decodable {
            let currency: String
            let totalBalance: String
            let grantedBalance: String
            let toppedUpBalance: String
        }
        let isAvailable: Bool
        let balanceInfos: [Info]
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Balance.self, from: data)
        else { throw ProviderError.decoding }
        // Prefer a USD balance when several currencies are held.
        guard let info = payload.balanceInfos.first(where: { $0.currency == "USD" })
                ?? payload.balanceInfos.first
        else {
            return ProviderReading(label: nil, metrics: [UsageMetric(
                id: "balance", title: "Balance", remaining: 0, unit: .usd,
                caption: "no balance on this account", isHeadline: true)])
        }

        // Amounts come back as decimal strings, one entry per currency held.
        var metrics = [UsageMetric(
            id: "balance",
            title: "Balance",
            remaining: Double(info.totalBalance),
            unit: .usd,
            currencyCode: info.currency,
            caption: "granted + topped up",
            isHeadline: true)]

        if let granted = Double(info.grantedBalance), granted > 0 {
            metrics.append(UsageMetric(
                id: "granted", title: "Granted", remaining: granted,
                unit: .usd, currencyCode: info.currency))
        }
        if let toppedUp = Double(info.toppedUpBalance), toppedUp > 0 {
            metrics.append(UsageMetric(
                id: "topped-up", title: "Topped up", remaining: toppedUp,
                unit: .usd, currencyCode: info.currency))
        }

        var notes: [String] = []
        if !payload.isAvailable {
            notes.append("Balance is too low for API calls.")
        }
        if payload.balanceInfos.count > 1 {
            let others = payload.balanceInfos.filter { $0.currency != info.currency }.map(\.currency).joined(separator: ", ")
            notes.append("Additional balances held in \(others).")
        }
        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
