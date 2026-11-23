import Foundation

/// Board-wide aggregates for the Overview hero, derived from last-good
/// snapshots. Pure, so the rules are unit-tested rather than living in a view.
struct BoardSummary {
    struct Attention: Identifiable {
        var id: UUID { account.id }
        let account: Account
        let metric: UsageMetric?
        let fraction: Double?
        let error: String?
    }

    /// Ids providers emit for month-to-date spend.
    static let spendIDs: Set<String> = ["spend", "month-cost", "monthly"]

    struct SpendShare: Identifiable {
        var id: UUID { account.id }
        let account: Account
        let amount: Double
    }

    /// Month-to-date USD spend, or nil when no account reports one.
    let monthSpend: Double?
    /// Who the month's spend went to, largest first. Zero-spend accounts are
    /// left out.
    let spendShares: [SpendShare]
    /// USD credit remaining across prepaid balances, or nil when none.
    let creditLeft: Double?
    /// True when some account reports money in a non-USD currency that was
    /// therefore left out of the totals.
    let excludesOtherCurrencies: Bool
    /// Accounts at or above the watch line, or failing — worst first.
    let attention: [Attention]
    let connected: Int
    let reporting: Int
    /// Oldest reading on the board.
    let oldestReading: Date?

    init(
        accounts: [Account],
        snapshots: [UUID: UsageSnapshot],
        errors: [UUID: String] = [:],
        watchFraction: Double = Theme.watchFraction
    ) {
        var spend = 0.0, spendFound = false
        var credit = 0.0, creditFound = false
        var otherCurrency = false
        var attention: [Attention] = []
        var dates: [Date] = []
        var shares: [SpendShare] = []

        for account in accounts {
            if let message = errors[account.id] {
                attention.append(Attention(account: account, metric: nil, fraction: nil, error: message))
            }
            guard let snapshot = snapshots[account.id] else { continue }
            dates.append(snapshot.fetchedAt)

            if let monthly = snapshot.metrics.first(where: {
                Self.spendIDs.contains($0.id) && $0.unit == .usd && ($0.currencyCode ?? "USD") == "USD"
            }), let used = monthly.used {
                spend += used
                spendFound = true
                if used > 0 { shares.append(SpendShare(account: account, amount: used)) }
            }
            if let left = snapshot.metrics.usdCreditRemaining {
                credit += left
                creditFound = true
            }
            if snapshot.metrics.contains(where: { $0.unit == .usd && ($0.currencyCode ?? "USD") != "USD" }) {
                otherCurrency = true
            }
            if errors[account.id] == nil,
               let headline = snapshot.headline,
               let fraction = headline.fraction,
               fraction >= watchFraction {
                attention.append(Attention(account: account, metric: headline, fraction: fraction, error: nil))
            }
        }

        monthSpend = spendFound ? spend : nil
        spendShares = shares.sorted { $0.amount > $1.amount }
        creditLeft = creditFound ? credit : nil
        excludesOtherCurrencies = otherCurrency
        self.attention = attention.sorted {
            // Errors after the fullest allowances; allowances worst first.
            ($0.fraction ?? 0.5) > ($1.fraction ?? 0.5)
        }
        connected = accounts.count
        reporting = accounts.filter { snapshots[$0.id] != nil }.count
        oldestReading = dates.min()
    }
}
