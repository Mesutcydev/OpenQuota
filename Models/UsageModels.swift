import Foundation

/// What a number means, which drives how it is formatted on screen.
enum MetricUnit: String, Codable, Hashable {
    case usd
    case tokens
    case requests
    /// A share of an allowance the provider reports directly as a percentage,
    /// rather than as an amount we divide ourselves.
    case percent
    /// Provider-specific credits, points or characters — shown as a bare
    /// count; the metric title says what the unit is.
    case credits
}

/// A single measurable thing a provider reports: a credit balance, a spend
/// total, a token count, a request quota.
///
/// Every field past `title` is optional on purpose. Providers expose wildly
/// different slices of their accounting, and a metric with a `used` value but
/// no `limit` is still worth showing — it just renders as a bare number
/// instead of a progress bar.
struct UsageMetric: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var used: Double?
    var limit: Double?
    var remaining: Double?
    var unit: MetricUnit
    /// ISO currency code for `.usd` metrics that are not actually dollars.
    var currencyCode: String? = nil
    var resetsAt: Date?
    /// Free-text qualifier shown under the value, e.g. "rolling 30 days".
    var caption: String?
    /// The one metric a card leads with. Exactly one per provider reading.
    var isHeadline: Bool = false

    /// Fraction of the allowance consumed, or nil when there is no limit to
    /// measure against. Clamped so a provider over its cap still renders.
    var fraction: Double? {
        guard let limit, limit > 0 else { return nil }
        let consumed: Double
        if let used {
            consumed = used
        } else if let remaining {
            consumed = limit - remaining
        } else {
            return nil
        }
        return min(max(consumed / limit, 0), 1)
    }

    /// Value to lead with. Percentages are reported as a share consumed, so
    /// leading with "remaining" there contradicts the bar beside it.
    var displayValue: Double? {
        switch unit {
        case .percent: return used ?? remaining
        default: return remaining ?? used
        }
    }
}

extension Array where Element == UsageMetric {
    /// The credit-left figure: whatever the account holds in USD, summed over
    /// the metric ids providers actually use for balances. Non-dollar
    /// currencies are excluded from the sum — mixing CNY into a dollar total
    /// would be a lie — and accounts with no USD balance read as `nil` rather
    /// than a fake zero.
    ///
    /// Shared by the dashboard header and the widget so the two never drift.
    var usdCreditRemaining: Double? {
        let balanceIDs: Set<String> = ["balance", "total", "available", "credit", "credits"]
        var total = 0.0
        var found = false
        for metric in self
        where metric.unit == .usd
            && (metric.currencyCode ?? "USD") == "USD"
            && balanceIDs.contains(metric.id) {
            if let remaining = metric.remaining {
                total += remaining
                found = true
            }
        }
        return found ? total : nil
    }
}

/// One successful read from a provider.
struct ProviderReading: Hashable {
    var label: String?
    var metrics: [UsageMetric]
    var notes: [String] = []
    /// A rotated credential the provider handed back (a web session cookie
    /// the server renewed). The app writes it over the stored one so the
    /// session does not silently expire.
    var renewedCredential: String? = nil
}

/// A reading tied to an account and a moment, persisted for history.
struct UsageSnapshot: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var accountID: UUID
    var fetchedAt: Date
    var label: String?
    var metrics: [UsageMetric]
    var notes: [String] = []

    var headline: UsageMetric? {
        metrics.first(where: \.isHeadline) ?? metrics.first
    }
}

/// A provider connection the user has added. The secret itself never lives
/// here — it is held in the keychain under `id`.
struct Account: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var providerID: String
    var nickname: String
    /// Second piece of configuration some providers need alongside the key —
    /// a base URL, a team id, a region. Meaning is set by the descriptor.
    var extraValue: String?
    var createdAt: Date = Date()
    /// Free-form group such as "work" or "personal", for splitting spend.
    var tag: String? = nil
}

/// Per-account load state held in memory, not persisted.
enum AccountState: Hashable {
    case idle
    case loading
    case loaded(UsageSnapshot)
    case failed(String)

    var snapshot: UsageSnapshot? {
        if case .loaded(let snapshot) = self { return snapshot }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
