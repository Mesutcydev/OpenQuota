import Foundation
import Observation
import UserNotifications
import WidgetKit

enum DashboardSort: String, Codable, CaseIterable, Identifiable {
    case custom, attention, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: return "Custom order"
        case .attention: return "Needs attention first"
        case .name: return "Name"
        }
    }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Settings: Codable, Hashable {
    var alertsEnabled: Bool = false
    /// Fraction of an allowance consumed before an alert fires.
    var alertThreshold: Double = 0.8
    var refreshOnLaunch: Bool = true
    /// Re-read providers when the app returns to the foreground if the last
    /// read is older than this many minutes. 0 disables.
    var staleAfterMinutes: Int = 15
    var sort: DashboardSort = .custom
    var appearance: AppearancePreference = .system
    /// Pure black canvas and dimmer surfaces in dark mode, for OLED screens.
    var oledBlack: Bool = false
    /// Ask iOS to re-read providers while the app is closed.
    var backgroundRefresh: Bool = true
    /// Notify when a limit that was in use resets.
    var resetAlertsEnabled: Bool = false
    /// Require Face ID / passcode when the app opens.
    var requireUnlock: Bool = false
    /// Monthly USD budget across every account. Nil means none set.
    var monthlyBudget: Double? = nil
    /// Monthly USD budget per account.
    var accountBudgets: [UUID: Double] = [:]
    /// Notify at 80% and 100% of a budget.
    var budgetAlertsEnabled: Bool = true
    /// Notify when today's spend is far above the usual day.
    var spikeAlertsEnabled: Bool = true

    init() {}

    init(refreshOnLaunch: Bool) {
        self.refreshOnLaunch = refreshOnLaunch
    }

    // Tolerant decoding so adding a setting never resets the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alertsEnabled = (try? c.decode(Bool.self, forKey: .alertsEnabled)) ?? false
        alertThreshold = (try? c.decode(Double.self, forKey: .alertThreshold)) ?? 0.8
        refreshOnLaunch = (try? c.decode(Bool.self, forKey: .refreshOnLaunch)) ?? true
        staleAfterMinutes = (try? c.decode(Int.self, forKey: .staleAfterMinutes)) ?? 15
        sort = (try? c.decode(DashboardSort.self, forKey: .sort)) ?? .custom
        appearance = (try? c.decode(AppearancePreference.self, forKey: .appearance)) ?? .system
        oledBlack = (try? c.decode(Bool.self, forKey: .oledBlack)) ?? false
        backgroundRefresh = (try? c.decode(Bool.self, forKey: .backgroundRefresh)) ?? true
        resetAlertsEnabled = (try? c.decode(Bool.self, forKey: .resetAlertsEnabled)) ?? false
        requireUnlock = (try? c.decode(Bool.self, forKey: .requireUnlock)) ?? false
        monthlyBudget = try? c.decode(Double.self, forKey: .monthlyBudget)
        accountBudgets = (try? c.decode([UUID: Double].self, forKey: .accountBudgets)) ?? [:]
        budgetAlertsEnabled = (try? c.decode(Bool.self, forKey: .budgetAlertsEnabled)) ?? true
        spikeAlertsEnabled = (try? c.decode(Bool.self, forKey: .spikeAlertsEnabled)) ?? true
    }
}

/// Navigation state shared by the tab bar, the notification delegate and
/// deep links.
@MainActor
@Observable
final class Router {
    enum Tab: Hashable { case overview, accounts, settings }

    var tab: Tab = .overview
    var overviewPath: [UUID] = []
    var accountsPath: [UUID] = []
    var showingConnect = false
    /// Set by Settings → Replay intro; the root view shows the onboarding.
    var replayingIntro = false

    func open(accountID: UUID) {
        tab = .overview
        overviewPath = [accountID]
    }
}

@MainActor
@Observable
final class AppModel {
    /// The live instance, for App Intents that run inside the app process.
    static weak var shared: AppModel?

