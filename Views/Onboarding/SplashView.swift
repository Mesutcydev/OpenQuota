import SwiftUI

/// Launch animation: a short terminal boot sequence that dissolves into the
/// app. About 1.7 s, tap to skip, static under Reduce Motion.
struct SplashView: View {
    /// Shown in the second boot line.
    let providerCount: Int
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var leaving = false
    @State private var finished = false

    private let word = "openquota"
    private let typeStart = 0.12
    private let perChar = 0.042
    private var typeEnd: Double { typeStart + Double(word.count) * perChar }

    private var lines: [(tag: String, text: String)] {
        [("ok", "keychain unlocked"),
         ("ok", "\(providerCount) providers mounted"),
         ("ok", "dashboard ready")]
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || leaving)) { context in
            let t = reduceMotion ? 10 : context.date.timeIntervalSince(start)
            scene(t)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .scaleEffect(leaving ? 1.05 : 1)
        .blur(radius: leaving ? 8 : 0)
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.75))
            finish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open Quota")
        .accessibilityAddTraits(.isStaticText)
    }

    private func scene(_ t: Double) -> some View {
        let typing = t < typeEnd
        let meter = Motion.beat(t, from: 0.55, duration: 0.95)

        return VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 0) {
                Text("❯ ")
                    .foregroundStyle(Theme.brand)
                    .opacity(Motion.beat(t, from: 0, duration: 0.18))
                Text(Motion.typed(word, t, from: typeStart, perChar: perChar))
                    .foregroundStyle(Theme.ink)
                Text("▌")
                    .foregroundStyle(Theme.brand)
                    .opacity(Motion.cursorOn(t, typing: typing) ? 1 : 0)
            }
            .font(.mono(size: 34, weight: .semibold))

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 8) {
                        HStack(spacing: 0) {
                            Text("[ ")
                            Text(line.tag).foregroundStyle(Theme.brand).fontWeight(.bold)
                            Text(" ]")
                        }
                        .foregroundStyle(Theme.inkTertiary)
                        Text(line.text).foregroundStyle(Theme.inkSecondary)
                    }
                    .reveal(Motion.beat(t, from: 0.55 + Double(index) * 0.2, duration: 0.3))
                }
            }
            .font(.mono(.footnote))

            VStack(alignment: .leading, spacing: 6) {
                SegmentedMeter(fraction: meter, height: 6, segment: 5, gap: 2,
                               tint: Theme.brand, showsSeverity: false)
                HStack {
                    Text("booting")
                    Spacer()
                    Text("\(Int((meter * 100).rounded()))%").monospacedDigit()
                }
                .font(.mono(.caption2))
                .foregroundStyle(Theme.inkTertiary)
            }
            .opacity(Motion.beat(t, from: 0.45, duration: 0.3))
        }
        .frame(width: 270, alignment: .leading)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.38)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.38))
            onFinish()
        }
    }
}
