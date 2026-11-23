import Foundation

/// Together AI reports organization-wide spend as cost-annotated line items
/// grouped into time windows, per billing month.
///
/// Two sharp edges worth knowing:
///  * The endpoint is beta and enabled per organization. Organizations
///    without access get a 404, which we translate into a plain sentence
///    rather than the generic "endpoint not found" the shared layer emits.
///  * Money and quantities arrive as decimal *strings*, not numbers.
struct TogetherProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "together",
        name: "Together AI",
        subtitle: "Organization spend this month",
        symbol: "square.stack.3d.up",
        tintHex: "0F6FFF",
        credentialTitle: "API key",
        credentialHint: "Your Together API key",
        keyPrefix: nil,
        category: .spend,
        docsURL: URL(string: "https://api.together.ai/settings/api-keys"),
        caveat: "Billing usage is organization-wide and in beta — it must be "
              + "enabled for your organization, and reads the whole org rather "
              + "than a single project.")

    private struct Report: Decodable {
        struct Window: Decodable {
            let lineItems: [LineItem]

            enum CodingKeys: String, CodingKey {
                case lineItems = "line_items"
            }
        }

        struct LineItem: Decodable {
            let productName: String
            let quantity: String?
            let cost: String?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case quantity
                case cost
            }
        }

        let billingPeriod: String?
        let currency: String?
        let data: [Window]

        enum CodingKeys: String, CodingKey {
            case billingPeriod = "billing_period"
            case currency
            case data
        }
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let url = URL(string: "https://api.together.ai/v1/billing/usage")!
        let month = Self.currentMonth()

        let (data, _): (Data, HTTPURLResponse)
        do {
            (data, _) = try await HTTP.get(
                url,
                headers: ["Authorization": "Bearer \(key)"],
                query: [URLQueryItem(name: "month", value: month),
                        URLQueryItem(name: "granularity", value: "day")])
        } catch ProviderError.notFound {
            // The documented signal for "billing usage not enabled for this org".
            throw ProviderError.message(
                "Together AI billing usage is not enabled for this organization. "
                + "It is a beta endpoint that must be switched on by Together "
                + "support — your key itself is fine.")
        } catch ProviderError.forbidden {
            // Observed in practice: a key without billing access fails the
            // beta entitlement check and comes back 403, not 404.
            throw ProviderError.message(
                "Together AI refused access to billing usage for this key. The "
                + "endpoint is in beta and must be enabled for your "
                + "organization — enable it or use an organization-level key.")
        }

        let decoder = JSONDecoder()
        guard let report = try? decoder.decode(Report.self, from: data) else {
            throw ProviderError.decoding
        }

        let currency = report.currency ?? "USD"

        // Roll every line item in the month into one total, and keep a
        // per-product breakdown so the biggest cost centres are visible.
        var total = 0.0
        var byProduct: [String: Double] = [:]
        var haveAnyCost = false

        for window in report.data {
            for item in window.lineItems {
                guard let raw = item.cost, let cost = Double(raw) else { continue }
                haveAnyCost = true
                total += cost
                byProduct[item.productName, default: 0] += cost
            }
        }

        var metrics: [UsageMetric] = []
        let periodCaption = report.billingPeriod.map { "billing month \($0)" } ?? "current billing month"

        metrics.append(UsageMetric(
            id: "spend",
            title: "Spend",
            used: haveAnyCost ? total : 0,
            unit: .usd,
            currencyCode: currency,
            caption: periodCaption,
            isHeadline: true))

        // Only the largest few products — this is a summary card, not an invoice.
        let top = byProduct
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
        for (index, entry) in top.enumerated() {
            metrics.append(UsageMetric(
                id: "product-\(index)",
                title: entry.key,
                used: entry.value,
                unit: .usd,
                currencyCode: currency,
                caption: "this month"))
        }

        var notes: [String] = []
        if !haveAnyCost {
            notes.append("No usage recorded for \(report.billingPeriod ?? month) yet.")
        }
        if byProduct.count > top.count {
            notes.append("Showing the top \(top.count) of \(byProduct.count) billed products.")
        }

        return ProviderReading(label: report.billingPeriod, metrics: metrics, notes: notes)
    }

    /// Together expects a `YYYY-MM` billing month in UTC.
    private static func currentMonth() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month], from: Date())
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
}