    private(set) var accounts: [Account] = []
    /// What is happening right now for each account.
    private(set) var states: [UUID: AccountState] = [:]
    /// The last reading that succeeded, kept through later loads and
    /// failures so a card never goes blank. Persisted, so launch shows the
    /// previous numbers instantly.
    private(set) var snapshots: [UUID: UsageSnapshot] = [:]
    private(set) var history: [UUID: [HistoryPoint]] = [:]
    /// Day-by-day spend reconstructed from month-to-date figures.
    private(set) var ledger = SpendLedger()
    private(set) var lastRefreshedAt: Date?
    private(set) var isRefreshingAll = false

    var settings: Settings {
        didSet {
            if !DemoData.isEnabled { Persistence.save(settings, to: "settings.json") }
            if oldValue.monthlyBudget != settings.monthlyBudget { pushWidget() }
        }
    }

    /// "accountID-dayStamp" keys of alerts already sent, persisted so a
    /// relaunch does not re-fire the same alert.
    private var alertStamps: Set<String> = []
    /// "budget-<scope>-<yyyy-MM>-<level>" stamps, kept for the current month.
    private var budgetStamps: Set<String> = []

    init() {
        if DemoData.isEnabled {
            let seeded = DemoData.seed()
            accounts = seeded.accounts
            states = seeded.states
            snapshots = seeded.states.compactMapValues(\.snapshot)
            history = seeded.history
            ledger = seeded.ledger
            settings = Settings(refreshOnLaunch: false)
            settings.monthlyBudget = 2000
            if let openAI = accounts.first(where: { $0.providerID == "openai" }) {
                settings.accountBudgets[openAI.id] = 1000
            }
            lastRefreshedAt = Date()
            return
        }
        defer {
            AppModel.shared = self
            WidgetRefresher.handler = { [weak self] in await self?.refreshAll() }
        }
        accounts = Persistence.load([Account].self, from: "accounts.json") ?? []
        history = Persistence.load([UUID: [HistoryPoint]].self, from: "history.json") ?? [:]
        snapshots = Persistence.load([UUID: UsageSnapshot].self, from: "snapshots.json") ?? [:]
        settings = Persistence.load(Settings.self, from: "settings.json") ?? Settings()
        alertStamps = Persistence.load(Set<String>.self, from: "alerts.json") ?? []
        budgetStamps = Persistence.load(Set<String>.self, from: "budget-alerts.json") ?? []
        ledger = Persistence.load(SpendLedger.self, from: "ledger.json") ?? SpendLedger()
        WatchSync.shared.start()
        lastRefreshedAt = snapshots.values.map(\.fetchedAt).max()
        for account in accounts { states[account.id] = .idle }
        pruneAlertStamps()
    }

    var isRefreshing: Bool { isRefreshingAll || states.values.contains(where: \.isLoading) }

    func state(for account: Account) -> AccountState {
        states[account.id] ?? .idle
    }

    func snapshot(for account: Account) -> UsageSnapshot? {
        snapshots[account.id]
    }

    func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    /// Accounts in the order the dashboard should show them.
    var sortedAccounts: [Account] {
        switch settings.sort {
        case .custom:
            return accounts
        case .name:
            return accounts.sorted {
                $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
            }
        case .attention:
            return accounts.enumerated().sorted { a, b in
                let sa = attentionScore(a.element), sb = attentionScore(b.element)
                return sa == sb ? a.offset < b.offset : sa > sb
            }.map(\.element)
        }
    }

    /// Higher means more urgent: failures first, then fullest allowances.
    func attentionScore(_ account: Account) -> Double {
        if state(for: account).errorMessage != nil { return 2 }
        return snapshot(for: account)?.headline?.fraction ?? -1
    }

    // MARK: - Connecting

