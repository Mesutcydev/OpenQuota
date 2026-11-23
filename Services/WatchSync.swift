import Foundation
import WatchConnectivity

/// Sends the widget board to a paired Apple Watch. `applicationContext` keeps
/// only the latest value, so the watch always holds the newest reading and
/// nothing queues up while it is out of range.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Last board built; sent again once the session finishes activating.
    private var pending: WidgetBoard?

    private override init() { super.init() }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ board: WidgetBoard) {
        pending = board
        deliver()
    }

    private func deliver() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isWatchAppInstalled, let board = pending,
              let data = try? JSONEncoder().encode(board) else { return }
        try? session.updateApplicationContext(["board": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        deliver()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a switched watch keeps receiving.
        session.activate()
    }
}
