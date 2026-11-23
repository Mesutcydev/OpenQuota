import BackgroundTasks
import Foundation

/// Keeps widgets, alerts and the Live Activity current while the app is
/// closed. iOS decides when a refresh actually runs — typically every
/// half hour to few hours, based on how often the app is used — so this is a
/// request for the earliest time, not a schedule.
enum BackgroundRefresh {
    static let identifier = "ai.openquota.refresh"

    /// Earliest gap between background reads. Shorter than this mostly gets
    /// ignored by the scheduler and costs battery for no fresher numbers.
    static let interval: TimeInterval = 30 * 60

    static func schedule(enabled: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // Fails on the simulator and when Background App Refresh is off in
        // Settings; both are fine to ignore — foreground refresh still works.
        try? BGTaskScheduler.shared.submit(request)
    }
}
