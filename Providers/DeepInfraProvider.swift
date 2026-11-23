import Foundation

/// DeepInfra splits its accounting across two endpoints that do not agree on
/// units, which is the main thing this adapter has to get right:
///
///  * `/payment/usage` reports `total_cost` as an **integer number of cents**.
///  * `/payment/key-limits` reports `limit` and `spend` as **USD** numbers.
///
/// Monthly spend is the headline; per-key spending limits are reported when
/// the account has them set. The key-limits call is best-effort — it needs
/// account-level access, so a key that can read usage but not limits still
/// produces a useful reading.
struct DeepInfraProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "deepinfra",
        name: "DeepInfra",
        subtitle: "Monthly spend and per-key limits",
        symbol: "infinity",
        tintHex: "1F6FEB",
        credentialTitle: "API token",
        credentialHint: "Your DeepInfra API token",
        keyPrefix: nil,
        category: .spend,
        docsURL: URL(string: "https://deepinfra.com/dash/api_keys"),
        caveat: "Spend is read from the billing API and needs a token with "
              + "account access. Per-key limits only appear when they are set.")

    private struct UsageOut: Decodable {
        struct Month: Decodable {
            let period: String
            /// Cents, not dollars.
            let totalCost: Double?
            let invoiceID: String?

            enum CodingKeys: String, CodingKey {
                case period
                case totalCost = "total_cost"
                case invoiceID = "invoice_id"
            }
        }

        let months: [Month]
        let initialMonth: String?

        enum CodingKeys: String, CodingKey {
            case months
            case initialMonth = "initial_month"
        }
    }

    /// One month's spend, in cents as the API reports it.
    struct MonthSpend: Equatable {
        var period: String
        var cents: Double
    }

    struct KeyLimit: Decodable {
        let tokenID: String?
        let name: String
        /// USD, may be absent when no limit is configured.
        let limit: Double?
        /// USD spent this month; null when not yet computed.
        let spend: Double?

        enum CodingKeys: String, CodingKey {
            case tokenID = "token_id"
            case name
            case limit
            case spend
        }
    }

    struct UsageSummary: Equatable {
        /// The newest month in the report.
        var current: MonthSpend
        /// Older months, newest-last order preserved.
        var history: [MonthSpend]
    }

    /// Pure decode of the usage report; the cents→dollars division stays in
    /// `fetch`, but this pins which field is cents and which month is current.
    static func parseUsage(_ data: Data) -> UsageSummary? {
        let decoder = JSONDecoder()
        guard let usage = try? decoder.decode(UsageOut.self, from: data),
              let current = usage.months.last
        else { return nil }
        return UsageSummary(
            current: MonthSpend(period: current.period, cents: current.totalCost ?? 0),
            history: usage.months.dropLast().compactMap {
                guard let cents = $0.totalCost else { return nil }
                return MonthSpend(period: $0.period, cents: cents)
            })
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let headers = ["Authorization": "Bearer \(key)"]

        // `current` in DeepInfra's period syntax means "this month".
        var components = URLComponents(
            string: "https://api.deepinfra.com/payment/usage")!
        components.queryItems = [URLQueryItem(name: "from", value: "current")]

        let (data, _): (Data, HTTPURLResponse)
        do {
            (data, _) = try await HTTP.get(components.url!, headers: headers)
        } catch ProviderError.unauthorized {
            // The billing API rejects inference-only tokens here, so a bare
            // "key rejected" would send the user chasing the wrong problem.
            throw ProviderError.message(
                "DeepInfra rejected this token for billing access. The token is "
                + "probably valid for inference only — create or use a token "
                + "with account access.")
        }
        guard let summary = Self.parseUsage(data) else {
            throw ProviderError.decoding
        }
        let period = summary.current.period

        var metrics: [UsageMetric] = []
        metrics.append(UsageMetric(
            id: "spend",
            title: "Spend",
            used: summary.current.cents / 100,
            unit: .usd,
            caption: "billing month \(period)",
            isHeadline: true))

        // Prior months give useful context without a second round trip.
        for month in summary.history.suffix(2) {
            metrics.append(UsageMetric(
                id: "spend-\(month.period)",
                title: "Spend \(month.period)",
                used: month.cents / 100,
                unit: .usd))
        }

        var notes: [String] = []

        // Best effort: not every token can read account-level limits.
        if let limits = try? await fetchKeyLimits(key: key),
           !limits.isEmpty {
            // The endpoint lists every key on the account and does not say
            // which one is this key, so surface the closest to its cap.
            if let binding = limits
                .filter({ ($0.limit ?? 0) > 0 })
                .max(by: { ($0.spend ?? 0) / ($0.limit ?? 1) < ($1.spend ?? 0) / ($1.limit ?? 1) }) {
                let spent = binding.spend ?? 0
                metrics.append(UsageMetric(
                    id: "key-limit",
                    title: "Most-used key limit",
                    used: spent,
                    limit: binding.limit,
                    unit: .usd,
                    caption: "key “\(binding.name)”"))
            }
            let capped = limits.filter { ($0.limit ?? 0) > 0 }.count
            if capped == 0 {
                notes.append("No per-key spending limits are set.")
            } else if capped < limits.count {
                notes.append("\(capped) of \(limits.count) API keys have a limit set.")
            }
        }

        return ProviderReading(label: period, metrics: metrics, notes: notes)
    }

    private func fetchKeyLimits(key: String) async throws -> [KeyLimit] {
        let url = URL(string: "https://api.deepinfra.com/payment/key-limits")!
        let (data, _) = try await HTTP.get(url, headers: ["Authorization": "Bearer \(key)"])
        return (try? JSONDecoder().decode([KeyLimit].self, from: data)) ?? []
    }
}
