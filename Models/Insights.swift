import Foundation

// MARK: - Spend ledger

/// Day-by-day spend, reconstructed from the month-to-date figure providers
/// report.
///
/// Providers only give a running month total, so the ledger keeps the last
/// month-to-date value seen on each calendar day per account; a day's spend is
/// the rise since the previous recorded day. That makes daily spend survive
/// missed days (the rise lands on the next day read) and month rollovers (a
/// new month starts from zero).
struct SpendLedger: Codable, Hashable {
    /// accountID → "yyyy-MM-dd" → month-to-date USD at the day's last read.
    var mtd: [UUID: [String: Double]] = [:]

    static let keepDays = 120

    mutating func record(account: UUID, monthToDate: Double, at date: Date, calendar: Calendar = .current) {
        mtd[account, default: [:]][Self.key(date, calendar: calendar)] = monthToDate
    }

    mutating func remove(account: UUID) { mtd[account] = nil }

    /// Drops days older than `keepDays`.
    mutating func prune(now: Date = Date(), calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: now) else { return }
        let cutoffKey = Self.key(cutoff, calendar: calendar)
        for (account, days) in mtd {
            mtd[account] = days.filter { $0.key >= cutoffKey }
        }
    }

    /// Spend per day for one account, oldest first.
    func daily(account: UUID, calendar: Calendar = .current) -> [DaySpend] {
        guard let days = mtd[account] else { return [] }
        let ordered = days.sorted { $0.key < $1.key }.compactMap { key, value -> (Date, Double)? in
            Self.date(key, calendar: calendar).map { ($0, value) }
        }
        var result: [DaySpend] = []
        var previous: (Date, Double)?
        for (day, value) in ordered {
            defer { previous = (day, value) }
            let sameMonth = previous.map { calendar.isDate($0.0, equalTo: day, toGranularity: .month) } ?? false
            if sameMonth, let previous {
                result.append(DaySpend(day: day, amount: max(value - previous.1, 0)))
            } else if previous != nil || calendar.component(.day, from: day) == 1 {
                // New month: everything so far this month landed by today.
                result.append(DaySpend(day: day, amount: max(value, 0)))
            }
            // The very first reading mid-month has no baseline; the month's
            // earlier spend would show as one fake spike, so it is skipped.
        }
        return result
    }

    /// Spend per day summed over accounts (all when `accounts` is nil),
    /// oldest first.
    func dailyTotals(accounts: Set<UUID>? = nil, calendar: Calendar = .current) -> [DaySpend] {
        var totals: [Date: Double] = [:]
        for account in mtd.keys where accounts?.contains(account) ?? true {
            for day in daily(account: account, calendar: calendar) {
                totals[day.day, default: 0] += day.amount
            }
        }
        return totals.map { DaySpend(day: $0.key, amount: $0.value) }.sorted { $0.day < $1.day }
    }

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

struct DaySpend: Hashable, Identifiable {
    var id: Date { day }
    let day: Date
    let amount: Double
}

// MARK: - Budget

/// Month-to-date spend against a monthly budget, with a straight-line
/// projection to month end.
struct BudgetStatus: Hashable {
    let spent: Double
    let budget: Double
    /// Spend projected for the whole month at the pace so far.
    let projected: Double
    let monthEnd: Date

    var fraction: Double { budget > 0 ? spent / budget : 0 }
    var projectedFraction: Double { budget > 0 ? projected / budget : 0 }
    var remaining: Double { budget - spent }
    var isOver: Bool { spent > budget }
    var willExceed: Bool { projected > budget }

    init?(spent: Double?, budget: Double?, now: Date = Date(), calendar: Calendar = .current) {
        guard let spent, let budget, budget > 0,
              let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        self.spent = spent
        self.budget = budget
        monthEnd = month.end.addingTimeInterval(-1)
        let elapsed = now.timeIntervalSince(month.start)
        // Under a day of data makes the projection wild; treat it as one day.
        let elapsedDays = max(elapsed / 86_400, 1)
        let monthDays = month.duration / 86_400
        projected = spent / elapsedDays * monthDays
    }

    /// "on track for $2,140 by nov 30".
    var projectionText: String {
        let end = monthEnd.formatted(.dateTime.month(.abbreviated).day()).lowercased()
        return "on track for \(Format.currency(projected)) by \(end)"
    }
}

// MARK: - Spike

/// Today's spend compared with the usual day.
struct SpendSpike: Hashable {
    let today: Double
    /// Mean of recent complete days.
    let usual: Double

    var ratio: Double? { usual > 0 ? today / usual : nil }

    /// "3.1× usual" or "new" when there was no spend before.
    var ratioText: String {
        guard let ratio else { return "new" }
        return String(format: "%.1f× usual", ratio)
    }

