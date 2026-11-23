import Foundation

/// Mistral's Admin API reports organization spend and the monthly cap that
/// applies to it.
///
/// Three things differ from every other adapter here:
///  * Auth is the `x-api-key` header, not `Authorization: Bearer`.
///  * The base path is `/v1/admin`, and the key must be an *Admin* API key
///    created in the Backoffice — a normal inference key is rejected.
///  * Monthly spend is only meaningful next to the configured limit, so the
///    headline carries both and renders as a progress bar.
struct MistralProvider: UsageProvider {
    let descriptor = ProviderDescriptor(
        id: "mistral",
        name: "Mistral",
        subtitle: "Organization spend against monthly cap",
        symbol: "wind",
        tintHex: "FA500F",
        credentialTitle: "Admin API key",
        credentialHint: "Admin key from the Mistral Backoffice",
        keyPrefix: nil,
        category: .spend,
        docsURL: URL(string: "https://console.mistral.ai/"),
        caveat: "Requires an Admin API key created in the Backoffice — a "
              + "standard inference key will be rejected. Spend covers the "
              + "whole organization.")

    private struct Limits: Decodable {
        struct Context: Decodable {
            struct Completion: Decodable {
                let usage: Double?
                let totalUsage: Double?
                let usageLimit: Double?
                let noMonthlyLimit: Bool?
                let monthlyLimitReached: Bool?

                enum CodingKeys: String, CodingKey {
                    case usage
                    case totalUsage = "total_usage"
                    case usageLimit = "usage_limit"
                    case noMonthlyLimit = "no_monthly_limit"
                    case monthlyLimitReached = "monthly_limit_reached"
                }
            }

            let completion: Completion
            let currency: String?
            let lastPaymentFailure: Bool?

            enum CodingKeys: String, CodingKey {
                case completion
                case currency
                case lastPaymentFailure = "last_payment_failure"
            }
        }

        let limits: Context
    }

    func fetch(key: String, extra: String?) async throws -> ProviderReading {
        let url = URL(string: "https://api.mistral.ai/v1/admin/spend-limit")!
        let headers = ["x-api-key": key]

        let (data, _) = try await HTTP.get(url, headers: headers)
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Limits.self, from: data) else {
            throw ProviderError.decoding
        }

        let limits = payload.limits
        let completion = limits.completion
        let currency = limits.currency ?? "USD"

        // Prefer total_usage (includes Vibe); fall back to the completion slice.
        let spent = completion.totalUsage ?? completion.usage
        let cap = completion.usageLimit
        let uncapped = completion.noMonthlyLimit == true || cap == nil

        let caption: String
        if uncapped {
            caption = "no monthly limit set"
        } else if completion.monthlyLimitReached == true {
            caption = "monthly limit reached"
        } else {
            caption = "this billing month"
        }

        var metrics: [UsageMetric] = [UsageMetric(
            id: "spend",
            title: "Spend",
            used: spent,
            limit: uncapped ? nil : cap,
            unit: .usd,
            currencyCode: currency,
            caption: caption,
            isHeadline: true)]

        if !uncapped, let cap, cap > 0, completion.monthlyLimitReached != true {
            metrics.append(UsageMetric(
                id: "remaining",
                title: "Limit remaining",
                remaining: max(cap - (spent ?? 0), 0),
                unit: .usd,
                currencyCode: currency,
                caption: "until the cap resets"))
        }

        var notes: [String] = []
        if completion.monthlyLimitReached == true {
            notes.append("This organization has hit its monthly spending limit.")
        }
        if limits.lastPaymentFailure == true {
            notes.append("The most recent payment failed.")
        }
        if uncapped {
            notes.append("No monthly spending limit is configured, so there is "
                       + "nothing to measure spend against.")
        }

        return ProviderReading(label: nil, metrics: metrics, notes: notes)
    }
}
