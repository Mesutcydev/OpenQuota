import SwiftUI
import WidgetKit
import AppIntents

/// The Open Quota widget extension. Reads the board the app rebuilt after its
/// last refresh (every account's headline figure) and lays it out for every
/// widget family the system offers — Home Screen small/medium/large and the
/// Lock Screen accessories.
///
/// The look mirrors the app's dashboard: a `▍ TITLE` panel header, monospaced
/// type, and segmented meters drawn in calm ink that only turn amber (75%) or
/// red (90%) when a limit is actually at stake.
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

/// One timeline for every widget: an entry now, then one at each upcoming
/// limit reset, so a 5-hour window that rolls over shows "reset" on time
/// instead of its stale load until the app next runs.
enum BoardTimeline {
    /// The app reloads timelines after each refresh that changed the board;
    /// this is only the safety tick for days the app never runs.
    static let refreshInterval: TimeInterval = 6 * 3600

    static var current: WidgetBoard { WidgetStore.load() ?? WidgetStore.sample }

    static func dates(for board: WidgetBoard, from now: Date = Date()) -> [Date] {
        let horizon = now.addingTimeInterval(refreshInterval)
        let resets = board.entries.flatMap { entry in
            [entry.resetsAt].compactMap { $0 } + (entry.windows ?? []).compactMap(\.resetsAt)
        }
        let upcoming = Set(resets.filter { $0 > now && $0 < horizon }).sorted().prefix(12)
        return [now] + upcoming
    }

    static func timeline<Entry: TimelineEntry>(make: (Date, WidgetBoard) -> Entry) -> Timeline<Entry> {
        let board = current
        let now = Date()
        let entries = dates(for: board, from: now).map { make($0, board.asOf($0)) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshInterval)))
    }
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: WidgetStore.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(BoardEntry(date: Date(), board: BoardTimeline.current.asOf(Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        completion(BoardTimeline.timeline { BoardEntry(date: $0, board: $1) })
    }
}

// MARK: - Design tokens
// The widget extension does not compile the app's Theme, so the handful of
// tokens it needs are mirrored here with the same values.

enum WTheme {
    static let surface = adaptive(light: "FFFFFF", dark: "18181B")
    static let raised = adaptive(light: "EBEDF0", dark: "232327")
    static let divider = adaptive(light: "10182817", dark: "FFFFFF12")
    static let track = adaptive(light: "E3E6EA", dark: "2A2A2E")

    static let brand = adaptive(light: "15171A", dark: "ECECEE")
    static let ink = adaptive(light: "15171A", dark: "F2F2F4")
    static let inkSecondary = adaptive(light: "5F6670", dark: "9E9EA4")
    static let inkTertiary = adaptive(light: "9AA0A8", dark: "66666C")
    static let gauge = adaptive(light: "23262B", dark: "E2E2E6")

    static let watch = adaptive(light: "B86A00", dark: "EFB25A")
    static let critical = adaptive(light: "C2412F", dark: "F0907F")

    /// Horizontal inset of every Home Screen layout (margins are disabled so
    /// the header band can run edge to edge).
    static let inset: CGFloat = 14

    /// Calm ink while healthy, amber from 75%, red from 90% — the app's rule.
    static func severity(_ fraction: Double, calm: Color = gauge) -> Color {
        if fraction >= 0.90 { return critical }
        if fraction >= 0.75 { return watch }
        return calm
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 9.99) * 100).rounded()))%"
    }

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// `RRGGBB` or `RRGGBBAA`.
    private static func uiColor(_ hex: String) -> UIColor {
        guard let value = UInt64(hex, radix: 16), hex.count == 6 || hex.count == 8 else { return .clear }
        let alpha = hex.count == 8
        let r = alpha ? (value >> 24) & 0xFF : (value >> 16) & 0xFF
        let g = alpha ? (value >> 16) & 0xFF : (value >> 8) & 0xFF
        let b = alpha ? (value >> 8) & 0xFF : value & 0xFF
        let a = alpha ? value & 0xFF : 0xFF
        return UIColor(red: Double(r) / 255, green: Double(g) / 255,
                       blue: Double(b) / 255, alpha: Double(a) / 255)
    }
}

// MARK: - Building blocks

