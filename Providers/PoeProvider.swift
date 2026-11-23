import Foundation

/// Poe: compute points left on the subscription plus add-ons.
struct PoeProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "poe",
        name: "Poe",
        subtitle: "Compute points remaining",
        symbol: "bubble.left.and.text.bubble.right",
        tintHex: "5D5CDE",
        category: .plan,
        docsURL: URL(string: "https://poe.com/api_key"))

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let (data, _) = try await HTTP.get(
            URL(string: "https://api.poe.com/usage/current_balance")!,
            headers: ["Authorization": "Bearer \(key)"])
        guard let points = JSON.number(JSON.object(data), "current_point_balance")
        else { throw ProviderError.decoding }
        return ProviderReading(label: nil, metrics: [UsageMetric(
            id: "points", title: "Points left", remaining: points, unit: .credits,
            caption: "plan + add-on points", isHeadline: true)])
    }
}
