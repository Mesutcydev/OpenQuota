import Foundation

/// Venice.ai: USD balance plus the daily DIEM (staked) allocation.
struct VeniceProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "venice",
        name: "Venice.ai",
        subtitle: "USD balance and daily DIEM allowance",
        symbol: "building.columns",
        tintHex: "D9452B",
        category: .balance,
        docsURL: URL(string: "https://venice.ai/settings/api"))

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.venice.ai/api/v1/billing/balance")!,
            headers: ["Authorization": "Bearer \(key)"])
        guard let object = JSON.object(data) else { throw ProviderError.decoding }
        return Self.reading(object)
    }

    static func reading(_ object: [String: Any]) -> ProviderReading {
        var metrics: [UsageMetric] = []
        let usd = JSON.number(object, "balances.usd") ?? 0
        let diem = JSON.number(object, "balances.diem")
        let allocation = JSON.number(object, "diemEpochAllocation")
        let diemIsPrimary = (allocation ?? 0) > 0 && usd <= 0

        if let diem, let allocation, allocation > 0 {
            metrics.append(UsageMetric(
                id: "diem", title: "DIEM used today", used: max(allocation - diem, 0),
                limit: allocation, remaining: diem, unit: .credits,
                caption: "daily staking allowance", isHeadline: diemIsPrimary))
        }
        metrics.insert(UsageMetric(
            id: "balance", title: "USD balance", remaining: usd, unit: .usd,
            isHeadline: !diemIsPrimary), at: 0)
        for (path, id, title) in [("balances.bundledCredits", "bundled", "Bundled credits"),
                                  ("balances.earnedCredits", "earned", "Earned credits")] {
            if let value = JSON.number(object, path), value > 0 {
                metrics.append(UsageMetric(id: id, title: title, remaining: value, unit: .credits))
            }
        }
        var notes: [String] = []
        if (object["canConsume"] as? Bool) == false {
            notes.append("This account cannot make API calls until it is topped up.")
        }
        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
