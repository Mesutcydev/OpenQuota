import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var showingRecap = false
    @State private var editingBudget = false

    private var summary: BoardSummary {
        BoardSummary(
            accounts: model.accounts,
            snapshots: model.snapshots,
            errors: model.states.compactMapValues(\.errorMessage))
    }

    /// Worst state on the board; tints the ambient lights.
    private var mood: Theme.Level {
        summary.attention.reduce(.calm) { worst, item in
            max(worst, item.fraction.map(Theme.level) ?? .critical)
        }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.overviewPath) {
            Group {
                if model.accounts.isEmpty {
                    EmptyStateView { router.showingConnect = true }
                } else {
                    content
                }
            }
            .background {
                ZStack {
                    CanvasBackground()
                    AmbientLights(mood: mood)
                }
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in
                AccountDetailView(accountID: id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // The page draws its own prompt-line header; keep the bar title empty.
        ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        if !model.accounts.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: model.isRefreshingAll)
                }
                .disabled(model.isRefreshingAll)
                .accessibilityLabel("Refresh all")
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button { router.showingConnect = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Connect a provider")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.stack) {
                PromptHeader(summary: summary, lastRefreshedAt: model.lastRefreshedAt,
                             refreshing: model.isRefreshingAll)
                    .padding(.bottom, Theme.Space.s)
                    .entrance(0)

                SpendPanel(summary: summary,
                           budget: model.budgetStatus(spent: summary.monthSpend),
                           spike: model.spike,
                           tagRows: model.tags.isEmpty ? [] : TagSplit.rows(summary),
                           onRecap: { showingRecap = true },
                           onBudget: { editingBudget = true })
                    .lightSweep(every: 7)
                    .runningRim()
                    .entrance(1)

                KPIRow(summary: summary)
                    .entrance(2)

                if !summary.attention.isEmpty {
                    AlertsPanel(items: summary.attention) { router.overviewPath = [$0] }
                        .entrance(3)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if model.dailySpend().count >= 2 {
                    Panel(title: "activity · 16w") {
                        SpendHeatmap(days: model.dailySpend(), spikeToday: model.spike != nil)
                            .padding(Theme.Spacing.card)
                    }
                    .entrance(4)
                }

                Panel(title: "providers", count: model.accounts.count) {
                    sortMenu
                } content: {
                    VStack(spacing: 0) {
                        ColumnHeader()
                        ForEach(model.sortedAccounts) { account in
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            NavigationLink(value: account.id) {
                                ProviderRow(
                                    account: account,
                                    state: model.state(for: account),
                                    snapshot: model.snapshot(for: account),
                                    trend: Trend.series(model.history[account.id] ?? []))
                            }
                            .buttonStyle(RowPressStyle())
                            .contextMenu { tileMenu(account) }
                        }
                    }
                }
                .entrance(5)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxxl)
            .animation(.settle, value: model.sortedAccounts.map(\.id))
            .animation(.settle, value: summary.attention.isEmpty)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refreshAll() }
        .sheet(isPresented: $showingRecap) {
            RecapSheet(recap: MonthRecap(summary: summary, days: model.dailySpend()))
        }
        .sheet(isPresented: $editingBudget) {
            @Bindable var model = model
            BudgetEditor(title: "Monthly budget", current: model.settings.monthlyBudget) {
                model.settings.monthlyBudget = $0
            }
        }
    }

    private var sortMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Sort", selection: $model.settings.sort) {
                ForEach(DashboardSort.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Text("sort: \(model.settings.sort.title.lowercased()) ▾")
                .font(.mono(.caption2, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityLabel("Sort providers")
    }

    @ViewBuilder
    private func tileMenu(_ account: Account) -> some View {
        Button {
            Task { await model.refresh(account) }
        } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        Button {
            router.overviewPath = [account.id]
        } label: { Label("Open", systemImage: "arrow.up.right") }
    }
}

// MARK: - Panel

/// Dashboard panel: a bordered box with a monospaced title bar.
struct Panel<Trailing: View, Content: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Text("▍").foregroundStyle(Theme.brand)
                Text(title)
                if let count { Text("[\(count)]").foregroundStyle(Theme.inkTertiary) }
                Spacer(minLength: Theme.Space.s)
                trailing
            }
            .eyebrow()
            .padding(.horizontal, Theme.Spacing.rowH)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.surfaceRaised.opacity(0.55))
            .accessibilityAddTraits(.isHeader)

            Rectangle().fill(Theme.divider).frame(height: 1)

            content
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay { GlassRim(shape: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)) }
        .elevated()
    }
}

