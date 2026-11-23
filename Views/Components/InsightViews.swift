import SwiftUI

// MARK: - Budget

/// `budget $2,000 ▮▮▮▮▮▮▯▯ 88%` with the month-end projection underneath.
/// Calm ink while on track, amber when the projection overshoots, coral once
/// the budget is spent.
struct BudgetLine: View {
    let status: BudgetStatus
    var label = "budget"

    private var color: Color {
        if status.isOver { return Theme.critical }
        if status.willExceed || status.fraction >= Theme.watchFraction { return Theme.watch }
        return Theme.inkSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text("\(label) \(Format.currency(status.budget))")
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                SegmentedMeter(fraction: min(status.fraction, 1), height: 6, segment: 4, gap: 1.5)
                Text("\(Int((status.fraction * 100).rounded()))%")
                    .foregroundStyle(status.isOver || status.fraction >= Theme.watchFraction ? color : Theme.ink)
                    .monospacedDigit()
            }
            Text(status.isOver
                 ? "# over by \(Format.currency(-status.remaining)) · \(status.projectionText)"
                 : "# \(Format.currency(status.remaining)) left · \(status.projectionText)")
                .foregroundStyle(status.willExceed ? color : Theme.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.mono(.caption))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Format.currency(status.budget)), \(Int((status.fraction * 100).rounded())) percent used, \(status.projectionText)")
    }
}

// MARK: - Spike

/// `▲ today $42.10 · 3.1× usual` with a pulsing amber LED.
struct SpikeLine: View {
    let spike: SpendSpike

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            PulseDot(color: Theme.watch, size: 6, period: 1.4)
            Text("▲ today \(Format.currency(spike.today))")
                .foregroundStyle(Theme.watch)
                .fontWeight(.semibold)
            Text("· \(spike.ratioText)")
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
        }
        .font(.mono(.caption))
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs + 2)
        .background(Theme.watch.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.tag + 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spend spike: \(Format.currency(spike.today)) today, \(spike.ratioText)")
    }
}

// MARK: - Tags

/// `by tag  work $1,612 · personal $41 · other $112`.
struct TagSplit: View {
    let rows: [(tag: String, amount: Double)]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text("by tag").foregroundStyle(Theme.inkTertiary)
            ViewThatFits(in: .horizontal) {
                line(rows)
                line(Array(rows.prefix(2)))
            }
        }
        .font(.mono(.caption))
    }

    private func line(_ rows: [(tag: String, amount: Double)]) -> some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Text("·").foregroundStyle(Theme.inkTertiary) }
                Text("#\(row.tag)").foregroundStyle(Theme.inkSecondary)
                Text(Format.currency(row.amount)).foregroundStyle(Theme.ink).monospacedDigit()
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Month spend grouped by tag, untagged accounts as "other".
    static func rows(_ summary: BoardSummary) -> [(tag: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for share in summary.spendShares {
            totals[share.account.tag ?? "other", default: 0] += share.amount
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}

// MARK: - Heatmap

/// Contribution-graph of daily spend: columns are weeks (newest on the
/// right), rows are weekdays, four shades of ink from quiet to busy.
/// Monochrome like the gauges; today turns amber on a spike day.
struct SpendHeatmap: View {
    let days: [DaySpend]
    var weeks = 16
    var spikeToday = false
    var hidesAmounts = false
    var cell: CGFloat = 15
    var gap: CGFloat = 3

    @State private var selected: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let calendar = Calendar.current

    /// Columns of 7 dates, oldest week first, ending with this week.
    private var columns: [[Date]] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let thisWeekStart = calendar.date(byAdding: .day, value: -offset, to: today)!
        return (0..<weeks).reversed().map { back in
            let start = calendar.date(byAdding: .day, value: -7 * back, to: thisWeekStart)!
            return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        }
    }

    private var amounts: [Date: Double] {
        Dictionary(days.map { (calendar.startOfDay(for: $0.day), $0.amount) }, uniquingKeysWith: +)
    }

    /// Labels for the first, third and fifth row; blank between, like a
    /// contribution graph.
    private var rowLabels: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { $0 % 2 == 0 ? symbols[(calendar.firstWeekday - 1 + $0) % 7].lowercased() : "" }
    }

    /// Four shades by share of the busiest day.
    static func level(_ amount: Double?, top: Double) -> Double {
        guard let amount, amount > 0.005 else { return 0 }
        switch amount / top {
        case ..<0.25: return 0.22
        case ..<0.5: return 0.42
        case ..<0.75: return 0.66
        default: return 1
        }
    }

    var body: some View {
        let amounts = amounts
        let columns = columns
        let top = max(amounts.values.max() ?? 0, 0.01)
        let today = calendar.startOfDay(for: Date())
        let total = columns.flatMap { $0 }.compactMap { amounts[$0] }.reduce(0, +)

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(Array(rowLabels.enumerated()), id: \.offset) { _, label in
                        Text(label).frame(height: cell)
                    }
                }
                .font(.mono(size: 9))
                .foregroundStyle(Theme.inkTertiary)

                HStack(spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { col, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { row, day in
                                square(day, amount: amounts[day], top: top, today: today,
                                       delay: Double(col) * 0.025 + Double(row) * 0.01)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: Theme.Space.s) {
                Group {
                    if let selected, let amount = amounts[selected] ?? (selected <= today ? 0 : nil) {
                        Text(selected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).lowercased())
                            .foregroundStyle(Theme.inkSecondary)
                        Text(hidesAmounts ? "$•••" : Format.currency(amount))
                            .foregroundStyle(Theme.ink).fontWeight(.semibold)
                    } else {
                        Text("\(weeks)w").foregroundStyle(Theme.inkTertiary)
                        Text(hidesAmounts ? "$•••" : Format.currency(total))
                            .foregroundStyle(Theme.ink).fontWeight(.semibold)
                    }
                }
                .contentTransition(.numericText())
                Spacer(minLength: Theme.Space.s)
                legend
            }
            .font(.mono(.caption))
            .monospacedDigit()
            .lineLimit(1)
        }
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.settle) { shown = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily spend, last \(weeks) weeks: \(Format.currency(total)) in total")
    }

    private func square(_ day: Date, amount: Double?, top: Double, today: Date, delay: Double) -> some View {
        let future = day > today
        let level = Self.level(amount, top: top)
        let isToday = day == today
        let fill: Color = isToday && spikeToday ? Theme.watch : Theme.gauge
        let isSelected = selected == day
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(future ? Color.clear : Theme.track)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill.opacity(level))
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
                    .animation(.settle.delay(delay), value: shown)
            }
            .overlay {
                if (isToday && !future) || isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(isSelected ? Theme.ink : Theme.brand.opacity(0.7), lineWidth: 1)
                }
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !future else { return }
                withAnimation(.snappy) { selected = selected == day ? nil : day }
            }
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("less").foregroundStyle(Theme.inkTertiary)
            ForEach([0.0, 0.22, 0.42, 0.66, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.track)
                    .overlay(RoundedRectangle(cornerRadius: 2).fill(Theme.gauge.opacity(level)))
                    .frame(width: 9, height: 9)
            }
            Text("more").foregroundStyle(Theme.inkTertiary)
        }
        .font(.mono(.caption2))
    }
}