/// The app's `SegmentedMeter`: a full-width row of small blocks, filled in
/// ink (or amber/red under load) over a quiet track.
struct Meter: View {
    let fraction: Double
    var height: CGFloat = 7
    var segment: CGFloat = 4
    var gap: CGFloat = 2
    var showsSeverity = true

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let color = showsSeverity ? WTheme.severity(clamped) : WTheme.gauge
        GeometryReader { proxy in
            let count = max(Int((proxy.size.width + gap) / (segment + gap)), 1)
            let filled = clamped > 0 ? max(Int((clamped * Double(count)).rounded()), 1) : 0
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(index < filled ? color : WTheme.track)
                        .frame(width: segment)
                        .widgetAccentable(index < filled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Provider identity: a small square in the provider's own tint — the only
/// colour a calm widget carries, like the app's glyphs.
struct TintMark: View {
    let hex: String?
    var size: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Color(hex: hex) ?? WTheme.inkTertiary)
            .frame(width: size, height: size)
    }
}

/// The app's panel title bar: `▍ TITLE [n]` on a raised band with a hairline.
struct PanelHeader<Trailing: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("▍").foregroundStyle(WTheme.brand).widgetAccentable()
                Text(title)
                    .lineLimit(1)
                if let count {
                    Text("[\(count)]").foregroundStyle(WTheme.inkTertiary)
                }
                Spacer(minLength: 4)
                trailing
            }
            .font(WTheme.mono(10, .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(WTheme.inkSecondary)
            .padding(.horizontal, WTheme.inset)
            .frame(height: 30)
            .background(renderingMode == .fullColor ? WTheme.raised.opacity(0.55) : .clear)

            Rectangle().fill(WTheme.divider).frame(height: 1)
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil) {
        self.init(title: title, count: count, trailing: { EmptyView() })
    }
}

/// Refresh button for the header (runs in the app's process — the extension
/// only declares it).
struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshFromWidgetIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WTheme.inkSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
    }
}

/// One account on one line, like a row of the app's providers table:
/// `■ nickname ········ ▮▮▮▮▮▯▯▯  $8.82`.
struct TableRow: View {
    let entry: WidgetEntry
    var meterWidth: CGFloat = 70