    /// Validates the credential by doing a real read before anything is
    /// stored, so a bad key never becomes a broken card on the dashboard.
    func connect(
        providerID: String,
        nickname: String,
        key: String,
        extra: String?
    ) async throws -> Account {
        guard let provider = ProviderRegistry.provider(id: providerID) else {
            throw ProviderError.message("Unknown provider.")
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExtra = extra?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = try await provider.fetch(key: trimmedKey, extra: trimmedExtra)

        let descriptor = provider.descriptor
        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = reading.label.flatMap { $0.isEmpty ? nil : $0 } ?? descriptor.name
        let account = Account(
            providerID: providerID,
            nickname: trimmedName.isEmpty ? fallbackName : trimmedName,
            extraValue: trimmedExtra)

        guard KeychainStore.save(trimmedKey, for: account.id) else {
            throw ProviderError.message("Could not save the key to the keychain.")
        }

        accounts.append(account)
        persistAccounts()
        apply(reading: reading, to: account)
        pushWidget()
        return account
    }

    /// Swaps in a new key for an existing account, keeping its history and
    /// position. Validated before the old key is overwritten.
    func replaceKey(for account: Account, with key: String) async throws {
        guard let provider = ProviderRegistry.provider(id: account.providerID) else {
            throw ProviderError.message("Unknown provider.")
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = try await provider.fetch(key: trimmed, extra: account.extraValue)
        guard KeychainStore.save(trimmed, for: account.id) else {
            throw ProviderError.message("Could not save the key to the keychain.")
        }
        apply(reading: reading, to: account)
        pushWidget()
    }

    func remove(_ account: Account) {
        KeychainStore.delete(for: account.id)
        LiveActivities.end(accountID: account.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["reset-\(account.id.uuidString)"])
        accounts.removeAll { $0.id == account.id }
        states[account.id] = nil
        snapshots[account.id] = nil
        history[account.id] = nil
        ledger.remove(account: account.id)
        settings.accountBudgets[account.id] = nil
        persistAccounts()
        persistLedger()
        persistSnapshots()
        Persistence.save(history, to: "history.json")
        pushWidget()
    }

    func rename(_ account: Account, to name: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts[index].nickname = trimmed
        persistAccounts()
        pushWidget()
    }

    /// Sets or clears the account's group tag.
    func setTag(_ tag: String?, for account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        accounts[index].tag = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persistAccounts()
    }

    /// Every tag in use, alphabetical.
    var tags: [String] {
        Array(Set(accounts.compactMap(\.tag))).sorted()
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        persistAccounts()
        pushWidget()
    }

    // MARK: - Refreshing

    /// Refreshes when the newest reading is older than the stale window.
    func refreshIfStale() async {
        guard settings.staleAfterMinutes > 0 else { return }
        let limit = TimeInterval(settings.staleAfterMinutes * 60)
        if let last = lastRefreshedAt, Date().timeIntervalSince(last) < limit { return }
        await refreshAll()
    }

    func refreshAll() async {
        // A second pull-to-refresh must not stack a parallel fan-out on top
        // of one already in flight.
        guard !accounts.isEmpty, !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        let pending = accounts.filter { !state(for: $0).isLoading }
        for account in pending { states[account.id] = .loading }

        // At most four requests in flight: fourteen simultaneous connections
        // get keys rate-limited and drain the radio.
        var next = 0
        let anyLoaded = await withTaskGroup(of: Bool.self) { group in
            func addNext() {
                guard next < pending.count else { return }
                let account = pending[next]
                next += 1
                group.addTask { await self.refresh(account, markLoading: false, pushWidget: false) }
            }
            for _ in 0..<4 { addNext() }
            var loaded = false
            while let success = await group.next() {
                if success { loaded = true }
                addNext()
            }
            return loaded
        }
        // Only claim the data is fresh if at least one read actually landed.
        if anyLoaded { lastRefreshedAt = Date() }
        persistSnapshots()
        checkBudgets()
        checkSpike()
        pushWidget()
    }

    @discardableResult
    func refresh(_ account: Account, markLoading: Bool = true, pushWidget push: Bool = true) async -> Bool {
        guard let provider = ProviderRegistry.provider(id: account.providerID) else {
            states[account.id] = .failed("This provider is no longer supported.")
            return false
        }
        guard let key = KeychainStore.read(for: account.id) else {
            states[account.id] = .failed("Key missing from keychain. Replace the key to reconnect.")
            return false
        }
        if markLoading {
            guard !state(for: account).isLoading else { return false }
            states[account.id] = .loading
        }

        defer {
            if push {
                persistSnapshots()
                pushWidget()
            }
        }

        do {
            let reading = try await provider.fetch(key: key, extra: account.extraValue)
            if let renewed = reading.renewedCredential, renewed != key {
                KeychainStore.save(renewed, for: account.id)
            }
            apply(reading: reading, to: account)
            return true
        } catch is CancellationError {
            // Cancellation is control flow, not a provider fault. Never park
            // the card on `.loading`: fall back to the last good reading.
            if accounts.contains(where: { $0.id == account.id }) {
                states[account.id] = snapshots[account.id].map(AccountState.loaded) ?? .idle
            }
            return false
        } catch {
            guard accounts.contains(where: { $0.id == account.id }) else { return false }
            let message = (error as? ProviderError)?.errorDescription
                ?? error.localizedDescription
            states[account.id] = .failed(message)
            return false
        }
    }

    private func apply(reading: ProviderReading, to account: Account) {
        // A refresh in flight when the account was removed must not
        // resurrect its state or history.
        guard accounts.contains(where: { $0.id == account.id }) else { return }
        let snapshot = UsageSnapshot(
            accountID: account.id,
            fetchedAt: Date(),
            label: reading.label,
            metrics: reading.metrics,
            notes: reading.notes)
        states[account.id] = .loaded(snapshot)
        snapshots[account.id] = snapshot
        record(snapshot, for: account)
        recordSpend(snapshot, for: account)
        checkThreshold(snapshot, for: account)
        scheduleResetAlert(snapshot, for: account)
        LiveActivities.update(accountID: account.id, snapshot: snapshot,
                              pace: pace(for: account))
    }

    // MARK: - History

    private func record(_ snapshot: UsageSnapshot, for account: Account) {
        guard let headline = snapshot.headline,
              let value = headline.displayValue else { return }
        var points = history[account.id] ?? []
        let point = HistoryPoint(date: snapshot.fetchedAt, value: value, unit: headline.unit,
                                 fraction: headline.fraction, remaining: headline.remaining)
        // One point per clock hour. Comparing hour buckets (rather than "less
        // than an hour since the last point") stops frequent refreshes from
        // sliding a single point forward forever.
        if let last = points.last,
           Calendar.current.isDate(last.date, equalTo: snapshot.fetchedAt, toGranularity: .hour),
           last.unit == headline.unit {
            points[points.count - 1] = point
        } else {
            // A unit change (e.g. a provider switching headline) would make
            // the chart meaningless; start the series over.
            if let last = points.last, last.unit != headline.unit { points.removeAll() }
            points.append(point)
        }
        if points.count > 24 * 30 { points.removeFirst(points.count - 24 * 30) }
        history[account.id] = points
        Persistence.save(history, to: "history.json")
    }

    /// Month-to-date USD spend the account reports, if any.
    nonisolated static func monthToDate(_ snapshot: UsageSnapshot) -> Double? {
        snapshot.metrics.first {
            BoardSummary.spendIDs.contains($0.id) && $0.unit == .usd && ($0.currencyCode ?? "USD") == "USD"
        }?.used
    }

    private func recordSpend(_ snapshot: UsageSnapshot, for account: Account) {
        guard let mtd = Self.monthToDate(snapshot) else { return }
        ledger.record(account: account.id, monthToDate: mtd, at: snapshot.fetchedAt)
        ledger.prune()
        persistLedger()
    }

    /// Daily spend across accounts (all by default), oldest first.
    func dailySpend(accounts ids: Set<UUID>? = nil) -> [DaySpend] {
        ledger.dailyTotals(accounts: ids)
    }

    /// Board-wide budget status, when a monthly budget is set.
    func budgetStatus(spent: Double?) -> BudgetStatus? {
        BudgetStatus(spent: spent, budget: settings.monthlyBudget)
    }

    /// Budget status for one account.
    func budgetStatus(for account: Account) -> BudgetStatus? {
        BudgetStatus(spent: snapshots[account.id].flatMap(Self.monthToDate),
                     budget: settings.accountBudgets[account.id])
    }

    /// Today's spend when it is far above the usual day.
    var spike: SpendSpike? { SpendSpike.detect(dailySpend()) }

    /// Projection for the account's headline, from its recorded history.
    func pace(for account: Account, now: Date = Date()) -> PaceForecast? {
        guard let headline = snapshots[account.id]?.headline else { return nil }
        return Pace.forecast(metric: headline, history: history[account.id] ?? [], now: now)
    }

    // MARK: - Alerts

    private func checkThreshold(_ snapshot: UsageSnapshot, for account: Account) {
        guard settings.alertsEnabled, !DemoData.isEnabled,
              let headline = snapshot.headline,
              let fraction = headline.fraction,
              fraction >= settings.alertThreshold
        else { return }

        let day = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let stamp = "\(account.id.uuidString)-\(day)"
        guard !alertStamps.contains(stamp) else { return }
        alertStamps.insert(stamp)
        Persistence.save(alertStamps, to: "alerts.json")

        let content = UNMutableNotificationContent()
        content.title = account.nickname
        content.body = "\(headline.title) — \(Int((fraction * 100).rounded()))% used."
        content.sound = .default
        content.userInfo = ["accountID": account.id.uuidString]
        content.threadIdentifier = account.id.uuidString
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: stamp, content: content, trigger: nil))
    }