// MARK: - Sparkline

/// Tiny 7-day trend: a single ink stroke ending in a dot.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.inkSecondary

    var body: some View {
        GeometryReader { proxy in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
            let point: (Int) -> CGPoint = { i in
                CGPoint(x: CGFloat(i) * step,
                        y: proxy.size.height * (1 - CGFloat((values[i] - lo) / span)))
            }
            ZStack(alignment: .topLeading) {
                Path { path in
                    guard !values.isEmpty else { return }
                    path.move(to: point(0))
                    for i in values.indices.dropFirst() { path.addLine(to: point(i)) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                if let last = values.indices.last {
                    Circle().fill(color).frame(width: 3, height: 3)
                        .position(point(last))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Peak hours

/// 24 bars, one per hour of day, with the peak drawn in ink and the rest
/// on the track — `busiest 14:00–15:00 · quietest 03:00` underneath.
struct PeakHoursChart: View {
    let peak: PeakHours

    var body: some View {
        let top = max(peak.shares.max() ?? 1, 0.0001)
        let now = Calendar.current.component(.hour, from: Date())
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(hour == peak.peak ? Theme.gauge : Theme.gauge.opacity(0.18 + 0.5 * peak.shares[hour] / top))
                        .frame(height: max(3, 54 * peak.shares[hour] / top))
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            if hour == now {
                                Rectangle().fill(Theme.brand).frame(height: 2).offset(y: 5)
                            }
                        }
                }
            }
            .frame(height: 54, alignment: .bottom)
            HStack {
                Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("23")
            }
            .font(.mono(.caption2))
            .foregroundStyle(Theme.inkTertiary)
            Text(peak.text)
                .font(.mono(.caption))
                .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage by hour of day: \(peak.text)")
    }
}

// MARK: - Budget editor

/// Small sheet to set or clear a monthly USD budget.
struct BudgetEditor: View {
    let title: String
    let current: Double?
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var value: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("monthly budget · usd").eyebrow()
                HStack(spacing: Theme.Space.xs) {
                    Text("$").foregroundStyle(Theme.inkTertiary)
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                }
                .font(.mono(size: Theme.TypeScale.display, weight: .semibold))
                .padding(Theme.Space.l)
                .card()
                Text("# alerts at 80% and when spent. the projection assumes the rest of the month runs at the pace so far.")
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.inkTertiary)
                HStack(spacing: Theme.Space.s) {
                    ForEach([50.0, 200, 500, 1000], id: \.self) { preset in
                        Button("$\(Int(preset))") { text = "\(Int(preset))" }
                            .buttonStyle(.glass)
                            .font(.mono(.caption, weight: .medium))
                    }
                }
                Spacer()
            }
            .padding(Theme.Spacing.page)
            .background { CanvasBackground() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(value.flatMap { $0 > 0 ? $0 : nil }); dismiss() }
                        .disabled(value == nil && !text.isEmpty)
                }
                if current != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Remove budget", role: .destructive) { onSave(nil); dismiss() }
                    }
                }
            }
        }
        .onAppear {
            if let current { text = current.rounded() == current ? "\(Int(current))" : String(format: "%.2f", current) }
            focused = true
        }
        .presentationDetents([.medium])
        .fontDesign(.monospaced)
    }
}

