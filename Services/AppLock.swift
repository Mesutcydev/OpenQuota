import LocalAuthentication
import SwiftUI

/// Optional Face ID / passcode gate. Balances and spend are not secret in
/// the way a password is, but they are private, and the app holds keys that
/// can read an organization's billing.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked = false
    private var isAuthenticating = false

    /// Called when the app leaves the foreground: lock immediately, so the
    /// app switcher snapshot shows the cover rather than the numbers.
    func lockIfEnabled(_ enabled: Bool) {
        if enabled { isLocked = true }
    }

    func unlock(enabled: Bool) async {
        guard enabled else { isLocked = false; return }
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        // deviceOwnerAuthentication falls back to the passcode, so a failed
        // Face ID never locks someone out of their own app.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        let ok = (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: "Unlock Open Quota")) ?? false
        if ok { isLocked = false }
    }

    /// Whether this device can lock at all (no passcode set means no).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }
}

struct LockCover: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text("Open Quota is locked")
                    .font(.headline)
                Button("Unlock with \(AppLock.biometryName)", action: unlock)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 280)
            }
        }
    }
}
