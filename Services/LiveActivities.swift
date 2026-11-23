import ActivityKit
import Foundation

/// Starts, updates and ends the per-account Live Activity. Updates ride on
/// ordinary refreshes (foreground and background); there is no push server,
/// so the activity is as fresh as the last read.
@MainActor
enum LiveActivities {
    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isRunning(for accountID: UUID) -> Bool {
        Activity<UsageActivityAttributes>.activities.contains { $0.attributes.accountID == accountID }
    }

    static func state(for snapshot: UsageSnapshot, pace: PaceForecast?) -> UsageActivityAttributes.ContentState? {
        guard let headline = snapshot.headline, let fraction = headline.fraction else { return nil }
        let value = headline.unit == .percent
            ? "\(Int((fraction * 100).rounded()))%"
            : MetricText.value(headline)
        return .init(fraction: fraction, valueText: value, title: headline.title,
                     resetsAt: headline.resetsAt, paceText: pace?.text(),
                     updatedAt: snapshot.fetchedAt)
    }

    @discardableResult
    static func start(account: Account, descriptor: ProviderDescriptor,
                      snapshot: UsageSnapshot, pace: PaceForecast?) -> Bool {
        guard isAvailable, !isRunning(for: account.id),
              let state = state(for: snapshot, pace: pace) else { return false }
        let attributes = UsageActivityAttributes(
            accountID: account.id, nickname: account.nickname,
            providerName: descriptor.name, tintHex: descriptor.tintHex)
        let content = ActivityContent(state: state, staleDate: staleDate(state))
        return (try? Activity.request(attributes: attributes, content: content)) != nil
    }

    static func update(accountID: UUID, snapshot: UsageSnapshot, pace: PaceForecast?) {
        guard let state = state(for: snapshot, pace: pace) else { return }
        for activity in Activity<UsageActivityAttributes>.activities
        where activity.attributes.accountID == accountID {
            Task { await activity.update(ActivityContent(state: state, staleDate: staleDate(state))) }
        }
    }

    static func end(accountID: UUID) {
        for activity in Activity<UsageActivityAttributes>.activities
        where activity.attributes.accountID == accountID {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Marked stale after two hours without a read, so the Lock Screen dims
    /// it rather than presenting old numbers as current.
    private static func staleDate(_ state: UsageActivityAttributes.ContentState) -> Date {
        state.updatedAt.addingTimeInterval(2 * 3600)
    }
}
