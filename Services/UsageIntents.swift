import AppIntents
import Foundation

/// "Hey Siri, check my AI usage" — answers from the last reading the app
/// stored for the widget, so it is instant and needs no network.
struct CheckUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Check AI Usage"
    static let description = IntentDescription(
        "Reads out credit left and the account closest to its limit, as of the last refresh.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = Self.summary(WidgetStore.load())
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }

    static func summary(_ board: WidgetBoard?) -> String {
        guard let board, !board.entries.isEmpty else {
            return "No usage yet. Open Open Quota and connect a provider."
        }
        var parts: [String] = []
        if let total = board.usdTotal {
            parts.append("You have \(Format.currency(total)) of credit left")
        }
        if let hot = board.entries.filter({ $0.fraction != nil })
            .max(by: { ($0.fraction ?? 0) < ($1.fraction ?? 0) }),
           let fraction = hot.fraction {
            var line = "\(hot.nickname) is at \(Int((fraction * 100).rounded()))%"
            if let pace = hot.paceText { line += ". \(pace)" }
            parts.append(line)
        }
        if parts.isEmpty {
            parts.append("\(board.entries.count) accounts connected, none with a balance or limit")
        }
        return parts.joined(separator: ". ") + "."
    }
}

/// Re-reads every provider, then reports. Runs in the background.
struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh AI Usage"
    static let description = IntentDescription("Re-reads every connected provider.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared ?? AppModel()
        await model.refreshAll()
        return .result(dialog: IntentDialog(stringLiteral: CheckUsageIntent.summary(WidgetStore.load())))
    }
}

struct OpenQuotaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckUsageIntent(),
            phrases: [
                "Check my AI usage in \(.applicationName)",
                "How much AI credit is left in \(.applicationName)",
            ],
            shortTitle: "Check Usage",
            systemImageName: "gauge.with.dots.needle.67percent")
        AppShortcut(
            intent: RefreshUsageIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh",
            systemImageName: "arrow.clockwise")
    }
}
