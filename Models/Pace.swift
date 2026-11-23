import Foundation

/// "At this pace…" — a projection of an account's headline figure from its
/// recent history.
///
/// Two shapes are forecast, because they are the two questions people ask:
/// - an allowance with a limit (a plan window, a key cap): *will I hit the
///   cap before it resets, and when?*
/// - a prepaid balance with no limit: *how many days until it is empty?*
/// Spend totals with no limit have nothing to run out of and get no forecast.
enum PaceForecast: Hashable {
    /// Consumption will reach 100% at this moment, before any reset.
    case limitReached(at: Date)
    /// The allowance resets before the current pace would exhaust it.
    case lastsUntilReset(Date)
    /// The prepaid balance empties at this moment.
    case balanceEmpty(at: Date)

    /// One short line for cards and widgets.
    func text(now: Date = Date()) -> String {
        switch self {
        case .limitReached(let date):
            return "At this pace, full \(Pace.when(date, now: now))"
        case .lastsUntilReset:
            return "At this pace, lasts until reset"
        case .balanceEmpty(let date):
            return "At this pace, empty \(Pace.when(date, now: now))"
        }
    }

    /// Whether the projection warrants drawing attention.
    var isWarning: Bool {
        switch self {
        case .limitReached: return true
        case .lastsUntilReset: return false
        case .balanceEmpty(let date): return date.timeIntervalSinceNow < 3 * 86_400
        }
    }
}

enum Pace {
    /// Need at least this much observed time before projecting; two reads a
    /// minute apart produce wild rates.
    static let minimumSpan: TimeInterval = 30 * 60
    /// Balance burn is averaged over at most a week, so a busy morning does
    /// not dominate.
    static let balanceWindow: TimeInterval = 7 * 86_400
    /// Projections further out than this are noise, not a forecast.
    static let horizon: TimeInterval = 120 * 86_400

    static func forecast(
        metric: UsageMetric,
        history: [HistoryPoint],
        now: Date = Date()
    ) -> PaceForecast? {
        if let fraction = metric.fraction {
            return allowance(current: fraction, resetsAt: metric.resetsAt, history: history, now: now)
        }
        if metric.unit == .usd, metric.limit == nil, let remaining = metric.remaining {
            return balance(current: remaining, history: history, now: now)
        }
        return nil
    }

    // MARK: - Allowance

    static func allowance(
        current: Double,
        resetsAt: Date?,
        history: [HistoryPoint],
        now: Date
    ) -> PaceForecast? {
        guard current < 1 else { return nil }
        // Walk back from the newest point while the series only rises: the
        // first drop going backwards is the previous window's reset.
        var window: [(Date, Double)] = [(now, current)]
        for point in history.reversed() {
            guard let fraction = point.fraction, point.date < window[0].0 else { continue }
            if fraction > window[0].1 + 0.02 { break }
            window.insert((point.date, fraction), at: 0)
        }
        guard let first = window.first, now.timeIntervalSince(first.0) >= minimumSpan else { return nil }
        let rate = (current - first.1) / now.timeIntervalSince(first.0)
        guard rate > 0 else {
            return resetsAt.map { .lastsUntilReset($0) }
        }
        let eta = now.addingTimeInterval((1 - current) / rate)
        if let resetsAt, resetsAt > now, eta >= resetsAt { return .lastsUntilReset(resetsAt) }
        guard eta.timeIntervalSince(now) <= horizon else { return nil }
        return .limitReached(at: eta)
    }

    // MARK: - Balance

    static func balance(current: Double, history: [HistoryPoint], now: Date) -> PaceForecast? {
        guard current > 0 else { return nil }
        // Same walk, other direction: a balance only falls between top-ups,
        // so stop at the first point lower than the one after it.
        var window: [(Date, Double)] = [(now, current)]
        for point in history.reversed() {
            guard let remaining = point.remaining, point.date < window[0].0 else { continue }
            guard now.timeIntervalSince(point.date) <= balanceWindow else { break }
            if remaining < window[0].1 - 0.005 { break }
            window.insert((point.date, remaining), at: 0)
        }
        guard let first = window.first, now.timeIntervalSince(first.0) >= minimumSpan else { return nil }
        let rate = (first.1 - current) / now.timeIntervalSince(first.0)
        guard rate > 0 else { return nil }
        let seconds = current / rate
        guard seconds <= horizon else { return nil }
        return .balanceEmpty(at: now.addingTimeInterval(seconds))
    }

    // MARK: - Formatting

    /// "at 16:40", "tomorrow 09:00", "Tue 09:00", "in 12 days".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow \(time)" }
        let days = date.timeIntervalSince(now) / 86_400
        if days < 6 { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        return "in \(Int(days.rounded())) days"
    }
}
