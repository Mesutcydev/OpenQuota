import SwiftUI

/// Timeline helpers for the scripted splash and onboarding animations.
///
/// Each scene is a pure function of elapsed time `t`, driven by a
/// `TimelineView`. That keeps the choreography in one readable place, lets
/// a scene restart by resetting its start date, and makes Reduce Motion a
/// matter of jumping `t` to the end.
enum Motion {
    /// Progress of a beat that starts at `start` and lasts `duration`,
    /// clamped to 0...1.
    static func progress(_ t: Double, from start: Double, duration: Double) -> Double {
        guard duration > 0 else { return t >= start ? 1 : 0 }
        return min(max((t - start) / duration, 0), 1)
    }

    /// Cubic ease-out: fast start, soft landing.
    static func easeOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return 1 - pow(1 - c, 3)
    }

    /// Eased progress of a beat.
    static func beat(_ t: Double, from start: Double, duration: Double) -> Double {
        easeOut(progress(t, from: start, duration: duration))
    }

    /// Characters of `text` revealed by a typewriter starting at `start`.
    static func typed(_ text: String, _ t: Double, from start: Double, perChar: Double = 0.04) -> String {
        guard t > start else { return "" }
        let count = min(Int((t - start) / perChar), text.count)
        return String(text.prefix(count))
    }

    /// Terminal cursor blink: solid while `typing`, otherwise ~2.4 Hz.
    static func cursorOn(_ t: Double, typing: Bool) -> Bool {
        typing || Int(t * 2.4).isMultiple(of: 2)
    }
}

/// Runs a scene from zero whenever `isActive` turns on. Paused (and frozen at
/// the final frame under Reduce Motion) otherwise.
struct SceneClock<Content: View>: View {
    var isActive: Bool
    /// Time to show when motion is reduced: the end of the scene.
    var settledTime: Double = 10
    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: start == nil || reduceMotion)) { context in
            let t = reduceMotion ? settledTime : start.map { context.date.timeIntervalSince($0) } ?? 0
            content(t)
        }
        .onAppear { if isActive { start = .now } }
        .onChange(of: isActive) { _, active in start = active ? .now : nil }
    }
}

/// Fade-and-rise used to stagger lines in.
extension View {
    func reveal(_ amount: Double, distance: CGFloat = 8) -> some View {
        opacity(amount)
            .offset(y: (1 - amount) * distance)
    }
}
