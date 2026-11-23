import Foundation
import WidgetKit

/// The widget's model: a compact snapshot of what the dashboard last read, so
/// the home screen and Lock Screen can show "credits left" without opening
/// the app. The app rebuilds this after every successful refresh and writes
/// it into the shared App Group container; the widget only ever reads.
///
/// Deliberately small and decodable — no provider types, no theme — so it can
/// compile into both the app and the widget extension.
struct WidgetEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var nickname: String
    var providerName: String
    /// USD credit remaining, or nil when the account holds nothing the
    /// credit-left rule recognises.
    var creditLeft: Double?
    /// Share of the headline allowance consumed, when the provider reports a
    /// limit. Drives the red alarm on the row.
    var fraction: Double?
    /// Brand colour for the row, as RRGGBB.
    var tintHex: String? = nil
    /// The account's headline figure, preformatted by the app.
    var headlineText: String? = nil
    var headlineTitle: String? = nil
    /// "At this pace, full at 16:40" — projected by the app.
    var paceText: String? = nil
    /// When the headline allowance resets, for Lock Screen countdowns.
    var resetsAt: Date? = nil
    /// Every metric with a limit, headline first, at most four.
    var windows: [WidgetWindow]? = nil
}

/// One limit window or allowance on an account, for the per-account widget.
struct WidgetWindow: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var fraction: Double
    var valueText: String
    var resetsAt: Date?
}

struct WidgetBoard: Codable, Hashable {
    var updatedAt: Date
    var entries: [WidgetEntry]
    /// Sum of USD credit across entries. Nil when no account reports a
    /// dollar balance (mixing CNY into this number would be a lie).
    var usdTotal: Double?
    /// Month-to-date USD spend across accounts.
    var monthSpend: Double? = nil
    /// Monthly budget, when one is set.
    var budget: Double? = nil
    /// Month-end spend at the pace so far.
    var projectedSpend: Double? = nil
    /// Today's spend.
    var todaySpend: Double? = nil
    /// "3.5× usual" when today is a spike.
    var spikeText: String? = nil
    /// Daily spend for the last 28 days, oldest first, today last.
    var recentDaily: [Double]? = nil

    /// Every limited metric, headline first, preformatted for the widget.
    static func windows(_ snapshot: UsageSnapshot) -> [WidgetWindow] {
        let limited = snapshot.metrics.filter { $0.fraction != nil }
        let ordered = limited.filter(\.isHeadline) + limited.filter { !$0.isHeadline }
        return ordered.prefix(4).compactMap { metric in
            guard let fraction = metric.fraction else { return nil }
            let value = metric.unit == .percent
                ? "\(Int((fraction * 100).rounded()))%"
                : (metric.displayValue.map {
                    Format.value($0, unit: metric.unit, currencyCode: metric.currencyCode)
                } ?? "\(Int((fraction * 100).rounded()))%")
            return WidgetWindow(id: metric.id, title: metric.title, fraction: fraction,
                                valueText: value, resetsAt: metric.resetsAt)
        }
    }

    /// Built from last-good snapshots, so an account that is mid-refresh or
    /// failed keeps its previous figure instead of vanishing from the widget.
    /// `updatedAt` is the oldest reading on the board, so the widget never
    /// claims fresher data than its stalest row.
    static func build(
        accounts: [Account],
        snapshots: [UUID: UsageSnapshot],
        namer: (String) -> String,
        tintFor: (String) -> String? = { _ in nil },
        paceFor: (UUID) -> String? = { _ in nil },
        fallbackDate: Date = Date()
    ) -> WidgetBoard {
        var dates: [Date] = []
        let entries: [WidgetEntry] = accounts.compactMap { account in
            guard let snapshot = snapshots[account.id] else { return nil }
            dates.append(snapshot.fetchedAt)
            let headline = snapshot.headline
            return WidgetEntry(
                id: account.id,
                nickname: account.nickname,
                providerName: namer(account.providerID),
                creditLeft: snapshot.metrics.usdCreditRemaining,
                fraction: headline?.fraction,
                tintHex: tintFor(account.providerID),
                headlineText: headline.flatMap { metric in
                    metric.displayValue.map {
                        Format.value($0, unit: metric.unit, currencyCode: metric.currencyCode)
                    }
                },
                headlineTitle: headline?.title,
                paceText: paceFor(account.id),
                resetsAt: headline?.resetsAt,
                windows: Self.windows(snapshot))
        }
        let withCredit = entries.compactMap(\.creditLeft)
        return WidgetBoard(
            updatedAt: dates.min() ?? fallbackDate,
            entries: entries,
            usdTotal: withCredit.isEmpty ? nil : withCredit.reduce(0, +))
    }
}

/// Storage for the widget's shared snapshot. Everything goes through one
/// App Group `UserDefaults`, which is the only container both the app and
/// the extension can read.
enum WidgetStore {
    static let appGroupID = "group.ai.openquota.shared"
    private static let key = "widgetBoard"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ board: WidgetBoard) {
        guard let data = try? JSONEncoder().encode(board) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> WidgetBoard? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetBoard.self, from: data)
    }

    /// Shown by the widget's placeholder and gallery, and before the first
    /// app refresh: one account per state the design has to carry — calm,
    /// watch, critical, and a balance with no limit.
    static let sample: WidgetBoard = {
        let now = Date()
        return WidgetBoard(
            updatedAt: now.addingTimeInterval(-300),
            entries: [
                WidgetEntry(
                    id: UUID(), nickname: "Claude Max", providerName: "Claude",
                    creditLeft: nil, fraction: 0.64, tintHex: "D97757",
                    headlineText: "64%", headlineTitle: "5-hour window",
                    resetsAt: now.addingTimeInterval(2 * 3600 + 840),
                    windows: [
                        WidgetWindow(id: "5h", title: "5-hour window", fraction: 0.64, valueText: "64%",
                                     resetsAt: now.addingTimeInterval(2 * 3600 + 840)),
                        WidgetWindow(id: "7d", title: "Weekly", fraction: 0.41, valueText: "41%",
                                     resetsAt: now.addingTimeInterval(3 * 86400)),
                    ]),
                WidgetEntry(
                    id: UUID(), nickname: "Personal key", providerName: "OpenRouter",
                    creditLeft: 8.82, fraction: 0.82, tintHex: "6467F2",
                    headlineText: "$8.82", headlineTitle: "Credits left",
                    windows: [WidgetWindow(id: "credit", title: "Credit used", fraction: 0.82,
                                           valueText: "$8.82", resetsAt: nil)]),
                WidgetEntry(
                    id: UUID(), nickname: "Codex", providerName: "ChatGPT",
                    creditLeft: nil, fraction: 0.93, tintHex: "10A37F",
                    headlineText: "93%", headlineTitle: "Weekly limit",
                    resetsAt: now.addingTimeInterval(86400 + 3600),
                    windows: [WidgetWindow(id: "7d", title: "Weekly limit", fraction: 0.93, valueText: "93%",
                                           resetsAt: now.addingTimeInterval(86400 + 3600))]),
                WidgetEntry(
                    id: UUID(), nickname: "Novita AI", providerName: "Novita AI",
                    creditLeft: 100.00, fraction: nil, tintHex: "23D18B",
                    headlineText: "$100.00", headlineTitle: "Balance"),
            ],
            usdTotal: 108.82,
            monthSpend: 412.40,
            budget: 600,
            projectedSpend: 538.10,
            todaySpend: 18.25)
    }()
}
