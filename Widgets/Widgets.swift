import SwiftUI
import WidgetKit
import AppIntents

/// The Open Quota widget extension. Reads the board the app rebuilt after its
/// last refresh (every account's headline figure) and lays it out for every
/// widget family the system offers — Home Screen small/medium/large and the
/// Lock Screen accessories.
@main
struct OpenQuotaWidgets: WidgetBundle {
    var body: some Widget {
        BoardWidget()
        ProvidersWidget()
        AccountWidget()
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
            .widgetCanvas(board)
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
                    .foregroundStyle(board.headlineGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("credits left")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if let first = board.entries.first {
                Text(first.headlineText ?? "—")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(board.headlineGradient)
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
/// Follows the app's row design: a raised surface card whose only colour is
/// the provider's own tint — tinted gradient bar, tinted value — shifting to
/// the app's watch-orange / critical-red as the allowance burns down.
struct AccountRow: View {
    @Environment(\.colorScheme) private var scheme

    let entry: WidgetEntry

    private var tint: Color {
        Color(hex: entry.tintHex) ?? .accentColor
    }

    /// App severity: provider tint while healthy, watch from 75%, critical from 90%.
    private func barColor(_ fraction: Double) -> Color {
        if fraction >= 0.90 { return scheme == .dark ? Color(hex: "F0907F")! : Color(hex: "C2412F")! }
        if fraction >= 0.75 { return scheme == .dark ? Color(hex: "EFB25A")! : Color(hex: "B86A00")! }
        return tint
    }

    var body: some View {
        Link(destination: URL(string: "openquota://account/\(entry.id.uuidString)")!) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.6), radius: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.nickname)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if let fraction = entry.fraction {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(barColor(fraction).opacity(0.18))
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [barColor(fraction), barColor(fraction).opacity(0.65)],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(3, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 4)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(entry.headlineText ?? "—")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(entry.fraction.map(barColor) ?? tint)
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
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.14), tint.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(tint.opacity(0.20), lineWidth: 1)))
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

// MARK: - Per-account configuration

/// A connected account, selectable in each widget's edit sheet.
struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation =
        .init(name: "Connected account")
    static let defaultQuery = AccountQuery()

    var id: UUID
    var nickname: String
    var providerName: String
    var tintHex: String?

    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(nickname)", subtitle: "\(providerName)")
    }
}

/// Enumerates the accounts currently on the board.
struct AccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        let all = try await suggestedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        (WidgetStore.load()?.entries ?? WidgetStore.sample.entries).map {
            AccountEntity(id: $0.id, nickname: $0.nickname,
                          providerName: $0.providerName, tintHex: $0.tintHex)
        }
    }
}

/// Selects one account; falls back to the first on the board.
struct SelectAccountIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("Which connected account to show.")

    @Parameter(title: "Account")
    var account: AccountEntity?
}

// MARK: - All-providers widget (small + medium, dense list)

/// Timeline entry for the configurable per-account widget.
struct AccountEntry: TimelineEntry {
    let date: Date
    let board: WidgetBoard
    let intent: SelectAccountIntent?
}

/// Timeline provider for the intent-configurable widget: reads the same
/// board, carries the user's account choice on the entry.
struct AccountIntentProvider: AppIntentTimelineProvider {
    typealias Intent = SelectAccountIntent
    typealias Entry = AccountEntry

