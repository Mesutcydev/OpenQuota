import SwiftUI

/// First-run walkthrough: four pages, each with a live mini-demo of the
/// feature it describes, ending on "connect a provider".
struct OnboardingView: View {
    /// False while the splash is still on top; scenes wait for the reveal
    /// so the first one is not half-played by the time it is seen.
    var isRevealed = true
    /// Called with `true` when the user chose to connect a provider now.
    let onFinish: (_ connect: Bool) -> Void

    @State private var page = 0
    @State private var appeared = false

    private let pages = OnboardingPage.all
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 22)
                .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index], index: index, total: pages.count,
                                       isActive: page == index && appeared)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .fontDesign(.monospaced)
        .sensoryFeedback(.selection, trigger: page)
        .onAppear { if isRevealed { appeared = true } }
        .onChange(of: isRevealed) { _, revealed in if revealed { appeared = true } }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 4) {
                Text("❯").foregroundStyle(Theme.brand)
                Text("setup").foregroundStyle(Theme.inkSecondary)
                Text("[\(page + 1)/\(pages.count)]")
                    .foregroundStyle(Theme.inkTertiary)
                    .contentTransition(.numericText(value: Double(page)))
            }
            .font(.mono(.caption, weight: .semibold))
            .animation(.snappy, value: page)
            Spacer()
            Button { onFinish(false) } label: {
                Text("skip")
                    .font(.mono(.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Theme.surface, in: Capsule())
                    .overlay { GlassRim(shape: Capsule()) }
            }
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
                .accessibilityLabel("Skip introduction")
        }
        .frame(height: 36)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.brand : Theme.track)
                        .frame(width: index == page ? 26 : 8, height: 6)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")

            Button {
                if isLast {
                    onFinish(true)
                } else {
                    withAnimation(.settle) { page += 1 }
                }
            } label: {
                ZStack {
                    Text(isLast ? "connect a provider" : "continue")
                        .font(.mono(.headline, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .contentTransition(.opacity)
                        .padding(.horizontal, 60)
                    HStack {
                        Spacer()
                        Image(systemName: isLast ? "plus" : "arrow.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: page)
                            .frame(width: 40, height: 40)
                            .background(Theme.onAccent.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .padding(.trailing, 5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 4,
                                                               style: .continuous))
                .animation(.snappy, value: isLast)
            }
            .buttonStyle(PressableCardStyle())
            .sensoryFeedback(.impact(weight: .medium), trigger: isLast ? page : -1)
            .accessibilityLabel(isLast ? "Connect a provider" : "Continue")

            Button("explore first") { onFinish(false) }
                .font(.mono(.footnote, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .opacity(isLast ? 1 : 0)
                .disabled(!isLast)
                .accessibilityHidden(!isLast)
                .frame(height: 20)
        }
    }
}

// MARK: - Page

struct OnboardingPage {
    let eyebrow: String
    let title: String
    let body: String
    let scene: Scene
    /// How long the scene runs, so Reduce Motion can show its last frame.
    let length: Double

    enum Scene { case overview, alerts, privacy, glance }

    static let all: [OnboardingPage] = [
        OnboardingPage(
            eyebrow: "overview",
            title: "every ai bill,\none glance",
            body: "Credits, spend and plan limits from \(ProviderRegistry.all.count) providers, side by side on one dashboard.",
            scene: .overview, length: 2.2),
        OnboardingPage(
            eyebrow: "alerts",
            title: "limits, before\nthey bite",
            body: "Calm until it matters. Amber at 75%, red at 90%, and a nudge before a window runs dry.",
            scene: .alerts, length: 4.0),
        OnboardingPage(
            eyebrow: "privacy",
            title: "your keys never\nleave this iphone",
            body: "Stored in the Keychain and sent only to their own provider. No Open Quota server, no analytics.",
            scene: .privacy, length: 3.6),
        OnboardingPage(
            eyebrow: "at a glance",
            title: "home screen,\nlock screen, island",
            body: "Widgets and Live Activities keep the numbers in view without opening the app.",
            scene: .glance, length: 2.4),
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let total: Int
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SceneClock(isActive: isActive, settledTime: page.length + 1) { t in
                scene(t)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 22)
            .accessibilityHidden(true)

            copy
                .padding(.horizontal, 26)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func scene(_ t: Double) -> some View {
        switch page.scene {
        case .overview: OverviewScene(t: t)
        case .alerts: AlertsScene(t: t)
        case .privacy: PrivacyScene(t: t)
        case .glance: GlanceScene(t: t)
        }
    }

    /// Title and body rise in, staggered, each time the page becomes active.
    private var copy: some View {
        SceneClock(isActive: isActive, settledTime: 2) { t in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(String(format: "%02d", index + 1)).foregroundStyle(Theme.brand)
                    Text("/ \(page.eyebrow)")
                }
                .eyebrow()
                .reveal(Motion.beat(t, from: 0.0, duration: 0.4))

                Text(page.title)
                    .font(.mono(size: 27, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(Motion.beat(t, from: 0.08, duration: 0.45), distance: 14)
                    .accessibilityAddTraits(.isHeader)

                Text(page.body)
                    .font(.mono(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(Motion.beat(t, from: 0.18, duration: 0.45), distance: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 190, alignment: .top)
    }
}
