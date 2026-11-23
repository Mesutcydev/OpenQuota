import SwiftUI

import CoreTransferable
import UniformTypeIdentifiers
import UserNotifications

/// The history export, built only when the share sheet asks for it.
struct HistoryCSV: Transferable {
    let make: @Sendable () -> String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.make().utf8) }
            .suggestedFileName("openquota-history.csv")
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var editingBudget = false
    @State private var showingRecap = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    header

                    SettingsGroup(title: "Refresh",
                                  footer: "Providers are read when you open the app, return to it, or pull to "
                                      + "refresh. With background refresh on, iOS also re-reads them every so "
                                      + "often while the app is closed, so widgets and alerts stay current.") {
                        SettingsRow(symbol: "arrow.clockwise", color: .blue, title: "Refresh on launch") {
                            Toggle("", isOn: $model.settings.refreshOnLaunch).labelsHidden().tint(Theme.toggleOn)
                        }
                        SettingsRow(symbol: "clock.arrow.circlepath", color: .teal, title: "Refresh after") {
                            Menu {
                                Picker("Refresh when older than", selection: $model.settings.staleAfterMinutes) {
                                    Text("Off").tag(0)
                                    Text("5 minutes").tag(5)
                                    Text("15 minutes").tag(15)
                                    Text("1 hour").tag(60)
                                }
                            } label: {
                                MenuValue(text: staleTitle(model.settings.staleAfterMinutes))
                            }
                        }
                        SettingsRow(symbol: "arrow.trianglehead.2.clockwise.rotate.90", color: .cyan,
                                    title: "Refresh in background", showsDivider: false) {
                            Toggle("", isOn: $model.settings.backgroundRefresh).labelsHidden().tint(Theme.toggleOn)
                        }
                        .onChange(of: model.settings.backgroundRefresh) { _, enabled in
                            BackgroundRefresh.schedule(enabled: enabled)
                        }
                    }

                    SettingsGroup(title: "Alerts",
                                  footer: "Threshold alerts fire at most once a day per account, only for providers "
                                      + "that report a limit. Reset alerts tell you when a window you were at least "
                                      + "half way through resets. Tapping an alert opens that account.") {
                        SettingsRow(symbol: "bell.badge.fill", color: .orange, title: "Threshold alerts") {
                            Toggle("", isOn: Binding(
                                get: { model.settings.alertsEnabled },
                                set: { enabled in
                                    model.settings.alertsEnabled = enabled
                                    if enabled { Task { _ = await model.requestAlertPermission() } }
                                }))
                                .labelsHidden().tint(Theme.toggleOn)
                        }
                        if model.settings.alertsEnabled {
                            thresholdSlider
                        }
                        SettingsRow(symbol: "arrow.counterclockwise", color: .red, title: "Reset alerts",
                                    showsDivider: false) {
                            Toggle("", isOn: Binding(
                                get: { model.settings.resetAlertsEnabled },
                                set: { enabled in
                                    model.settings.resetAlertsEnabled = enabled
                                    if enabled {
                                        Task {
                                            if await model.requestAlertPermission() {
                                                await model.refreshAll()
                                            } else {
                                                model.settings.resetAlertsEnabled = false
                                            }
                                        }
                                    } else {
                                        model.cancelResetAlerts()
                                    }
                                }))
                                .labelsHidden().tint(Theme.toggleOn)
                        }
                    }

                    SettingsGroup(title: "Spending",
                                  footer: "Budget alerts fire at 80% and when a budget is spent. Spike alerts fire "
                                      + "at most once a day, when today's spend is 2.5× the usual day and at least $5 more.") {
                        Button { editingBudget = true } label: {
                            SettingsRow(symbol: "dollarsign.gauge.chart.lefthalf.righthalf", color: Color(hex: "2E7D5B"),
                                        title: "Monthly budget") {
                                MenuValue(text: model.settings.monthlyBudget.map { Format.currency($0) } ?? "None")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        SettingsRow(symbol: "chart.bar.xaxis", color: .orange, title: "Budget alerts") {
                            Toggle("", isOn: alertToggle(\.budgetAlertsEnabled)).labelsHidden().tint(Theme.toggleOn)
                        }
                        SettingsRow(symbol: "waveform.path.ecg", color: Color(hex: "C2412F"), title: "Spike alerts") {
                            Toggle("", isOn: alertToggle(\.spikeAlertsEnabled)).labelsHidden().tint(Theme.toggleOn)
                        }
                        Button { showingRecap = true } label: {
                            SettingsRow(symbol: "calendar", color: Color(hex: "5E6472"),
                                        title: "Monthly recap", showsDivider: false) {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if AppLock.isAvailable {
                        SettingsGroup(title: "Security",
                                      footer: "Locks the app whenever it goes to the background. Widgets still show figures.") {
                            SettingsRow(symbol: "faceid", color: .green, title: "Require \(AppLock.biometryName)",
                                        showsDivider: false) {
                                Toggle("", isOn: $model.settings.requireUnlock).labelsHidden().tint(Theme.toggleOn)
                            }
                        }
                    }

                    SettingsGroup(title: "Appearance",
                                  footer: "Pure black turns dark mode surfaces fully off on OLED screens and dims the ambient lights.") {
                        SettingsRow(symbol: "circle.lefthalf.filled", color: .gray, title: "Theme") {
                            Menu {
                                Picker("Theme", selection: $model.settings.appearance) {
                                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                                }
                            } label: {
                                MenuValue(text: model.settings.appearance.title)
                            }
                        }
                        SettingsRow(symbol: "moon.stars.fill", color: .black,
                                    title: "Pure black (OLED)") {
                            Toggle("", isOn: $model.settings.oledBlack.animation(.snappy))
                                .labelsHidden().tint(Theme.toggleOn)
                        }
                        SettingsRow(symbol: "arrow.up.arrow.down", color: Color(hex: "5E6472"),
                                    title: "Overview order") {
                            Menu {
                                Picker("Overview order", selection: $model.settings.sort) {
                                    ForEach(DashboardSort.allCases) { Text($0.title).tag($0) }
                                }
                            } label: {
                                MenuValue(text: model.settings.sort.title)
                            }
                        }
                        Button {
                            router.replayingIntro = true
                        } label: {
                            SettingsRow(symbol: "play.rectangle", color: .gray,
                                        title: "Replay intro", showsDivider: false) {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the introduction again")
                    }

                    privacyCard

                    SettingsGroup(title: "Data",
                                  footer: "A CSV of every reading and each day's spend, per account. Keys are never included.") {
                        ShareLink(item: csv, preview: SharePreview("openquota-history.csv")) {
                            SettingsRow(symbol: "tablecells", color: .gray,
                                        title: "Export history (CSV)", showsDivider: false) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: Theme.Space.s) {
                        Text("Open Quota \(version)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("Figures come straight from each provider. Claude and ChatGPT plan limits are "
                           + "read from your own signed-in web session, not a public API, and can stop "
                           + "working if those sites change.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Theme.Space.xxl)
                    .padding(.bottom, Theme.Space.xl)
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Space.xs)
            }
            .background { CanvasBackground() }
            .navigationTitle("Settings")
            .sheet(isPresented: $editingBudget) {
                BudgetEditor(title: "Monthly budget", current: model.settings.monthlyBudget) {
                    model.settings.monthlyBudget = $0
                }
            }
            .sheet(isPresented: $showingRecap) {
                RecapSheet(recap: MonthRecap(
                    summary: BoardSummary(accounts: model.accounts, snapshots: model.snapshots),
                    days: model.dailySpend()))
            }
        }
    }

    private var csv: HistoryCSV {
        let accounts = model.accounts, history = model.history, ledger = model.ledger
        return HistoryCSV {
            HistoryExport.csv(accounts: accounts, history: history, ledger: ledger,
                              providerName: { ProviderRegistry.descriptor(id: $0).name })
        }
    }

    /// A notification toggle that asks for permission when switched on.
    private func alertToggle(_ key: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: key] },
            set: { enabled in
                model.settings[keyPath: key] = enabled
                if enabled {
                    Task { _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge]) }
                }
            })
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.grid) {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: Theme.TypeScale.title, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay { GlassRim(shape: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("openquota")
                        .font(.mono(.title3, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("# every ai bill, one glance")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .card(padding: Theme.Spacing.card, radius: Theme.Radius.hero)

            HStack(spacing: Theme.Spacing.grid) {
                HeaderStat(value: "\(model.accounts.count)", label: "Connected")
                HeaderStat(value: "\(ProviderRegistry.all.count)", label: "Providers")
                HeaderStat(value: model.settings.alertsEnabled ? "On" : "Off", label: "Alerts")
            }
        }
    }

    // MARK: Pieces

    private var thresholdSlider: some View {
        @Bindable var model = model
        let percent = Int((model.settings.alertThreshold * 100).rounded())
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Notify at")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text("\(percent)% used")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.severity(model.settings.alertThreshold))
                    .contentTransition(.numericText())
            }
            Slider(value: $model.settings.alertThreshold, in: 0.5...0.95, step: 0.05)
                .tint(Theme.severity(model.settings.alertThreshold))
                .accessibilityLabel("Alert threshold")
                .accessibilityValue("\(percent) percent")
        }
        .padding(.leading, 60)
        .padding(.trailing, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, 60)
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "lock.shield.fill", color: .green)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Private by design")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Keys and sign-in sessions are held in this iPhone’s Keychain (this device only, "
                   + "never in backups) and sent only to their own provider. There is no Open Quota "
                   + "server and no analytics.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func staleTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Off"
        case 60: return "1 hour"
        default: return "\(minutes) min"
        }
    }
}

// MARK: - Building blocks

/// Titled glass group with an optional footnote, in the manner of a
/// grouped list section.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .eyebrow()
                .padding(.leading, Theme.Space.l)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .card(padding: 0)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.l)
            }
        }
    }
}

/// One settings line: coloured icon tile, title and a trailing control.
private struct SettingsRow<Accessory: View>: View {
    let symbol: String
    let color: Color
    let title: String
    var showsDivider = true
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            IconTile(symbol: symbol, color: color)
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, 60)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Monochrome square with an ink glyph — the terminal look keeps colour
/// for state, not decoration. `color` is kept for call-site compatibility.
private struct IconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: Theme.TypeScale.small + 2, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}

/// Current value of a menu picker, with the up/down affordance.
private struct MenuValue: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Text(text)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs + Theme.Space.xxs)
        .background(Theme.fillSubtle, in: Capsule())
    }
}

private struct HeaderStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
        .card(padding: 0, radius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }
}