    func placeholder(in context: Context) -> AccountEntry {
        AccountEntry(date: Date(), board: WidgetStore.sample, intent: nil)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> AccountEntry {
        AccountEntry(date: Date(),
                     board: WidgetStore.load() ?? WidgetStore.sample,
                     intent: configuration)
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<AccountEntry> {
        let board = WidgetStore.load() ?? WidgetStore.sample
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date())
            ?? Date().addingTimeInterval(21_600)
        let entry = AccountEntry(date: Date(), board: board, intent: configuration)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

/// Timeline for the static all-providers widget: reads the same board.
struct AccountProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: WidgetStore.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(BoardEntry(date: Date(), board: WidgetStore.load() ?? WidgetStore.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let board = WidgetStore.load() ?? WidgetStore.sample
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date())
            ?? Date().addingTimeInterval(21_600)
        completion(Timeline(entries: [BoardEntry(date: Date(), board: board)],
                            policy: .after(next)))
    }
}

/// "Providers" widget: every connected account in a compact list. The small
/// size drops the header/spend footer so three-plus rows still fit, and the
/// medium keeps a refresh button with room for six rows.
struct ProvidersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenQuotaProviders", provider: AccountProvider()) { entry in
            ProvidersView(board: entry.board)
        }
        .configurationDisplayName("All Providers")
        .description("Every connected account, one compact row each.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProvidersView: View {
    @Environment(\.widgetFamily) private var family

    let board: WidgetBoard

    var body: some View {
        content
            .fontDesign(.monospaced)
            .widgetCanvas(board)
    }

    @ViewBuilder
    private var content: some View {
        let rows = family == .systemSmall ? 3 : 6
        VStack(alignment: .leading, spacing: 7) {
            if family != .systemSmall {
                BoardHeader(board: board, showRefresh: true)
                Divider()
            }
            if board.entries.isEmpty {
                Text("No accounts yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(board.entries.prefix(rows)) { entry in
                    AccountRow(entry: entry)
                }
                if board.entries.count > rows {
                    Text("+\(board.entries.count - rows) more — open for all")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Per-account widget: configurable in the edit sheet, one account's
/// headline and its limit windows. Available small (headline only),
/// medium (headline + window bars) and as Lock Screen accessories.
struct AccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenQuotaAccount",
                              intent: SelectAccountIntent.self,
                              provider: AccountIntentProvider()) { entry in
            AccountConfigView(board: entry.board,
                              selected: entry.intent?.account?.id)
        }
        .configurationDisplayName("Single Account")
        .description("One connected account you pick — headline and limits.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
        ])
    }
}

struct AccountConfigView: View {
    @Environment(\.widgetFamily) private var family

    let board: WidgetBoard
    let selected: UUID?

    private var entry: WidgetEntry? {
        board.entries.first { $0.id == selected } ?? board.entries.first
    }

    var body: some View {
        Group {
            if let entry {
                switch family {
                case .systemSmall: AccountSmall(entry: entry)
                case .systemMedium: AccountMedium(entry: entry, board: board)
                case .accessoryInline:
                    Text("\(entry.headlineText ?? "—") · \(entry.nickname)")
                case .accessoryCircular: AccountCircular(entry: entry)
                default: AccountRectangular(entry: entry)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Add one in Open Quota")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fontDesign(.monospaced)
        .widgetCanvas(board)
    }
}

/// Severity-aware gradient limit bar shared by the per-account widgets:
/// provider tint while healthy, the app's watch-orange from 75% and
/// critical-red from 90%, always as a bright-to-soft gradient capsule.
struct LimitBar: View {
    @Environment(\.colorScheme) private var scheme

    let entry: WidgetEntry
    let fraction: Double
    var height: CGFloat = 5

    private var color: Color {
        if fraction >= 0.90 { return scheme == .dark ? Color(hex: "F0907F")! : Color(hex: "C2412F")! }
        if fraction >= 0.75 { return scheme == .dark ? Color(hex: "EFB25A")! : Color(hex: "B86A00")! }
        return Color(hex: entry.tintHex) ?? .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.65)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

/// Small single-account: brand dot, nickname, big headline, the top limit
/// window as a slim bar.
struct AccountSmall: View {
    let entry: WidgetEntry

    private var tint: Color { Color(hex: entry.tintHex) ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(entry.nickname)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(entry.headlineText ?? "—")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(entry.headlineGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(entry.headlineTitle ?? entry.providerName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let window = entry.windows?.first {
                LimitBar(entry: entry, fraction: window.fraction, height: 5)
                Text(window.title)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .widgetURL(URL(string: "openquota://account/\(entry.id.uuidString)"))
    }
}

/// Medium single-account: headline block on the left, up to four limit
/// windows as labelled bars on the right.
struct AccountMedium: View {
    let entry: WidgetEntry
    let board: WidgetBoard

    private var tint: Color { Color(hex: entry.tintHex) ?? .accentColor }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(entry.nickname)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                Text(entry.headlineText ?? "—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(entry.headlineGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(entry.headlineTitle ?? entry.providerName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                ForEach((entry.windows ?? []).prefix(4)) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(window.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(window.valueText)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        LimitBar(entry: entry, fraction: window.fraction, height: 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "openquota://account/\(entry.id.uuidString)"))
    }
}

/// Circular Lock Screen accessory: the account's headline abbreviated.
struct AccountCircular: View {
    let entry: WidgetEntry

    private var headline: String {
        guard let text = entry.headlineText else { return "—" }
        if text.hasPrefix("$"), let value = Double(text.dropFirst()) {
            return value >= 1000 ? String(format: "$%.0fk", value / 1000)
                                 : String(format: "$%.0f", value)
        }
        return text
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(headline)
                .font(.system(size: 14, weight: .bold))
                .minimumScaleFactor(0.6)
        }
    }
}

/// Rectangular Lock Screen accessory: nickname, headline and first window.
struct AccountRectangular: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
            if let window = entry.windows?.first {
                HStack {
                    Text(window.title)
                        .font(.system(size: 9))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(window.valueText)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget design system
// Mirrors the app: graphite canvas surfaces, and the only colour comes from
// the connected providers' own tints — as a soft wash behind the board and a
// gradient on headline figures.

extension WidgetBoard {
    /// Gradient of the connected providers' tints for big headline figures.
    var headlineGradient: LinearGradient {
        let tints = entries.compactMap { Color(hex: $0.tintHex) }
        let colors: [Color] = tints.isEmpty ? [Color.primary] : Array(tints.prefix(4))
        return LinearGradient(colors: colors,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// The widget canvas: the app's calm graphite surface with a soft
    /// gradient wash of the providers' tints in the corner.
    func widgetCanvas(_ board: WidgetBoard) -> some View {
        containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemBackground)
                .overlay(
                    LinearGradient(colors: washColors(board),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .allowsHitTesting(false))
        }
    }

    private func washColors(_ board: WidgetBoard) -> [Color] {
        let tints = board.entries.compactMap { Color(hex: $0.tintHex) }
        guard !tints.isEmpty else { return [.clear] }
        var colors = tints.prefix(3).enumerated().map { index, tint in
            tint.opacity(0.16 - Double(index) * 0.04)
        }
        colors.append(.clear)
        return colors
    }
}

// MARK: - Helpers

extension WidgetEntry {
    /// The account's own tint as a headline gradient — bright tint fading
    /// slightly toward the trailing edge.
    var headlineGradient: LinearGradient {
        let tint = Color(hex: tintHex) ?? Color.accentColor
        return LinearGradient(colors: [tint, tint.opacity(0.72)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

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
