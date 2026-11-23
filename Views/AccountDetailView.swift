import SwiftUI
import Charts

struct AccountDetailView: View {
    let accountID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmingRemove = false
    @State private var replacingKey = false
    @State private var keyHint: String?
    @State private var liveActivityOn = false
    @State private var editingBudget = false
    @State private var editingTag = false
    @State private var draftTag = ""

    var body: some View {
        if let account = model.account(id: accountID) {
            content(account)
        } else {
            ContentUnavailableView("Account removed", systemImage: "trash",
                                   description: Text("This account is no longer connected."))
        }
    }

    private func content(_ account: Account) -> some View {
        let descriptor = ProviderRegistry.descriptor(id: account.providerID)
        let state = model.state(for: account)
        let snapshot = model.snapshot(for: account)
        let points = model.history[account.id] ?? []

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                AccountHero(account: account, descriptor: descriptor, state: state, snapshot: snapshot,
                            pace: model.pace(for: account))

                if let message = state.errorMessage {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Callout(text: message, level: .critical)
                        HStack {
                            Button("Try again") { Task { await model.refresh(account) } }
                                .buttonStyle(.glass)
                            if descriptor.webSignIn != nil {
                                Button("Sign in again") { replacingKey = true }
                                    .buttonStyle(.glass)
                            } else if message.lowercased().contains("key") {
                                Button("Replace key") { replacingKey = true }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                }

                if points.count >= 2 {
                    HistoryChart(points: points, tint: descriptor.tint,
                                 currencyCode: snapshot?.headline?.currencyCode,
                                 title: snapshot?.headline?.title ?? "History")
                }

                insights(account)

                if let snapshot, snapshot.metrics.count > 1 {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionHeader(title: "All figures")
                        VStack(spacing: 0) {
                            ForEach(Array(snapshot.metrics.enumerated()), id: \.element.id) { index, metric in
                                if index > 0 { Divider() }
                                MetricRow(metric: metric, tint: descriptor.tint)
                                    .padding(.vertical, Theme.Space.m)
                            }
                        }
                        .padding(.horizontal, Theme.Space.l)
                        .card(padding: 0)
                    }
                }

                if let notes = snapshot?.notes, !notes.isEmpty {
                    VStack(spacing: Theme.Space.s) {
                        ForEach(notes, id: \.self) { Callout(text: $0, level: .info) }
                    }
                }

                connection(account, descriptor: descriptor)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxxl)
        }
        .background { CanvasBackground() }
        .refreshable { await model.refresh(account) }
        .navigationTitle(account.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refresh(account) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: state.isLoading)
                }
                .accessibilityLabel("Refresh")
                .disabled(state.isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { draftName = account.nickname; renaming = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { draftTag = account.tag ?? ""; editingTag = true } label: {
                        Label(account.tag == nil ? "Add tag" : "Change tag", systemImage: "number")
                    }
                    if AppModel.monthToDate(snapshot ?? UsageSnapshot(accountID: account.id, fetchedAt: .now, metrics: [])) != nil {
                        Button { editingBudget = true } label: {
                            Label("Monthly budget", systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                        }
                    }
                    Button { replacingKey = true } label: {
                        if descriptor.webSignIn != nil {
                            Label("Sign in again", systemImage: "person.badge.key")
                        } else {
                            Label("Replace key", systemImage: "key")
                        }
                    }
                    if snapshot?.headline?.fraction != nil, LiveActivities.isAvailable {
                        if liveActivityOn {
                            Button {
                                LiveActivities.end(accountID: account.id)
                                liveActivityOn = false
                            } label: {
                                Label("Remove from Lock Screen", systemImage: "rectangle.badge.xmark")
                            }
                        } else {
                            Button {
                                if let snapshot {
                                    liveActivityOn = LiveActivities.start(
                                        account: account, descriptor: descriptor,
                                        snapshot: snapshot, pace: model.pace(for: account))
                                }
                            } label: {
                                Label("Pin to Lock Screen", systemImage: "rectangle.badge.plus")
                            }
                        }
                    }
                    if let url = descriptor.docsURL {
                        Link(destination: url) { Label("Open \(descriptor.name) console", systemImage: "safari") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label("Remove account", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .task {
            keyHint = KeychainStore.hint(for: account.id)
            liveActivityOn = LiveActivities.isRunning(for: account.id)
            // Only fetch when nothing is cached and nothing is in flight —
            // a second concurrent read here used to leave the card spinning.
            if snapshot == nil, !state.isLoading { await model.refresh(account) }
        }
        .sheet(isPresented: $replacingKey) {
            ReplaceKeyView(account: account) { keyHint = KeychainStore.hint(for: account.id) }
        }
        .sheet(isPresented: $editingBudget) {
            @Bindable var model = model
            BudgetEditor(title: account.nickname, current: model.settings.accountBudgets[account.id]) {
                model.settings.accountBudgets[account.id] = $0
            }
        }
        .alert("Tag", isPresented: $editingTag) {
            TextField("work, personal…", text: $draftTag)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {}
            if account.tag != nil {
                Button("Remove", role: .destructive) { model.setTag(nil, for: account) }
            }
            Button("Save") { model.setTag(draftTag, for: account) }
        } message: {
            Text("Group accounts to split monthly spend by tag.")
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.rename(account, to: draftName) }
        }
        .confirmationDialog("Remove \(account.nickname)?", isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.remove(account)
                dismiss()
            }
        } message: {
            Text("The key is deleted from this iPhone’s Keychain. It stays valid at "
               + "the provider — revoke it there if you need to.")
        }
    }

    /// Budget, daily spend and peak hours — each only when there is data.
    @ViewBuilder
    private func insights(_ account: Account) -> some View {
        let days = model.ledger.daily(account: account.id)
        let peak = PeakHours.analyze(model.history[account.id] ?? [])
        let hasSpend = model.snapshot(for: account).flatMap(AppModel.monthToDate) != nil

        if let budget = model.budgetStatus(for: account) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Budget")
                Button { editingBudget = true } label: {
                    BudgetLine(status: budget, label: "monthly")
                        .card()
                }
                .buttonStyle(.plain)
            }
        } else if hasSpend {
            Button { editingBudget = true } label: {
                HStack {
                    Text("+ set a monthly budget for this account")
                    Spacer()
                    Text("›")
                }
                .font(.mono(.caption))
                .foregroundStyle(Theme.inkSecondary)
                .card()
            }
            .buttonStyle(.plain)
        }

        if days.count >= 2 {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Daily spend")
                SpendHeatmap(days: days)
                    .card()
            }
        }

        if let peak {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Peak hours", subtitle: "when this allowance gets used")
                PeakHoursChart(peak: peak)
                    .card()
            }
        }
    }

    private func connection(_ account: Account, descriptor: ProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "Connection")
            VStack(spacing: 0) {
                row("Provider", descriptor.name)
                Divider()
                if let tag = account.tag {
                    row("Tag", "#\(tag)", monospaced: true)
                    Divider()
                }
                if let kind = descriptor.webSignIn {
                    row("Session", keyHint == nil ? "—" : "Signed in to \(kind.host)")
                } else {
                    row("Key", keyHint ?? "—", monospaced: true)
                }
                if let extra = account.extraValue, !extra.isEmpty, let field = descriptor.extraField {
                    Divider()
                    row(field.label, field.options.first { $0.value == extra }?.title ?? extra)
                }
                Divider()
                row("Added", account.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let fetched = model.snapshot(for: account)?.fetchedAt {
                    Divider()
                    row("Last read", fetched.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .card(padding: 0)
        }
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Theme.ink)
                .fontDesign(monospaced ? .monospaced : .default)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.vertical, Theme.Space.m)
    }
}

