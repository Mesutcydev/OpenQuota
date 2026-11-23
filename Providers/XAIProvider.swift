import Foundation

/// xAI exposes prepaid credit through its Management API, which is a separate
/// credential from an inference key and is scoped to a team.
///
/// Another cents trap: `total.val` is a string of USD **cents**.
struct XAIProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "xai",
        name: "xAI",
        subtitle: "Prepaid credit balance",
        symbol: "x.circle",
        tintHex: "7C8597",
        tintHexDark: "B4BCCB",
        credentialTitle: "Management API key",
        credentialHint: "management key, not an inference key",
        keyPrefix: nil,
        extraField: ExtraFieldSpec(
            label: "Team ID",
            placeholder: "from the xAI console URL"),
        category: .balance,
        docsURL: URL(string: "https://console.x.ai"),
        caveat: "Needs a Management API key and your team ID. An ordinary "
              + "inference key cannot read billing.")

    private struct Balance: Decodable {
        struct Amount: Decodable { let val: String? }
        let total: Amount?
    }

    /// `total.val` is a decimal string of **cents**; this returns dollars.
    /// Pure so the /100 conversion is pinned by a test.
    static func credit(from data: Data) -> Double? {
        let decoder = JSONDecoder()
        guard let balance = try? decoder.decode(Balance.self, from: data),
              let cents = balance.total?.val.flatMap(Double.init)
        else { return nil }
        // Prepaid credit is reported as a negative ledger value (money the
        // team is owed); show its magnitude.
        return abs(cents) / 100
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let team = (extra ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !team.isEmpty else {
            throw ProviderError.message("Enter your xAI team ID.")
        }
        guard let url = URL(
            string: "https://management-api.x.ai/v1/billing/teams/\(team)/prepaid/balance")
        else { throw ProviderError.message("Invalid team ID.") }

        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])
        guard let dollars = Self.credit(from: data) else {
            throw ProviderError.decoding
        }

        return ProviderReading(
            label: nil,
            metrics: [UsageMetric(
                id: "credit",
                title: "Prepaid credit",
                remaining: dollars,
                unit: .usd,
                caption: "team \(team)",
                isHeadline: true)])
    }
}
