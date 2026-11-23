import SwiftUI
import UserNotifications

@main
struct OpenQuotaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .tint(Theme.brand)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .environment(\.oledBlack, model.settings.oledBlack)
                .onAppear { appDelegate.router = router }
                .onOpenURL { url in
                    // openquota://account/<uuid> — used by the widget.
                    guard url.scheme == "openquota" else { return }
                    if url.host == "account",
                       let id = UUID(uuidString: url.lastPathComponent),
                       model.account(id: id) != nil {
                        router.open(accountID: id)
                    } else if url.host == "connect" {
                        router.showingConnect = true
                    }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            // Queue the next one first: if this run is cut short, the chain
            // must not break.
            await MainActor.run {
                BackgroundRefresh.schedule(enabled: model.settings.backgroundRefresh)
            }
            await model.refreshAll()
        }
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Routes a tapped threshold alert to its account.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var router: Router?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Self.styleNavigationBars()
        return true
    }

    /// Terminal look reaches the UIKit-drawn titles too.
    private static func styleNavigationBars() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 30, weight: .bold)]
        appearance.titleTextAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["accountID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { router?.open(accountID: id) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var lock = AppLock()
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showSplash = true
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var router = router

        Group {
            // The intro covers everything; not building the tabs under it
            // keeps them out of VoiceOver and off the main thread.
            if showOnboarding {
                Theme.canvas.ignoresSafeArea()
            } else {
                TabView(selection: $router.tab) {
                    Tab("Overview", systemImage: "gauge.with.dots.needle.67percent", value: Router.Tab.overview) {
                        OverviewView()
                    }
                    Tab("Accounts", systemImage: "square.stack.3d.up.fill", value: Router.Tab.accounts) {
                        AccountsView()
                    }
                    Tab("Settings", systemImage: "gearshape.fill", value: Router.Tab.settings) {
                        SettingsView()
                    }
                }
                .tabBarMinimizeBehavior(.never)
            }
        }
        .fontDesign(.monospaced)
        // Behind the lock cover, splash or intro the numbers must not be
        // reachable by VoiceOver either.
        .accessibilityHidden(lock.isLocked || showSplash || showOnboarding)
        .sheet(isPresented: $router.showingConnect) {
            AddAccountView().fontDesign(.monospaced)
                .environment(\.oledBlack, model.settings.oledBlack)
        }
        .overlay {
            if lock.isLocked {
                LockCover { Task { await lock.unlock(enabled: model.settings.requireUnlock) } }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: lock.isLocked)
        .overlay {
            if showOnboarding {
                OnboardingView(isRevealed: !showSplash) { connect in finishOnboarding(connect: connect) }
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.97))))
                    .zIndex(1)
            }
        }
        .overlay {
            if showSplash {
                SplashView(providerCount: model.accounts.isEmpty
                           ? ProviderRegistry.all.count : model.accounts.count) {
                    showSplash = false
                }
                .zIndex(2)
            }
        }
        .onChange(of: router.replayingIntro) { _, replay in
            guard replay else { return }
            router.replayingIntro = false
            withAnimation(.easeOut(duration: 0.3)) { showOnboarding = true }
        }
        .task {
            decideIntro()
            if model.settings.requireUnlock {
                lock.lockIfEnabled(true)
                Task { await lock.unlock(enabled: true) }
            }
            openDemoScreenIfRequested()
            if model.settings.refreshOnLaunch { await model.refreshAll() }
        }
        .onChange(of: scenePhase) { old, phase in
            switch phase {
            case .active:
                Task { await model.refreshIfStale() }
                // Only prompt when coming back from the background: the
                // Face ID sheet itself flips the scene to inactive and back,
                // and re-prompting on that would loop after a cancel.
                if old == .background {
                    Task { await lock.unlock(enabled: model.settings.requireUnlock) }
                }
            case .background:
                BackgroundRefresh.schedule(enabled: model.settings.backgroundRefresh)
                lock.lockIfEnabled(model.settings.requireUnlock)
            default: break
            }
        }
    }

    /// The intro runs once, for a fresh install. Someone who already has
    /// accounts (an update, a restore) has nothing to learn from it.
    private func decideIntro() {
        if DemoData.isEnabled {
            showSplash = DemoData.screen != "onboarding-static"
            showOnboarding = DemoData.screen.hasPrefix("onboarding")
            return
        }
        if !onboardingCompleted {
            if model.accounts.isEmpty {
                showOnboarding = true
            } else {
                onboardingCompleted = true
            }
        }
    }

    private func finishOnboarding(connect: Bool) {
        onboardingCompleted = true
        withAnimation(.easeOut(duration: 0.35)) { showOnboarding = false }
        if connect {
            Task {
                try? await Task.sleep(for: .seconds(0.35))
                router.showingConnect = true
            }
        }
    }

    /// Jumps straight to a screen when launched with OQ_SCREEN, so each state
    /// can be captured without driving the UI by hand.
    private func openDemoScreenIfRequested() {
        guard DemoData.isEnabled else { return }
        switch DemoData.screen {
        case "settings": router.tab = .settings
        case "accounts": router.tab = .accounts
        case "connect": router.showingConnect = true
        case "detail":
            if let first = model.accounts.first { router.open(accountID: first.id) }
        default: break
        }
    }
}
