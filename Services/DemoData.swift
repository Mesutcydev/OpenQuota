import Foundation

/// Debug-only fixtures, enabled with the `OQ_DEMO=1` environment variable.
///
/// This exists so every screen and state can be rendered and inspected
/// without a live provider key. Nothing here touches the keychain or disk.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["OQ_DEMO"] == "1"
    }

    /// Which screen to open on launch, for capturing a specific state.
    static var screen: String {
        ProcessInfo.processInfo.environment["OQ_SCREEN"] ?? "dashboard"
    }

    static func seed() -> (accounts: [Account], states: [UUID: AccountState], history: [UUID: [HistoryPoint]],
                          ledger: SpendLedger) {
        var seeded = rawSeed()
        let tags = ["OpenAI (near cap)": "work", "Anthropic org": "work", "Mistral org": "work",
                    "Together": "work", "Personal key": "personal", "Claude Max": "personal",
                    "GLM Coding Pro": "personal"]
        seeded.accounts = seeded.accounts.map { var a = $0; a.tag = tags[a.nickname]; return a }
        if let claude = seeded.accounts.first(where: { $0.providerID == "claude-plan" }) {
            seeded.history[claude.id] = peakHistory()
        }
        return (seeded.accounts, seeded.states, seeded.history,
                ledger(accounts: seeded.accounts, states: seeded.states))
    }

    /// Five days of a plan window filling mostly in the afternoon, ending at
    /// the current 64%, so peak-hour hints have something to read.
    private static func peakHistory(now: Date = Date()) -> [HistoryPoint] {
        let calendar = Calendar.current
        var points: [HistoryPoint] = []
        var fraction = 0.0
        for step in stride(from: -120, through: -1, by: 1) {
            let date = now.addingTimeInterval(Double(step) * 3600)
            let hour = calendar.component(.hour, from: date)
            if hour == 4 { fraction = 0.02 }
            let weight = max(0, 1 - abs(Double(hour) - 14.5) / 6)
            fraction = min(fraction + weight * 0.05, 0.95)
            points.append(HistoryPoint(date: date, value: fraction * 100, unit: .percent,
                                       fraction: fraction, remaining: nil))
        }
        return points
    }

    /// 60 days of month-to-date readings that end on each account's current
    /// figure, with a few busy days and a spike today.
    private static func ledger(accounts: [Account], states: [UUID: AccountState],
                               now: Date = Date()) -> SpendLedger {
        let calendar = Calendar.current
        var ledger = SpendLedger()
        let today = calendar.startOfDay(for: now)
        for account in accounts {
            guard let snapshot = states[account.id]?.snapshot,
                  let mtd = AppModel.monthToDate(snapshot), mtd > 0 else { continue }
            let dayOfMonth = calendar.component(.day, from: now)
            // Shape of a day's spend: weekdays heavier, a couple of bursts.
            func weight(_ date: Date, _ offset: Int) -> Double {
                let weekday = calendar.component(.weekday, from: date)
                var w = (weekday == 1 || weekday == 7) ? 0.35 : 1.0
                w *= 0.7 + 0.6 * abs(sin(Double(offset) * 1.7 + Double(account.nickname.count)))
                if offset == 0 { return 3.6 }
                if offset % 11 == 5 { w *= 2.2 }
                return w
            }
            let thisMonth = (0..<dayOfMonth).map { offset -> (Date, Double) in
                let date = calendar.date(byAdding: .day, value: -offset, to: today)!
                return (date, weight(date, offset))
            }.reversed()
            let total = thisMonth.reduce(0) { $0 + $1.1 }
            var running = 0.0
            for (date, w) in thisMonth {
                running += mtd * w / total
                ledger.record(account: account.id, monthToDate: running, at: date)
            }
            // Last month, at a similar daily rate.
            let perDay = mtd / Double(dayOfMonth)
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: today),
                  let range = calendar.range(of: .day, in: .month, for: lastMonth),
                  let start = calendar.dateInterval(of: .month, for: lastMonth)?.start else { continue }
            running = 0
            for day in range {
                let date = calendar.date(byAdding: .day, value: day - 1, to: start)!
                running += perDay * weight(date, day + 40) * 0.9
                ledger.record(account: account.id, monthToDate: running, at: date)
            }
        }
        return ledger
    }

    private static func rawSeed() -> (accounts: [Account], states: [UUID: AccountState], history: [UUID: [HistoryPoint]]) {
        let openCode = Account(providerID: "opencode", nickname: "OpenCode Go")
        let moonshot = Account(providerID: "moonshot", nickname: "Kimi")
        let openRouter = Account(providerID: "openrouter", nickname: "Personal key")
        let anthropic = Account(providerID: "anthropic", nickname: "Anthropic org")
        let deepSeek = Account(providerID: "deepseek", nickname: "DeepSeek")
        let groq = Account(providerID: "groq", nickname: "Groq")

        let now = Date()
        var states: [UUID: AccountState] = [:]

        states[openRouter.id] = .loaded(UsageSnapshot(
            accountID: openRouter.id, fetchedAt: now, label: "sk-or-v1-…8fa2",
            metrics: [
                UsageMetric(
                    id: "credits", title: "Credits left", used: 41.18, limit: 50,
                    remaining: 8.82, unit: .usd,
                    resetsAt: now.addingTimeInterval(3600 * 19),
                    caption: "key credit limit", isHeadline: true),
                UsageMetric(id: "daily", title: "Today", used: 3.94, unit: .usd),
                UsageMetric(id: "weekly", title: "This week", used: 17.22, unit: .usd),
                UsageMetric(id: "monthly", title: "This month", used: 41.18, unit: .usd),
                UsageMetric(
                    id: "free-requests", title: "Free model requests", used: 47,
                    limit: 1000, remaining: 953, unit: .requests, caption: "resets daily"),
            ]))

        states[openCode.id] = .loaded(UsageSnapshot(
            accountID: openCode.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "rolling", title: "5-hour window", used: 62, limit: 100,
                    remaining: 38, unit: .percent,
                    resetsAt: now.addingTimeInterval(3600 * 2 + 900),
                    caption: "20% of the monthly allowance", isHeadline: true),
                UsageMetric(id: "weekly", title: "This week", used: 34, limit: 100,
                            remaining: 66, unit: .percent,
                            caption: "50% of the monthly allowance"),
                UsageMetric(id: "monthly", title: "This month", used: 18, limit: 100,
                            remaining: 82, unit: .percent,
                            caption: "full monthly allowance"),
            ]))

        states[moonshot.id] = .loaded(UsageSnapshot(
            accountID: moonshot.id, fetchedAt: now,
            metrics: [
                UsageMetric(id: "available", title: "Available", remaining: 12.84,
                            unit: .usd, caption: "cash + vouchers", isHeadline: true),
                UsageMetric(id: "cash", title: "Cash", remaining: 9.84, unit: .usd),
                UsageMetric(id: "voucher", title: "Vouchers", remaining: 3.00,
                            unit: .usd, caption: "free credit"),
            ]))

        states[anthropic.id] = .loaded(UsageSnapshot(
            accountID: anthropic.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "month-cost", title: "Spent this month", used: 284.61,
                    unit: .usd, caption: "since Sep 1", isHeadline: true),
                UsageMetric(id: "today-cost", title: "Today", used: 12.04, unit: .usd),
                UsageMetric(id: "week-cost", title: "Last 7 days", used: 96.55, unit: .usd),
                UsageMetric(
                    id: "today-tokens", title: "Tokens today", used: 4_820_115,
                    unit: .tokens, caption: "input + cache + output"),
            ],
            notes: ["Subscription (Pro/Max) quotas are not exposed by the API — "
                  + "these figures are API organization usage."]))

        states[deepSeek.id] = .loaded(UsageSnapshot(
            accountID: deepSeek.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "balance", title: "Balance", remaining: 6.40, unit: .usd,
                    currencyCode: "CNY", caption: "granted + topped up", isHeadline: true),
                UsageMetric(id: "topped-up", title: "Topped up", remaining: 6.40,
                            unit: .usd, currencyCode: "CNY"),
            ]))

        // One failing account, so the error path is visible in the same pass.
        states[groq.id] = .failed("Key rejected. Check that it is active and pasted in full.")

        // The four added this session, each shaped like its real adapter's
        // output so the new decoders' headline/extras split is exercised.
        let mistral = Account(providerID: "mistral", nickname: "Mistral org")
        let together = Account(providerID: "together", nickname: "Together")
        let deepInfra = Account(providerID: "deepinfra", nickname: "DeepInfra")
        let novita = Account(providerID: "novita", nickname: "Novita")

        states[mistral.id] = .loaded(UsageSnapshot(
            accountID: mistral.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "spend", title: "Spent this month", used: 372.40, limit: 500,
                    remaining: 127.60, unit: .usd, caption: "monthly spend limit",
                    isHeadline: true),
                UsageMetric(id: "completion-tokens", title: "Completion tokens",
                            used: 18_400_000, unit: .tokens),
                UsageMetric(id: "requests", title: "Requests", used: 42_180,
                            unit: .requests),
            ]))

        states[together.id] = .loaded(UsageSnapshot(
            accountID: together.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "spend", title: "Spent this month", used: 118.73, unit: .usd,
                    caption: "organization billing", isHeadline: true),
                UsageMetric(id: "product-chat", title: "Chat models", used: 74.10,
                            unit: .usd),
                UsageMetric(id: "product-embeddings", title: "Embeddings", used: 31.55,
                            unit: .usd),
                UsageMetric(id: "product-images", title: "Images", used: 13.08, unit: .usd),
            ],
            notes: ["Billing usage requires the organization usage endpoint to be "
                  + "enabled for this key."]))

        states[deepInfra.id] = .loaded(UsageSnapshot(
            accountID: deepInfra.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "spend", title: "Spent this month", used: 9.42, limit: 25,
                    remaining: 15.58, unit: .usd, caption: "key limit",
                    isHeadline: true),
                UsageMetric(id: "requests", title: "Requests", used: 3_204,
                            unit: .requests),
            ]))

        states[novita.id] = .loaded(UsageSnapshot(
            accountID: novita.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "balance", title: "Credit balance", remaining: 100.00,
                    unit: .usd, caption: "top-up + bonus", isHeadline: true),
                UsageMetric(id: "cash", title: "Top-up balance", remaining: 80.00,
                            unit: .usd),
                UsageMetric(id: "bonus", title: "Bonus credit", remaining: 20.00,
                            unit: .usd),
                UsageMetric(id: "outstanding", title: "Amount due", used: 12.50,
                            unit: .usd),
            ]))

        // Pushed well past the warn threshold so the severity ramp is visible
        // in a normal capture rather than only in the states screen.
        let sambaish = Account(providerID: "openai", nickname: "OpenAI (near cap)")
        states[sambaish.id] = .loaded(UsageSnapshot(
            accountID: sambaish.id, fetchedAt: now,
            metrics: [
                UsageMetric(
                    id: "spend", title: "Spent this month", used: 940.00, limit: 1000,
                    remaining: 60.00, unit: .usd, caption: "hard limit",
                    isHeadline: true),
                UsageMetric(id: "tokens", title: "Tokens", used: 92_100_000,
                            unit: .tokens),
            ]))

        var history: [UUID: [HistoryPoint]] = [:]
        history[openRouter.id] = (0..<24).map { (step: Int) -> HistoryPoint in
            let hour = Double(step)
            let wobble = Double(step % 3) * 0.4
            let balance: Double = 50 - hour * 1.72 - wobble
            return HistoryPoint(
                date: now.addingTimeInterval((hour - 23) * 3600),
                value: balance, unit: .usd, fraction: 1 - balance / 50, remaining: balance)
        }
        // Climbing toward the cap, so the "full at …" forecast shows.
        history[sambaish.id] = (0..<10).map { (step: Int) -> HistoryPoint in
            let fraction: Double = 0.80 + Double(step) * 0.0135
            return HistoryPoint(
                date: now.addingTimeInterval(Double(step - 10) * 3600),
                value: 1000 * (1 - fraction), unit: .usd,
                fraction: fraction, remaining: 1000 * (1 - fraction))
        }

        // OQ_SCREEN=states puts the non-happy cards first so the error and
        // loading treatments can be inspected without scrolling.
        if screen == "states" {
            let loading = Account(providerID: "openai", nickname: "OpenAI org")
            states[loading.id] = .loading
            return ([groq, loading, openRouter], states, history)
        }

        let zai = Account(providerID: "zai", nickname: "GLM Coding Pro")
        states[zai.id] = .loaded(UsageSnapshot(
            accountID: zai.id, fetchedAt: now, label: "Pro plan",
            metrics: [
                UsageMetric(id: "window-0", title: "5-hour window", used: 41, limit: 100,
                            remaining: 59, unit: .percent,
                            resetsAt: now.addingTimeInterval(3600 * 3 + 600),
                            caption: "prompts", isHeadline: true),
                UsageMetric(id: "window-1", title: "Weekly window", used: 22, limit: 100,
                            remaining: 78, unit: .percent,
                            resetsAt: now.addingTimeInterval(86_400 * 4), caption: "prompts"),
            ]))
        // A slow climb that the window reset outruns: "lasts until reset".
        history[zai.id] = (0..<4).map { (step: Int) -> HistoryPoint in
            let hour = Double(step)
            return HistoryPoint(
                date: now.addingTimeInterval((hour - 4) * 3600),
                value: 5 + hour * 9, unit: .percent,
                fraction: 0.05 + hour * 0.09)
        }
        let claude = Account(providerID: "claude-plan", nickname: "Claude Max")
        var claudeMetrics = [
            UsageMetric(id: "five-hour", title: "5-hour window", used: 64, limit: 100, remaining: 36,
                        unit: .percent, resetsAt: now.addingTimeInterval(2 * 3600 + 900),
                        caption: "session limit"),
            UsageMetric(id: "weekly", title: "Weekly limit", used: 31, limit: 100, remaining: 69,
                        unit: .percent, resetsAt: now.addingTimeInterval(4 * 86_400),
                        caption: "all models"),
            UsageMetric(id: "weekly-opus", title: "Weekly · Opus", used: 12, limit: 100, remaining: 88,
                        unit: .percent, resetsAt: now.addingTimeInterval(4 * 86_400),
                        caption: "model limit"),
        ]
        ClaudeSubscriptionProvider.markTightest(&claudeMetrics)
        states[claude.id] = .loaded(UsageSnapshot(
            accountID: claude.id, fetchedAt: now, label: "Personal", metrics: claudeMetrics))
        let eleven = Account(providerID: "elevenlabs", nickname: "ElevenLabs")
        states[eleven.id] = .loaded(UsageSnapshot(
            accountID: eleven.id, fetchedAt: now,
            metrics: [
                UsageMetric(id: "credits", title: "Credits left", used: 71_400, limit: 100_000,
                            remaining: 28_600, unit: .credits,
                            resetsAt: now.addingTimeInterval(86_400 * 11),
                            caption: "Creator plan", isHeadline: true),
            ]))

        return ([claude, openRouter, zai, mistral, openCode, eleven, anthropic, together, moonshot,
                 novita, deepInfra, sambaish, deepSeek, groq], states, history)
    }
}