    var body: some View {
        Link(destination: entry.deepLink) {
            HStack(spacing: 8) {
                TintMark(hex: entry.tintHex)
                Text(entry.nickname.lowercased())
                    .font(WTheme.mono(11, .semibold))
                    .foregroundStyle(WTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let fraction = entry.fraction {
                        Meter(fraction: fraction, height: 7, segment: 3, gap: 1.5)
                    } else {
                        Text(entry.caption)
                            .font(WTheme.mono(8.5))
                            .foregroundStyle(WTheme.inkTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: meterWidth)
                Text(entry.headlineText ?? "—")
                    .font(WTheme.mono(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, WTheme.inset)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }
}

/// One account on two lines — name and figure, then a full-width meter —
/// for the narrow layouts.
struct StackRow: View {
    let entry: WidgetEntry

    var body: some View {
        Link(destination: entry.deepLink) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TintMark(hex: entry.tintHex, size: 6)
                    Text(entry.nickname.lowercased())
                        .font(WTheme.mono(10, .semibold))
                        .foregroundStyle(WTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.headlineText ?? "—")
                        .font(WTheme.mono(10, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(entry.valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                if let fraction = entry.fraction {
                    HStack(spacing: 6) {
                        Meter(fraction: fraction, height: 6, segment: 3, gap: 1.5)
                        // The figure above is already a percentage for
                        // plan windows; only money figures need the load.
                        if !(entry.headlineText ?? "").hasSuffix("%") {
                            Text(WTheme.percent(fraction))
                                .font(WTheme.mono(8.5, .medium))
                                .monospacedDigit()
                                .foregroundStyle(WTheme.severity(fraction, calm: WTheme.inkTertiary))
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                } else {
                    Text(entry.caption)
                        .font(WTheme.mono(8.5))
                        .foregroundStyle(WTheme.inkTertiary)
                        .lineLimit(1)
                        .frame(height: 6)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

/// Hairline between table rows, inset like the app's lists.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(WTheme.divider).frame(height: 1)
            .padding(.leading, WTheme.inset + 15)
    }
}

struct EmptyBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("no accounts yet")
                .font(WTheme.mono(12, .semibold))
                .foregroundStyle(WTheme.inkSecondary)
            Text("❯ add one in open quota")
                .font(WTheme.mono(9))
                .foregroundStyle(WTheme.inkTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WTheme.inset)
    }
}

// MARK: - Board widget

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
        .contentMarginsDisabled()
    }
}

struct BoardView: View {
    @Environment(\.widgetFamily) private var family

    let board: WidgetBoard

    var body: some View {
        content
            .fontDesign(.monospaced)
            .widgetCanvas()
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

/// Small: the headline figure, then the most loaded accounts as meters.
struct SmallBoard: View {
    let board: WidgetBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: board.heroTitle, count: board.entries.count)
            VStack(alignment: .leading, spacing: 0) {
                Text(board.heroFigure)
                    .font(WTheme.mono(22, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(board.shortCaption)
                    .font(WTheme.mono(9))
                    .foregroundStyle(WTheme.inkTertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(board.byLoad.prefix(2)) { entry in
                        StackRow(entry: entry)
                    }
                }
            }
            .padding(.horizontal, WTheme.inset)
            .padding(.top, 9)
            .padding(.bottom, 13)
        }
        .widgetURL(URL(string: "openquota://"))
    }
}

/// Medium: the app's providers table — one line per account.
struct MediumBoard: View {
    let board: WidgetBoard

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "openquota", count: board.entries.count) {
                if let spend = board.monthSpend {
                    Text("mtd \(Format.currency(spend))")
                        .tracking(0)
                        .textCase(nil)
                        .monospacedDigit()
                }
                RefreshButton()
            }
            if board.entries.isEmpty {
                EmptyBoard()
            } else {
                RowStack(entries: Array(board.entries.prefix(4)), slots: 4)
                    .padding(.vertical, 3)
            }
        }
    }
}

/// Large: headline figures and budget, then the full table.
struct LargeBoard: View {
    let board: WidgetBoard

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "openquota", count: board.entries.count) {
                Text(board.updatedAt, format: .dateTime.hour().minute())
                    .tracking(0)
                    .monospacedDigit()
                RefreshButton()
            }
            hero
                .padding(.horizontal, WTheme.inset)
                .padding(.vertical, 11)
            Rectangle().fill(WTheme.divider).frame(height: 1)
            HStack {
                Text("name")
                Spacer()
                Text("load / value")
            }
            .font(WTheme.mono(8, .medium))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(WTheme.inkTertiary)
            .padding(.horizontal, WTheme.inset)
            .padding(.top, 7)
            .padding(.bottom, 1)
            if board.entries.isEmpty {
                EmptyBoard()
            } else {
                RowStack(entries: Array(board.entries.prefix(rowLimit)), slots: rowLimit)
                    .padding(.bottom, 4)
            }
        }
        .widgetURL(URL(string: "openquota://"))
    }

    private var rowLimit: Int { board.budgetFraction == nil ? 7 : 6 }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.heroFigure)
                        .font(WTheme.mono(28, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(board.heroCaption)
                        .font(WTheme.mono(9))
                        .foregroundStyle(WTheme.inkTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if let today = board.todaySpend {
                        stat("today", Format.currency(today))
                    }
                    if let projected = board.projectedSpend {
                        stat("→ eom", Format.currency(projected))
                    }
                    if board.todaySpend == nil, board.projectedSpend == nil {
                        stat("up", "\(board.entries.count)")
                    }
                }
            }
            if let fraction = board.budgetFraction, let budget = board.budget {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("budget")
                        Spacer()
                        Text("\(WTheme.percent(fraction)) of \(Format.currency(budget))")
                            .monospacedDigit()
                            .foregroundStyle(WTheme.severity(fraction, calm: WTheme.inkSecondary))
                    }
                    .font(WTheme.mono(9))
                    .foregroundStyle(WTheme.inkSecondary)
                    Meter(fraction: fraction, height: 8, segment: 5, gap: 2)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(WTheme.inkTertiary)
            Text(value).foregroundStyle(WTheme.ink).monospacedDigit()
        }
        .font(WTheme.mono(10, .medium))
        .lineLimit(1)
    }
}