// MARK: - Recap

/// The share card: a terminal window with the month in figures and its
/// calendar. Fixed size so the exported image is consistent.
struct RecapCard: View {
    let recap: MonthRecap
    var hideAmounts = false

    private func money(_ value: Double?) -> String {
        guard let value else { return "—" }
        return hideAmounts ? "$•••" : Format.currency(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: 6) {
                ForEach(["FF5F57", "FEBC2E", "28C840"], id: \.self) {
                    Circle().fill(Color(hex: $0)).frame(width: 9, height: 9)
                }
                Spacer()
                Text("openquota — recap").foregroundStyle(Theme.inkTertiary)
                Spacer()
                Color.clear.frame(width: 39, height: 1)
            }
            .font(.mono(.caption2))

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: 0) {
                    Text("❯ ").foregroundStyle(Theme.brand)
                    Text("recap --month \(recap.month.formatted(.dateTime.month(.abbreviated).year()).lowercased())")
                        .foregroundStyle(Theme.ink)
                }
                .font(.mono(.footnote, weight: .semibold))
                Text(money(recap.total))
                    .font(.mono(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("# spent across \(recap.accounts) providers")
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.inkTertiary)
            }

            Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.s) {
                GridRow {
                    Text("top").foregroundStyle(Theme.inkTertiary)
                    Text(recap.topName?.lowercased() ?? "—").foregroundStyle(Theme.ink).lineLimit(1)
                    Text(money(recap.topAmount)).foregroundStyle(Theme.inkSecondary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("peak").foregroundStyle(Theme.inkTertiary)
                    Text(recap.busiestDay.map { $0.day.formatted(.dateTime.weekday(.abbreviated).day()).lowercased() } ?? "—")
                        .foregroundStyle(Theme.ink)
                    Text(money(recap.busiestDay?.amount)).foregroundStyle(Theme.inkSecondary)
                }
                GridRow {
                    Text("active").foregroundStyle(Theme.inkTertiary)
                    Text("\(recap.activeDays) days").foregroundStyle(Theme.ink)
                    Text("")
                }
            }
            .font(.mono(.footnote))
            .monospacedDigit()

            SpendHeatmap(days: recap.recentDays, weeks: 14, hidesAmounts: hideAmounts, cell: 16)
                .allowsHitTesting(false)

            HStack {
                Text("every ai bill, one glance")
                Spacer()
                Text("openquota")
                    .fontWeight(.semibold)
            }
            .font(.mono(.caption2))
            .foregroundStyle(Theme.inkTertiary)
        }
        .padding(Theme.Space.xl)
        .frame(width: 360)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { GlassRim(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
        .padding(Theme.Space.xl)
        .background(Theme.canvas)
    }
}

/// Preview of the recap with a hide-amounts switch and a share button.
struct RecapSheet: View {
    let recap: MonthRecap

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.oledBlack) private var oled
    @State private var hideAmounts = false
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    RecapCard(recap: recap, hideAmounts: hideAmounts)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .elevated()
                    Toggle("Hide amounts", isOn: $hideAmounts)
                        .font(.mono(.subheadline))
                        .tint(Theme.brand)
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.vertical, Theme.Space.m)
                        .card(padding: 0)
                }
                .padding(Theme.Spacing.page)
            }
            .background { CanvasBackground() }
            .navigationTitle("Monthly recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let image {
                        ShareLink(item: image, preview: SharePreview("Open Quota recap", image: image)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear(perform: render)
            .onChange(of: hideAmounts) { render() }
        }
        .fontDesign(.monospaced)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: RecapCard(recap: recap, hideAmounts: hideAmounts)
            .environment(\.colorScheme, scheme)
            .environment(\.oledBlack, oled)
            .fontDesign(.monospaced))
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}
