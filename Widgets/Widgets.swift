import SwiftUI
import WidgetKit

/// The Open Quota widget extension. Reads the board the app rebuilt after its
/// last refresh (every account's headline figure) and lays it out for every
/// widget family the system offers — Home Screen small/medium/large and the
/// Lock Screen accessories.
@main
struct OpenQuotaWidgets: WidgetBundle {
    var body: some Widget {
        BoardWidget()
    }
}

// MARK: - Timeline

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: WidgetBoard
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: WidgetStore.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(BoardEntry(date: Date(), board: WidgetStore.load() ?? WidgetStore.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let board = WidgetStore.load() ?? WidgetStore.sample
        let entry = BoardEntry(date: Date(), board: board)
        // The app calls WidgetCenter.reloadAllTimelines() after every refresh,
        // so WidgetKit only needs a safety tick for days the app never ran.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date().addingTimeInterval(21_600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenQuotaBoard", provider: BoardProvider()) { entry in
            BoardView(board: entry.board)
        }
        .configurationDisplayName("Open Quota")
        .description("Balances, spend and limit headroom for every connected account.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
        ])
    }
}

struct BoardView: View {
    @Environment(\.widgetFamily) private var family

    let board: WidgetBoard

    var body: some View {
        content
            .fontDesign(.monospaced)
            .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall: SmallBoard(board: board)
        case .systemMedium: MediumBoard(board: board)
        case .systemLarge: LargeBoard(board: board)
        case .accessoryInline: InlineAccessory(board: board)
        case .accessoryCircular: CircularAccessory(board: board)
        default: RectangularAccessory(board: board)
        }
    }
}

// MARK: - Home Screen families

/// Small: the aggregate headline — total USD credits left, account count,
/// month spend — with a tap that opens the app.
struct SmallBoard: View {
    let board: WidgetBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("openquota")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let total = board.usdTotal {
                Text(total, format: .currency(code: "USD"))
                    .font(.system(size: 25, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("credits left")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if let first = board.entries.first {
                Text(first.headlineText ?? "—")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(first.nickname)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No data yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text("\(board.entries.count)")
                    .font(.system(size: 10, weight: .semibold))
                Text(board.entries.count == 1 ? "account" : "accounts")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let spend = board.monthSpend {
                    Text("/mo \(spend, format: .currency(code: "USD"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .widgetURL(URL(string: "openquota://"))
    }
}

/// Shared header: brand, month spend, refresh button (runs in the app's
/// process — the extension only declares it).
struct BoardHeader: View {
    let board: WidgetBoard
    var showRefresh: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("openquota")
                .font(.system(size: 11, weight: .bold))
            Spacer(minLength: 4)
            if let spend = board.monthSpend {
                Text("spent \(spend, format: .currency(code: "USD"))")
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if showRefresh {
                Button(intent: RefreshFromWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// Shared row: one account, tinted, deep-linking to its detail screen.
struct AccountRow: View {
    let entry: WidgetEntry

    private var tint: Color {
        Color(hex: entry.tintHex) ?? .accentColor
    }

    var body: some View {
        Link(destination: URL(string: "openquota://account/\(entry.id.uuidString)")!) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.nickname)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if let fraction = entry.fraction {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(tint.opacity(0.2))
                                Capsule()
                                    .fill(tint)
                                    .frame(width: max(2, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(entry.headlineText ?? "—")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let title = entry.headlineTitle {
                        Text(title)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .contentShape(Rectangle())
        }
    }
}

/// Medium: every account that fits (up to five rows).
struct MediumBoard: View {
    let board: WidgetBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BoardHeader(board: board, showRefresh: true)
            if board.entries.isEmpty {
                Text("No accounts yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(board.entries.prefix(5)) { entry in
                    AccountRow(entry: entry)
                }
                if board.entries.count > 5 {
                    Text("+\(board.entries.count - 5) more — open for all")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Large: every account (up to ten rows) plus the spend summary.
struct LargeBoard: View {
    let board: WidgetBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BoardHeader(board: board, showRefresh: true)
            if board.entries.isEmpty {
                Text("No accounts yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(board.entries.prefix(10)) { entry in
                    AccountRow(entry: entry)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let today = board.todaySpend {
                    Text("today \(today, format: .currency(code: "USD"))")
                        .font(.system(size: 9))
                }
                if let month = board.monthSpend {
                    Text("month \(month, format: .currency(code: "USD"))")
                        .font(.system(size: 9))
                }
                if let projected = board.projectedSpend {
                    Text("→ \(projected, format: .currency(code: "USD"))")
                        .font(.system(size: 9))
                }
                Spacer()
                Text(board.updatedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock Screen accessories

/// Inline: one line, the whole board compressed.
struct InlineAccessory: View {
    let board: WidgetBoard

    var body: some View {
        if let total = board.usdTotal {
            Text("\(total, format: .currency(code: "USD")) left · \(board.entries.count) accounts")
        } else {
            Text("openquota · \(board.entries.count) accounts")
        }
    }
}

/// Circular: total credits left, abbreviated to fit.
struct CircularAccessory: View {
    let board: WidgetBoard

    private var headline: String {
        if let total = board.usdTotal {
            return total >= 1000 ? String(format: "$%.0fk", total / 1000) : String(format: "$%.0f", total)
        }
        return "\(board.entries.count)"
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(headline)
                .font(.system(size: 15, weight: .bold))
                .minimumScaleFactor(0.6)
        }
    }
}

/// Rectangular: the first accounts' headline figures, one per line.
struct RectangularAccessory: View {
    let board: WidgetBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(board.entries.prefix(2)) { entry in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: entry.tintHex) ?? .accentColor)
                        .frame(width: 5, height: 5)
                    Text(entry.nickname)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.headlineText ?? "—")
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            if board.entries.count > 2 {
                Text("+\(board.entries.count - 2) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Helpers

extension Color {
    /// Decodes the app's RRGGBB tints for the widget.
    init?(hex: String?) {
        guard let hex = hex?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: ""),
              hex.count == 6,
              let value = UInt64(hex, radix: 16)
        else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}
