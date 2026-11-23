import Foundation

/// Novita reports an account balance plus its credit terms.
///
/// Every amount is a **decimal string in 1/10000 USD** — so "1000000" is
/// $100.00, not one million dollars. Divides before display.
struct NovitaProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "novita",
        name: "Novita AI",
        subtitle: "Credit balance and amount owed",
        symbol: "creditcard",
        tintHex: "7C3AED",
        credentialTitle: "API key",
        credentialHint: "sk_…",
        keyPrefix: nil,
        category: .balance,
        docsURL: URL(string: "https://novita.ai/settings/key-management"),
        caveat: "Balance comes from the billing API, so the key needs billing "
              + "access rather than inference-only permissions.")

    private struct Balance: Decodable {
        let availableBalance: String?
        let cashBalance: String?
        let creditLimit: String?
        let pendingCharges: String?
        let outstandingInvoices: String?
    }

    /// The balance endpoint's figures, converted to dollars. Every amount is
    /// a decimal string in **1/10000 USD** — "1000000" is $100.00, not one
    /// million dollars.
    struct BalanceFigures: Equatable {
        var available: Double?
        var cash: Double?
        var creditLimit: Double?
        var pendingCharges: Double?
        var outstanding: Double?
    }

    /// Novita's amounts are 1/10000 USD decimal strings.
    static func usd(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw) else { return nil }
        return value / 10_000
    }

    /// Pure decode + scale.
    static func parse(_ data: Data) -> BalanceFigures? {
        guard let payload = try? JSONDecoder().decode(Balance.self, from: data) else {
            return nil
        }
        return BalanceFigures(
            available: usd(payload.availableBalance),
            cash: usd(payload.cashBalance),
            creditLimit: usd(payload.creditLimit),
            pendingCharges: usd(payload.pendingCharges),
            outstanding: usd(payload.outstandingInvoices))
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let url = URL(string: "https://api.novita.ai/openapi/v1/billing/balance/detail")!
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])

        guard let figures = Self.parse(data) else {
            throw ProviderError.decoding
        }

        var metrics: [UsageMetric] = [UsageMetric(
            id: "available",
            title: "Balance",
            remaining: figures.available,
            unit: .usd,
            caption: "available to spend",
            isHeadline: true)]

        if let cash = figures.cash, cash > 0 {
            metrics.append(UsageMetric(
                id: "cash", title: "Top-up remaining", remaining: cash, unit: .usd))
        }

        // Owing money is the thing a user actually wants to be told about.
        if let owed = figures.outstanding, owed > 0 {
            metrics.append(UsageMetric(
                id: "outstanding",
                title: "Amount owed",
                used: owed,
                unit: .usd,
                caption: "outstanding invoices"))
        }

        var notes: [String] = []
        if let limit = figures.creditLimit, limit > 0 {
            notes.append("Credit limit: \(String(format: "$%.2f", limit)).")
        }
        if let pending = figures.pendingCharges, pending > 0 {
            notes.append("Pending charges: \(String(format: "$%.2f", pending)).")
        }
        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