/// Table rows sharing the available height evenly, with hairlines between
/// them; empty slots keep the rhythm when fewer accounts are connected.
struct RowStack: View {
    let entries: [WidgetEntry]
    let slots: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { RowDivider() }
                TableRow(entry: entry)
            }
            ForEach(0..<max(slots - entries.count, 0), id: \.self) { _ in
                Color.clear.frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Lock Screen accessories

/// Inline: one line, the whole board compressed.
struct InlineAccessory: View {
    let board: WidgetBoard

    var body: some View {
        if let top = board.byLoad.first, let fraction = top.fraction {
            Text("\(top.nickname.lowercased()) \(WTheme.percent(fraction)) · \(board.entries.count) accts")
        } else if let total = board.usdTotal {
            Text("\(Format.currency(total)) left · \(board.entries.count) accts")
        } else {
            Text("openquota · \(board.entries.count) accts")
        }
    }
}

/// Circular: the most loaded account as a capacity ring, or total credit.
struct CircularAccessory: View {
    let board: WidgetBoard

    var body: some View {
        if let top = board.byLoad.first, let fraction = top.fraction {
            Gauge(value: min(max(fraction, 0), 1)) {
                Text(top.nickname.prefix(3).uppercased())
            } currentValueLabel: {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(WTheme.mono(14, .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text(board.usdTotal.map(Format.compactCurrency) ?? "\(board.entries.count)")
                    .font(WTheme.mono(14, .semibold))
                    .minimumScaleFactor(0.6)
                    .padding(4)
            }
        }
    }
}

/// Rectangular: the two most loaded accounts, each with a meter.
struct RectangularAccessory: View {
    let board: WidgetBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(board.byLoad.prefix(2)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.nickname.lowercased())
                            .font(WTheme.mono(11, .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(entry.fraction.map(WTheme.percent) ?? entry.headlineText ?? "—")
                            .font(WTheme.mono(11, .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if let fraction = entry.fraction {
                        Meter(fraction: fraction, height: 5, segment: 3, gap: 1.5)
                    }
                }
            }
            if board.entries.isEmpty {
                Text("openquota · no accounts")
                    .font(WTheme.mono(11))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        AccountEntry(date: Date(), board: BoardTimeline.current.asOf(Date()), intent: configuration)
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<AccountEntry> {
        BoardTimeline.timeline { AccountEntry(date: $0, board: $1, intent: configuration) }
    }
}

// MARK: - All-providers widget

/// "All Providers": every connected account as a name, a figure and a meter.
/// Small stacks three; medium lays six out in two columns.
struct ProvidersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenQuotaProviders", provider: BoardProvider()) { entry in
            ProvidersView(board: entry.board)
        }
        .configurationDisplayName("All Providers")
        .description("Every connected account with its limit meter.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct ProvidersView: View {
    @Environment(\.widgetFamily) private var family

    let board: WidgetBoard

    var body: some View {
        VStack(spacing: 0) {
            if family == .systemSmall {
                PanelHeader(title: "load", count: board.entries.count)
            } else {
                PanelHeader(title: "providers", count: board.entries.count) { RefreshButton() }
            }
            if board.entries.isEmpty {
                EmptyBoard()
            } else if family == .systemSmall {
                column(Array(board.entries.prefix(3)), slots: 3)
                    .padding(.horizontal, WTheme.inset)
            } else {
                let shown = Array(board.entries.prefix(6))
                HStack(alignment: .top, spacing: 16) {
                    column(Array(shown.prefix(3)), slots: 3)
                    column(Array(shown.dropFirst(3)), slots: 3)
                }
                .padding(.horizontal, WTheme.inset)
            }
        }
        .fontDesign(.monospaced)
        .widgetCanvas()
        .widgetURL(URL(string: "openquota://"))
    }

    private func column(_ entries: [WidgetEntry], slots: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                StackRow(entry: entry)
                    .frame(maxHeight: .infinity)
            }
            ForEach(0..<max(slots - entries.count, 0), id: \.self) { _ in
                Color.clear.frame(maxHeight: .infinity)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Single-account widget

/// Per-account widget: configurable in the edit sheet, one account's
/// headline and its limit windows as meters.
struct AccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenQuotaAccount",
                              intent: SelectAccountIntent.self,
                              provider: AccountIntentProvider()) { entry in
            AccountConfigView(board: entry.board,
                              selected: entry.intent?.account?.id)
        }
        .configurationDisplayName("Single Account")
        .description("One connected account you pick — headline and limit meters.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
        ])
        .contentMarginsDisabled()
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
                case .systemMedium: AccountMedium(entry: entry)
                case .accessoryInline:
                    Text("\(entry.nickname.lowercased()) \(entry.fraction.map(WTheme.percent) ?? entry.headlineText ?? "—")")
                case .accessoryCircular: AccountCircular(entry: entry)
                default: AccountRectangular(entry: entry)
                }
            } else {
                EmptyBoard()
            }
        }
        .fontDesign(.monospaced)
        .widgetCanvas()
    }
}