extension Panel where Trailing == EmptyView {
    init(title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Header

/// `~/openquota ❯ overview▌` with a status line underneath.
struct PromptHeader: View {
    let summary: BoardSummary
    let lastRefreshedAt: Date?
    let refreshing: Bool

    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = Theme.TypeScale.title

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 0) {
                Text("~/openquota ").foregroundStyle(Theme.inkSecondary)
                Text("❯ ").foregroundStyle(Theme.brand)
                Text("overview").foregroundStyle(Theme.ink)
                BlinkingCursor()
            }
            .font(.mono(size: titleSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Overview")
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: Theme.Space.s) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).lowercased())
                Text("·")
                status
                Text("·")
                Text("\(summary.reporting)/\(summary.connected) up")
            }
            .font(.mono(.caption))
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var status: some View {
        if refreshing {
            HStack(spacing: Theme.Space.xs) {
                PulseDot(color: Theme.brand, size: 6, period: 0.8)
                SyncingLabel()
            }
            .foregroundStyle(Theme.brand)
        } else if let lastRefreshedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let stale = context.date.timeIntervalSince(lastRefreshedAt) > 3600
                HStack(spacing: Theme.Space.xs) {
                    PulseDot(color: stale ? Theme.watch : Color(hex: "3FBF7F"), size: 6)
                    Text("synced \(Format.relative(lastRefreshedAt, from: context.date))")
                }
            }
        } else {
            Text("not synced")
        }
    }
}

// MARK: - Spend

struct SpendPanel: View {
    let summary: BoardSummary
    var budget: BudgetStatus? = nil
    var spike: SpendSpike? = nil
    var tagRows: [(tag: String, amount: Double)] = []
    var onRecap: (() -> Void)? = nil
    var onBudget: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = Theme.TypeScale.display

    private var monthTag: String {
        Date().formatted(.dateTime.month(.abbreviated)).lowercased()
    }

    /// Top four spenders plus "other".
    private var rows: [(name: String, amount: Double)] {
        let shares = summary.spendShares
        var result = shares.prefix(4).map { ($0.account.nickname, $0.amount) }
        let rest = shares.dropFirst(4).reduce(0) { $0 + $1.amount }
        if rest > 0 { result.append(("other", rest)) }
        return result
    }