    /// A spike needs at least three earlier days with data, today ≥ 2.5×
    /// the mean and at least $5 above it — so a quiet $0.40 → $1.20 day is not
    /// an alarm.
    static func detect(_ days: [DaySpend], now: Date = Date(), calendar: Calendar = .current,
                       multiple: Double = 2.5, minimumRise: Double = 5) -> SpendSpike? {
        guard let today = days.last(where: { calendar.isDate($0.day, inSameDayAs: now) }) else { return nil }
        let earlier = days.filter { $0.day < calendar.startOfDay(for: now) }.suffix(7)
        guard earlier.count >= 3 else { return nil }
        let usual = earlier.reduce(0) { $0 + $1.amount } / Double(earlier.count)
        guard today.amount - usual >= minimumRise else { return nil }
        guard usual == 0 || today.amount >= usual * multiple else { return nil }
        return SpendSpike(today: today.amount, usual: usual)
    }
}

// MARK: - Peak hours

/// When in the day an allowance gets used, from the rises in its history.
struct PeakHours: Hashable {
    /// Hour of day (0–23) with the most consumption.
    let peak: Int
    /// Hour of day with the least.
    let quiet: Int
    /// Consumption share per hour of day, summing to 1.
    let shares: [Double]

    /// "busiest 14:00–15:00 · quietest 03:00".
    var text: String {
        "busiest \(Self.hour(peak))–\(Self.hour((peak + 1) % 24)) · quietest \(Self.hour(quiet))"
    }

    static func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    /// Needs rises spread over at least three days to say anything.
    static func analyze(_ history: [HistoryPoint], calendar: Calendar = .current) -> PeakHours? {
        var buckets = Array(repeating: 0.0, count: 24)
        var days = Set<String>()
        for (a, b) in zip(history, history.dropFirst()) {
            guard let fa = a.fraction, let fb = b.fraction, fb > fa,
                  b.date.timeIntervalSince(a.date) <= 2 * 3600 else { continue }
            buckets[calendar.component(.hour, from: b.date)] += fb - fa
            days.insert(SpendLedger.key(b.date, calendar: calendar))
        }
        let total = buckets.reduce(0, +)
        guard days.count >= 3, total > 0,
              let peak = buckets.indices.max(by: { buckets[$0] < buckets[$1] }),
              let quiet = buckets.indices.min(by: { buckets[$0] < buckets[$1] }) else { return nil }
        return PeakHours(peak: peak, quiet: quiet, shares: buckets.map { $0 / total })
    }
}

// MARK: - Trend

enum Trend {
    /// Headline values over the last `days`, thinned to at most `points`.
    static func series(_ history: [HistoryPoint], days: Double = 7, points: Int = 28,
                       now: Date = Date()) -> [Double] {
        let recent = history.filter { now.timeIntervalSince($0.date) <= days * 86_400 }
        guard recent.count >= 2 else { return [] }
        let stride = max(recent.count / points, 1)
        var values = Swift.stride(from: 0, to: recent.count, by: stride).map { recent[$0].value }
        if let last = recent.last?.value, values.last != last { values.append(last) }
        return values
    }
}

// MARK: - Recap

/// The month in a few figures, for the share card.
struct MonthRecap: Hashable {
    let month: Date
    let total: Double?
    let topName: String?
    let topAmount: Double?
    let busiestDay: DaySpend?
    let activeDays: Int
    let accounts: Int
    let days: [DaySpend]
    /// Every recorded day, for the card's activity graph.
    let recentDays: [DaySpend]

    init(summary: BoardSummary, days allDays: [DaySpend], now: Date = Date(), calendar: Calendar = .current) {
        month = now
        total = summary.monthSpend
        topName = summary.spendShares.first?.account.nickname
        topAmount = summary.spendShares.first?.amount
        recentDays = allDays
        days = allDays.filter { calendar.isDate($0.day, equalTo: now, toGranularity: .month) }
        busiestDay = days.max { $0.amount < $1.amount }
        activeDays = days.filter { $0.amount > 0.005 }.count
        accounts = summary.connected
    }
}

// MARK: - CSV

enum HistoryExport {
    /// One row per history point and per recorded spend day.
    static func csv(accounts: [Account], history: [UUID: [HistoryPoint]], ledger: SpendLedger,
                    providerName: (String) -> String) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["kind,account,provider,tag,date,value,unit,fraction_used,remaining"]
        for account in accounts {
            let name = field(account.nickname)
            let provider = field(providerName(account.providerID))
            let tag = field(account.tag ?? "")
            for point in history[account.id] ?? [] {
                lines.append([
                    "headline", name, provider, tag, iso.string(from: point.date),
                    number(point.value), point.unit.rawValue,
                    point.fraction.map(number) ?? "", point.remaining.map(number) ?? "",
                ].joined(separator: ","))
            }
            for day in ledger.daily(account: account.id) {
                lines.append([
                    "daily_spend", name, provider, tag, SpendLedger.key(day.day),
                    number(day.amount), "usd", "", "",
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double) -> String { String(format: "%.4f", value) }

    /// Quotes a field when it holds a comma, quote or newline.
    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
