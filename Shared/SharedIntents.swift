import ActivityKit
import AppIntents
import Foundation

/// Compiled into both the app and the widget extension: a control or Live
/// Activity can only run an intent that exists in the extension, and the
/// system then performs it in the app.

/// Opens Open Quota on the overview. Backs the Control Center / Lock Screen /
/// Action button control.
struct OpenOverviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Open AI Usage"
    static let description = IntentDescription("Opens Open Quota on the overview.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

/// Re-reads every provider from a widget's ↻ button. A `LiveActivityIntent`
/// so the system performs it in the app's process, where the providers and
/// keys live; the extension only declares it.
struct RefreshFromWidgetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh AI Usage"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await WidgetRefresher.run()
        return .result()
    }
}

/// Set by the app at launch; nil inside the widget extension.
enum WidgetRefresher {
    @MainActor static var handler: (() async -> Void)?

    @MainActor static func run() async { await handler?() }
}

/// The Live Activity for one account's headline allowance.
struct UsageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var fraction: Double
        var valueText: String
        var title: String
        var resetsAt: Date?
        var paceText: String?
        var updatedAt: Date
    }

    var accountID: UUID
    var nickname: String
    var providerName: String
    var tintHex: String
}
