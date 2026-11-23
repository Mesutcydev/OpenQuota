import Foundation

/// Deepgram: project credit balances. Finds the first project when the user
/// leaves the project ID blank.
struct DeepgramProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "deepgram",
        name: "Deepgram",
        subtitle: "Project credit balance",
        symbol: "mic.fill",
        tintHex: "13EF93",
        tintHexDark: "13EF93",
        credentialTitle: "API key",
        credentialHint: "Key with project read access",
        extraField: ExtraFieldSpec(
            label: "Project ID",
            placeholder: "Optional — first project if blank"),
        category: .balance,
        docsURL: URL(string: "https://console.deepgram.com"))

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let headers = ["Authorization": "Token \(key)"]
        var project = (extra ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var projectName: String?
        if project.isEmpty {
            let (data, _) = try await HTTP.get(
                URL(string: "https://api.deepgram.com/v1/projects")!, headers: headers)
            guard let first = (JSON.object(data)?["projects"] as? [[String: Any]])?.first,
                  let id = first["project_id"] as? String
            else { throw ProviderError.message("No Deepgram project is visible to this key.") }
            project = id
            projectName = first["name"] as? String
        }
        guard let url = URL(string: "https://api.deepgram.com/v1/projects/\(project)/balances")
        else { throw ProviderError.message("Invalid project ID.") }
        let (data, _) = try await HTTP.get(url, headers: headers)
        guard let balances = JSON.object(data)?["balances"] as? [[String: Any]]
        else { throw ProviderError.decoding }

        var metrics: [UsageMetric] = []
        for (index, balance) in balances.enumerated() {
            guard let amount = JSON.number(balance["amount"]) else { continue }
            let units = (balance["units"] as? String)?.uppercased() ?? "USD"
            let isMoney = units.count == 3
            metrics.append(UsageMetric(
                id: index == 0 ? "balance" : "balance-\(index)",
                title: index == 0 ? "Credit balance" : "Balance \(index + 1)",
                remaining: amount,
                unit: isMoney ? .usd : .credits,
                currencyCode: isMoney ? units : nil,
                caption: isMoney ? nil : units.lowercased(),
                isHeadline: index == 0))
        }
        if metrics.isEmpty {
            metrics.append(UsageMetric(
                id: "balance", title: "Credit balance", remaining: 0, unit: .usd,
                caption: "no balance on this project", isHeadline: true))
        }
        return ProviderReading(label: projectName, metrics: metrics)
    }
}