    var body: some View {
        Panel(title: summary.monthSpend != nil ? "spend · \(monthTag) mtd" : "credit") {
            if summary.monthSpend != nil, let onRecap {
                Button(action: onRecap) {
                    Text("recap ↗")
                        .font(.mono(.caption2, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityLabel("Monthly recap")
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(primaryFigure)
                        .font(.mono(size: figureSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if summary.excludesOtherCurrencies {
                        Text("# usd only; other currencies per provider")
                            .font(.mono(.caption2))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }

                if let spike { SpikeLine(spike: spike) }

                if let budget {
                    Button { onBudget?() } label: { BudgetLine(status: budget) }
                        .buttonStyle(.plain)
                } else if summary.monthSpend != nil, let onBudget {
                    Button(action: onBudget) {
                        Text("+ set a monthly budget")
                            .font(.mono(.caption))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if summary.monthSpend != nil, !rows.isEmpty {
                    breakdown
                }

                if tagRows.count >= 2 { TagSplit(rows: tagRows) }
            }
            .padding(Theme.Spacing.card)
        }
        .accessibilityElement(children: .contain)
    }

    private var breakdown: some View {
        let top = max(rows.map(\.amount).max() ?? 1, 0.0001)
        let total = max(rows.reduce(0) { $0 + $1.amount }, 0.0001)
        return Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    Text(row.name.lowercased())
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LiveBlockBar(fraction: row.amount / top, cells: 10, font: .mono(.caption2), showsSeverity: false,
                                 delay: 0.25 + Double(index) * 0.08)
                    Text("\(Int((row.amount / total * 100).rounded()))%")
                        .foregroundStyle(Theme.inkTertiary)
                        .gridColumnAlignment(.trailing)
                    Text(Format.currency(row.amount))
                        .foregroundStyle(Theme.ink)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.mono(.caption))
        .monospacedDigit()
    }

    private var primaryFigure: String {
        if let spend = summary.monthSpend { return Format.currency(spend) }
        if let credit = summary.creditLeft { return Format.currency(credit) }
        return "—"
    }
}

// MARK: - KPIs

struct KPIRow: View {
    let summary: BoardSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.grid) {
            tile("credit", summary.creditLeft.map { Format.currency($0) } ?? "—", note: "prepaid left")
            tile("up", "\(summary.reporting)/\(summary.connected)", note: "reporting",
                 led: summary.reporting == summary.connected ? Color(hex: "3FBF7F") : Theme.watch)
            tile("alerts", "\(summary.attention.count)",
                 note: summary.attention.isEmpty ? "all clear" : "need a look",
                 color: summary.attention.isEmpty ? Theme.healthy : Theme.watch,
                 led: summary.attention.isEmpty ? Color(hex: "3FBF7F") : Theme.watch)
        }
    }

    private func tile(_ label: String, _ value: String, note: String, color: Color = Theme.ink,
                      led: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Text(label).eyebrow()
                Spacer(minLength: 0)
                if let led { PulseDot(color: led, size: 5, period: led == Theme.watch ? 1.4 : 3) }
            }
            .padding(.bottom, Theme.Space.xxs)
            Text(value)
                .font(.mono(.title3, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(note)
                .font(.mono(.caption2))
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Space.m, radius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Alerts

/// Log-style list: `WARN openai (near cap)   94%`.
struct AlertsPanel: View {
    let items: [BoardSummary.Attention]
    let onOpen: (UUID) -> Void

    var body: some View {
        Panel(title: "alerts", count: items.count) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Theme.divider).frame(height: 1) }
                    Button { onOpen(item.account.id) } label: { line(item) }
                        .buttonStyle(RowPressStyle())
                }
            }
        }
    }

    private func line(_ item: BoardSummary.Attention) -> some View {
        let isError = item.fraction == nil
        let level = item.fraction.map(Theme.level) ?? .critical
        let color = isError ? Theme.critical : Theme.color(for: level)
        let tag = isError ? "ERR " : (level == .critical ? "CRIT" : "WARN")

        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(tag)
                .font(.mono(.caption2, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.xxs)
                .background(color.opacity(Theme.Wash.dark), in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(item.account.nickname.lowercased())
                    .font(.mono(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(detail(item))
                    .font(.mono(.caption2))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            if let fraction = item.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.mono(.callout, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            Text("›")
                .font(.mono(.callout))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, Theme.Spacing.rowH)
        .padding(.vertical, Theme.Spacing.rowV)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ item: BoardSummary.Attention) -> String {
        if let error = item.error { return error.lowercased() }
        if let reset = item.metric?.resetsAt, let countdown = Format.countdown(to: reset) {
            return "resets in \(countdown)"
        }
        return item.metric?.title.lowercased() ?? ""
    }
}

// MARK: - Providers table

private struct ColumnHeader: View {
    var body: some View {
        HStack {
            Text("name")
            Spacer()
            Text("value / load")
        }
        .font(.mono(.caption2, weight: .medium))
        .textCase(.uppercase)
        .foregroundStyle(Theme.inkTertiary)
        .padding(.horizontal, Theme.Spacing.rowH)
        .padding(.vertical, Theme.Space.s)
    }
}

/// One provider in the table: identity on the left, figure and block gauge
/// on the right.
struct ProviderRow: View {
    let account: Account
    let state: AccountState
    let snapshot: UsageSnapshot?
    var trend: [Double] = []

    private var descriptor: ProviderDescriptor {
        ProviderRegistry.descriptor(id: account.providerID)
    }

    private var subtitle: String {
        if let error = state.errorMessage, snapshot?.headline == nil { return "err: \(error.lowercased())" }
        var parts = [descriptor.name.lowercased()]
        if let tag = account.tag { parts.insert("#\(tag)", at: 0) }
        if let headline = snapshot?.headline {
            if let reset = headline.resetsAt, let countdown = Format.countdown(to: reset) {
                parts.append("↻ \(countdown)")
            } else {
                parts.append(headline.title.lowercased())
            }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ProviderGlyph(descriptor: descriptor, size: Theme.Glyph.row)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(account.nickname)
                    .font(.mono(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.mono(.caption2))
                    .foregroundStyle(state.errorMessage != nil && snapshot?.headline == nil
                                     ? Theme.critical : Theme.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.s)

            if trend.count >= 3 {
                Sparkline(values: trend, color: Theme.inkTertiary)
                    .frame(width: 34, height: 16)
            }

            trailing
        }
        .padding(.horizontal, Theme.Spacing.rowH)
        .padding(.vertical, Theme.Spacing.rowV)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var trailing: some View {
        if state.isLoading && snapshot == nil {
            Text("loading…")
                .font(.mono(.caption2))
                .foregroundStyle(Theme.inkTertiary)
        } else if let headline = snapshot?.headline {
            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.xs) {
                    if state.errorMessage != nil {
                        Text("!").foregroundStyle(Theme.critical)
                    }
                    Text(MetricText.value(headline))
                        .foregroundStyle(headline.fraction.map { Theme.severity($0, tint: Theme.ink) } ?? Theme.ink)
                        .contentTransition(.numericText())
                }
                .font(.mono(.callout, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                if let fraction = headline.fraction {
                    LiveBlockBar(fraction: fraction, cells: 10, font: .mono(.caption2), delay: 0.35)
                } else if let note = limitNote(headline) {
                    Text(note)
                        .font(.mono(.caption2))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }
            }
        } else if state.errorMessage != nil {
            Text("ERR")
                .font(.mono(.caption2, weight: .bold))
                .foregroundStyle(Theme.critical)
        }
    }

    private func limitNote(_ metric: UsageMetric) -> String? {
        if let limit = metric.limit, metric.unit != .percent {
            return "of \(Format.value(limit, unit: metric.unit, currencyCode: metric.currencyCode))"
        }
        return metric.title.lowercased()
    }

    private var accessibility: String {
        if let headline = snapshot?.headline {
            var text = MetricText.accessibility(headline, name: account.nickname)
            if state.errorMessage != nil { text += ". Last refresh failed; showing previous reading." }
            return text
        }
        if let error = state.errorMessage { return "\(account.nickname), error: \(error)" }
        return "\(account.nickname), loading"
    }
}

/// Row highlight on press, like a native list row.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.fillSubtle.opacity(configuration.isPressed ? 1 : 0))
            .animation(.press, value: configuration.isPressed)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let onConnect: () -> Void

    private let showcase = ["openai", "anthropic", "openrouter", "deepseek", "elevenlabs", "zai", "mistral", "fal"]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                ZStack {
                    ForEach(Array(showcase.enumerated()), id: \.offset) { index, id in
                        let angle = Double(index) / Double(showcase.count) * 2 * .pi
                        ProviderGlyph(descriptor: ProviderRegistry.descriptor(id: id), size: Theme.Glyph.hero)
                            .offset(x: cos(angle) * 92, y: sin(angle) * 92)
                    }
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: Theme.TypeScale.display, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                        .frame(width: 96, height: 96)
                        .background(Theme.surface, in: .circle)
                        .overlay { GlassRim(shape: Circle()) }
                }
                .frame(height: 250)
                .padding(.top, Theme.Space.xl)
                .accessibilityHidden(true)

                VStack(spacing: Theme.Space.s) {
                    Text("Every AI bill, one glance")
                        .font(.mono(.title2, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("Connect an API key to see credits, spend and rate limits. "
                       + "Keys stay in this iPhone’s Keychain.")
                        .font(.body)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Space.xxl)

                Button(action: onConnect) {
                    Label("Connect a provider", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.s)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, Theme.Space.xxl)

                Text("\(ProviderRegistry.all.count) providers supported")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Space.xxxl)
        }
    }
}