/// A limit window as a labelled meter: `5h window ····· 82%` over the bar,
/// with a live reset countdown when one is known.
struct WindowMeter: View {
    let window: WidgetWindow
    var height: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(window.title.lowercased())
                    .foregroundStyle(WTheme.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(window.valueText)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(WTheme.severity(window.fraction, calm: WTheme.ink))
                    .lineLimit(1)
            }
            .font(WTheme.mono(9))
            Meter(fraction: window.fraction, height: height, segment: 4, gap: 2)
        }
    }
}

/// Live `↻ 1:42:10` countdown to a reset.
struct ResetCountdown: View {
    let date: Date

    var body: some View {
        if date > Date() {
            HStack(spacing: 3) {
                Text("↻")
                Text(timerInterval: Date()...date, countsDown: true)
                    .monospacedDigit()
            }
            .font(WTheme.mono(8.5))
            .foregroundStyle(WTheme.inkTertiary)
            .lineLimit(1)
        }
    }
}

/// Small single-account: header with the provider mark, the headline figure,
/// and the top limit window as a full-width meter.
struct AccountSmall: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountHeader(entry: entry)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.headlineText ?? "—")
                    .font(WTheme.mono(22, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(entry.caption)
                    .font(WTheme.mono(9))
                    .foregroundStyle(WTheme.inkTertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let window = entry.windows?.first {
                    WindowMeter(window: window, height: 9)
                    if let reset = window.resetsAt {
                        ResetCountdown(date: reset).padding(.top, 4)
                    }
                } else if let fraction = entry.fraction {
                    Meter(fraction: fraction, height: 9, segment: 4, gap: 2)
                } else {
                    Text(entry.providerName.lowercased())
                        .font(WTheme.mono(9))
                        .foregroundStyle(WTheme.inkTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, WTheme.inset)
            .padding(.top, 9)
            .padding(.bottom, 13)
        }
        .widgetURL(entry.deepLink)
    }
}

/// Medium single-account: headline on the left, up to three limit windows
/// as meters on the right.
struct AccountMedium: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(spacing: 0) {
            AccountHeader(entry: entry, showsRefresh: true)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.headlineText ?? "—")
                        .font(WTheme.mono(24, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(entry.valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(entry.caption)
                        .font(WTheme.mono(9))
                        .foregroundStyle(WTheme.inkTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let pace = entry.paceText {
                        Text(pace.lowercased())
                            .font(WTheme.mono(8.5))
                            .foregroundStyle(WTheme.inkSecondary)
                            .lineLimit(2)
                    }
                    if let reset = entry.resetsAt {
                        ResetCountdown(date: reset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    let windows = Array((entry.windows ?? []).prefix(3))
                    if windows.isEmpty {
                        if let fraction = entry.fraction {
                            Meter(fraction: fraction, height: 9, segment: 4, gap: 2)
                        } else {
                            Text("no limit reported")
                                .font(WTheme.mono(9))
                                .foregroundStyle(WTheme.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    } else {
                        ForEach(windows) { window in
                            WindowMeter(window: window)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        ForEach(0..<(3 - windows.count), id: \.self) { _ in
                            Color.clear.frame(maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, WTheme.inset)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .widgetURL(entry.deepLink)
    }
}

/// Panel header naming the account, with its provider's mark.
struct AccountHeader: View {
    let entry: WidgetEntry
    var showsRefresh = false

    var body: some View {
        PanelHeader(title: entry.nickname) {
            if showsRefresh {
                Text(entry.providerName)
                    .tracking(0)
                    .textCase(.lowercase)
                    .foregroundStyle(WTheme.inkTertiary)
                    .lineLimit(1)
                RefreshButton()
            } else {
                TintMark(hex: entry.tintHex)
            }
        }
    }
}

/// Circular Lock Screen accessory: the headline load as a capacity ring.
struct AccountCircular: View {
    let entry: WidgetEntry

    var body: some View {
        if let fraction = entry.fraction {
            Gauge(value: min(max(fraction, 0), 1)) {
                Text(entry.nickname.prefix(3).uppercased())
            } currentValueLabel: {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(WTheme.mono(14, .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text(entry.headlineText ?? "—")
                    .font(WTheme.mono(13, .semibold))
                    .minimumScaleFactor(0.5)
                    .padding(4)
            }
        }
    }
}

/// Rectangular Lock Screen accessory: name and figure, the meter, and the
/// reset countdown.
struct AccountRectangular: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(entry.nickname.lowercased())
                    .font(WTheme.mono(11, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.headlineText ?? "—")
                    .font(WTheme.mono(11, .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let window = entry.windows?.first {
                Meter(fraction: window.fraction, height: 6, segment: 3, gap: 1.5)
                HStack(spacing: 4) {
                    Text(window.title.lowercased()).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(WTheme.percent(window.fraction)).monospacedDigit()
                }
                .font(WTheme.mono(9))
            } else if let fraction = entry.fraction {
                Meter(fraction: fraction, height: 6, segment: 3, gap: 1.5)
            } else {
                Text(entry.caption).font(WTheme.mono(9)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Canvas

extension View {
    /// The widget canvas: the app's plain card surface — no tint wash.
    func widgetCanvas() -> some View {
        containerBackground(for: .widget) { WTheme.surface }
    }
}

// MARK: - Model helpers

extension WidgetBoard {
    /// The board as it stands at `date`: any window whose reset has passed
    /// reads as freshly reset rather than showing its old load.
    func asOf(_ date: Date) -> WidgetBoard {
        var copy = self
        copy.entries = entries.map { $0.asOf(date) }
        return copy
    }

    /// Accounts with a limit first, most loaded first; the rest keep their order.
    var byLoad: [WidgetEntry] {
        let limited = entries.filter { $0.fraction != nil }
            .sorted { ($0.fraction ?? 0) > ($1.fraction ?? 0) }
        return limited + entries.filter { $0.fraction == nil }
    }

    var heroTitle: String {
        if usdTotal != nil { return "credit" }
        if monthSpend != nil { return "spend · mtd" }
        return "openquota"
    }

    var heroFigure: String {
        if let usdTotal { return Format.currency(usdTotal) }
        if let monthSpend { return Format.currency(monthSpend) }
        if let top = byLoad.first { return top.headlineText ?? "—" }
        return "—"
    }

    var heroCaption: String {
        if usdTotal != nil {
            if let monthSpend { return "prepaid left · \(Format.currency(monthSpend)) mtd" }
            return "prepaid left"
        }
        if monthSpend != nil { return "spent this month" }
        return byLoad.first.map { $0.nickname.lowercased() } ?? "no data yet"
    }

    /// One-clause caption for the narrow small widget.
    var shortCaption: String {
        if usdTotal != nil { return "prepaid left" }
        if monthSpend != nil { return "spent this month" }
        return byLoad.first.map { $0.nickname.lowercased() } ?? "no data yet"
    }

    var budgetFraction: Double? {
        guard let budget, budget > 0, let monthSpend else { return nil }
        return monthSpend / budget
    }
}

extension WidgetEntry {
    func asOf(_ date: Date) -> WidgetEntry {
        var copy = self
        if let reset = resetsAt, reset <= date, fraction != nil {
            copy.fraction = 0
            copy.headlineText = "reset"
            copy.resetsAt = nil
        }
        copy.windows = windows?.map { window in
            guard let reset = window.resetsAt, reset <= date else { return window }
            var fresh = window
            fresh.fraction = 0
            fresh.valueText = "reset"
            fresh.resetsAt = nil
            return fresh
        }
        return copy
    }

    var deepLink: URL {
        URL(string: "openquota://account/\(id.uuidString)")!
    }

    /// Ink while healthy, amber/red once the headline allowance is at stake.
    var valueColor: Color {
        fraction.map { WTheme.severity($0, calm: WTheme.ink) } ?? WTheme.ink
    }

    /// `credits left · openrouter` — what the headline figure means.
    var caption: String {
        let title = (headlineTitle ?? "").lowercased()
        let provider = providerName.lowercased()
        if title.isEmpty { return provider }
        if provider == nickname.lowercased() { return title }
        return "\(title) · \(provider)"
    }
}

extension Format {
    /// `$1.2k`-style figure for the tiny circular accessory.
    static func compactCurrency(_ amount: Double) -> String {
        amount >= 1000 ? String(format: "$%.1fk", amount / 1000) : String(format: "$%.0f", amount)
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