    /// Queues a local notification for the moment the headline allowance
    /// resets — only when the window was meaningfully used, since "your
    /// untouched quota reset" is noise. Re-scheduling replaces the pending
    /// one (same identifier), so each account has at most one queued.
    private func scheduleResetAlert(_ snapshot: UsageSnapshot, for account: Account) {
        let identifier = "reset-\(account.id.uuidString)"
        let center = UNUserNotificationCenter.current()
        guard settings.resetAlertsEnabled, !DemoData.isEnabled,
              let headline = snapshot.headline,
              let reset = headline.resetsAt,
              let fraction = headline.fraction, fraction >= 0.5
        else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let delay = reset.timeIntervalSinceNow
        guard delay > 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = account.nickname
        content.body = "\(headline.title) has reset — the full allowance is available again."
        content.sound = .default
        content.userInfo = ["accountID": account.id.uuidString]
        content.threadIdentifier = account.id.uuidString
        center.add(UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
    }

    /// Fires once per budget, level and month: at 80% used and when over.
    private func checkBudgets() {
        guard settings.budgetAlertsEnabled, !DemoData.isEnabled else { return }
        let month = String(SpendLedger.key(Date()).prefix(7))
        var scopes: [(id: String, name: String, status: BudgetStatus)] = []
        let summary = BoardSummary(accounts: accounts, snapshots: snapshots)
        if let total = budgetStatus(spent: summary.monthSpend) {
            scopes.append(("all", "All providers", total))
        }
        for account in accounts {
            if let status = budgetStatus(for: account) {
                scopes.append((account.id.uuidString, account.nickname, status))
            }
        }
        for scope in scopes {
            let level = scope.status.fraction >= 1 ? 100 : (scope.status.fraction >= 0.8 ? 80 : 0)
            guard level > 0 else { continue }
            let stamp = "budget-\(scope.id)-\(month)-\(level)"
            guard !budgetStamps.contains(stamp) else { continue }
            budgetStamps.insert(stamp)
            let content = UNMutableNotificationContent()
            content.title = "\(scope.name) budget"
            content.body = level == 100
                ? "Over budget: \(Format.currency(scope.status.spent)) of \(Format.currency(scope.status.budget)) this month."
                : "\(Int((scope.status.fraction * 100).rounded()))% of the \(Format.currency(scope.status.budget)) budget used — \(scope.status.projectionText)."
            content.sound = .default
            if scope.id != "all" { content.userInfo = ["accountID": scope.id] }
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: stamp, content: content, trigger: nil))
        }
        budgetStamps = budgetStamps.filter { $0.contains("-\(month)-") }
        Persistence.save(budgetStamps, to: "budget-alerts.json")
    }

    /// Fires at most once a day when today's spend spikes.
    private func checkSpike() {
        guard settings.spikeAlertsEnabled, !DemoData.isEnabled, let spike else { return }
        let day = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let stamp = "spike-\(day)"
        guard !alertStamps.contains(stamp) else { return }
        alertStamps.insert(stamp)
        Persistence.save(alertStamps, to: "alerts.json")
        let content = UNMutableNotificationContent()
        content.title = "Spend spike"
        content.body = "\(Format.currency(spike.today)) spent today — \(spike.ratioText) (\(Format.currency(spike.usual)) a day)."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: stamp, content: content, trigger: nil))
    }

    /// Clears every queued reset alert, used when the setting is turned off.
    func cancelResetAlerts() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: accounts.map { "reset-\($0.id.uuidString)" })
    }

    /// Drops stamps older than two days so the set does not grow forever.
    private func pruneAlertStamps() {
        let cutoff = Int(Date().addingTimeInterval(-2 * 86_400).timeIntervalSince1970)
        let kept = alertStamps.filter { stamp in
            guard let day = stamp.split(separator: "-").last.flatMap({ Int($0) }) else { return false }
            return day >= cutoff
        }
        if kept.count != alertStamps.count {
            alertStamps = kept
            Persistence.save(alertStamps, to: "alerts.json")
        }
    }

    func requestAlertPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if !granted { settings.alertsEnabled = false }
        return granted
    }

    // MARK: - Persistence

    private func persistAccounts() {
        guard !DemoData.isEnabled else { return }
        Persistence.save(accounts, to: "accounts.json")
    }

    private func persistLedger() {
        guard !DemoData.isEnabled else { return }
        Persistence.save(ledger, to: "ledger.json")
    }

    private func persistSnapshots() {
        guard !DemoData.isEnabled else { return }
        Persistence.save(snapshots, to: "snapshots.json")
    }

    /// Rebuild the widget board from last-good readings, so an account that
    /// is loading or failed keeps its previous figure on the Home Screen.
    private func pushWidget() {
        let board = WidgetBoard.build(
            accounts: accounts,
            snapshots: snapshots,
            namer: { ProviderRegistry.descriptor(id: $0).name },
            tintFor: { ProviderRegistry.descriptor(id: $0).tintHex },
            paceFor: { id in self.account(id: id).flatMap { self.pace(for: $0)?.text() } })
        var withSpend = board
        let summary = BoardSummary(accounts: accounts, snapshots: snapshots)
        let days = dailySpend()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.day), $0.amount) }, uniquingKeysWith: +)
        withSpend.monthSpend = summary.monthSpend
        withSpend.budget = settings.monthlyBudget
        withSpend.projectedSpend = BudgetStatus(spent: summary.monthSpend, budget: 1)?.projected
        withSpend.todaySpend = byDay[today]
        withSpend.spikeText = spike?.ratioText
        withSpend.recentDaily = days.isEmpty ? nil : (0..<28).reversed().map { back in
            byDay[calendar.date(byAdding: .day, value: -back, to: today)!] ?? 0
        }
        // Reloads come out of a daily budget: spending one on an unchanged
        // board leaves the widget stale later in the day.
        guard withSpend != WidgetStore.load() else { return }
        WidgetStore.save(withSpend)
        WatchSync.shared.send(withSpend)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