// MARK: - Hero

struct AccountHero: View {
    let account: Account
    let descriptor: ProviderDescriptor
    let state: AccountState
    let snapshot: UsageSnapshot?
    var pace: PaceForecast? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                ProviderGlyph(descriptor: descriptor, size: Theme.Glyph.hero)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(descriptor.name)
                        .font(.headline)
                    Text(snapshot?.label ?? descriptor.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if state.isLoading { ProgressView() }
            }

            if let headline = snapshot?.headline {
                HStack(alignment: .center, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(MetricText.value(headline))
                            .font(.system(size: figureSize, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text(MetricText.caption(headline))
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let fraction = headline.fraction {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SegmentedMeter(fraction: fraction, height: 14, segment: 6, gap: 2)
                        HStack {
                            Text("\(Int((fraction * 100).rounded()))% used")
                                .foregroundStyle(Theme.severity(fraction, tint: Theme.inkSecondary))
                            Spacer()
                            Text("\(100 - Int((fraction * 100).rounded()))% left")
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .font(.mono(.caption2, weight: .medium))
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    if let fraction = headline.fraction {
                        let level = Theme.level(fraction)
                        if level != .calm {
                            StatusPill(text: level == .critical ? "Near limit" : "Running high",
                                       color: Theme.color(for: level),
                                       symbol: "exclamationmark.triangle.fill")
                        }
                    }
                    if let reset = headline.resetsAt { ResetChip(date: reset) }
                    Spacer(minLength: 0)
                    if let snapshot {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(Format.relative(snapshot.fetchedAt, from: context.date))
                                .font(.caption)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
                if let pace {
                    Label(pace.text(), systemImage: pace.isWarning
                          ? "exclamationmark.triangle.fill"
                          : "speedometer")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(pace.isWarning ? Theme.critical : Theme.inkSecondary)
                }
            } else if snapshot != nil {
                Text("Connected, but this provider returned no usage figures.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            } else if state.errorMessage == nil {
                HStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.fillSubtle).frame(width: 160, height: 40)
                    Spacer()
                    RoundedRectangle(cornerRadius: Theme.Radius.tag).fill(Theme.fillSubtle).frame(width: 92, height: 40)
                }
                .accessibilityLabel("Loading usage")
            }
        }
        .glassPanel(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart

struct HistoryChart: View {
    let points: [HistoryPoint]
    let tint: Color
    let currencyCode: String?
    let title: String

    @State private var selected: Date?

    private var selectedPoint: HistoryPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "History", subtitle: subtitle)
            Chart(points) { point in
                AreaMark(x: .value("Time", point.date), y: .value(title, point.value))
                    .foregroundStyle(tint.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value(title, point.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                if let selectedPoint, selectedPoint.date == point.date {
                    RuleMark(x: .value("Time", point.date))
                        .foregroundStyle(Theme.inkTertiary)
                    PointMark(x: .value("Time", point.date), y: .value(title, point.value))
                        .foregroundStyle(tint)
                        .symbolSize(70)
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            .card()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("History chart, \(points.count) readings")
    }

    private var subtitle: String {
        let point = selectedPoint ?? points.last
        guard let point else { return "" }
        let value = Format.value(point.value, unit: point.unit, currencyCode: currencyCode)
        let when = selectedPoint == nil ? "now" : point.date.formatted(date: .abbreviated, time: .shortened)
        return "\(title) · \(value) \(when)"
    }
}

// MARK: - Metric row

struct MetricRow: View {
    let metric: UsageMetric
    var tint: Color = Theme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(MetricText.value(metric, includeLimit: true))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
            }
            if let fraction = metric.fraction {
                SegmentedMeter(fraction: fraction, height: 7, segment: 4, gap: 2)
            }
            if metric.caption != nil || metric.resetsAt != nil {
                HStack(spacing: Theme.Space.s) {
                    if let caption = metric.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    if let reset = metric.resetsAt { ResetChip(date: reset) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Replace key

struct ReplaceKeyView: View {
    let account: Account
    var onReplaced: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var signingIn = false

    private var descriptor: ProviderDescriptor {
        ProviderRegistry.descriptor(id: account.providerID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let kind = descriptor.webSignIn {
                    Section {
                        Button {
                            signingIn = true
                        } label: {
                            Label("Sign in to \(kind.serviceName) again", systemImage: "person.badge.key.fill")
                        }
                        .disabled(isSaving)
                    } footer: {
                        Text("Opens the \(kind.serviceName) login page. The new session replaces the "
                           + "old one; history and settings are kept.")
                    }
                } else {
                Section {
                    SecureField(descriptor.credentialHint, text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                        .onSubmit(save)
                    PasteKeyButton(key: $key)
                } header: {
                    Text("New \(descriptor.credentialTitle.lowercased())")
                } footer: {
                    Text("Checked against \(descriptor.name) before it replaces the current key. "
                       + "History and settings are kept.")
                }
                }
                if let errorMessage {
                    Section { Callout(text: errorMessage, level: .critical) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background { CanvasBackground() }
            .navigationTitle(descriptor.webSignIn == nil ? "Replace key" : "Reconnect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(role: .confirm, action: save)
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .sheet(isPresented: $signingIn) {
                if let kind = descriptor.webSignIn {
                    WebSignInView(kind: kind) { credential in
                        key = credential
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return }
        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await model.replaceKey(for: account, with: key)
                onReplaced()
                dismiss()
            } catch {
                errorMessage = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// "Paste from clipboard" row, using the system paste control so iOS does
/// not show the paste-permission prompt.
struct PasteKeyButton: View {
    @Binding var key: String

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            if let first = strings.first {
                key = first.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        .buttonBorderShape(.capsule)
        .labelStyle(.titleAndIcon)
    }
}
