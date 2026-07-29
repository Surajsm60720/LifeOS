import Foundation
import LocalAuthentication
import SwiftUI

enum AppLockMode: String {
    case off
    case biometric

    var systemImage: String {
        switch self {
        case .off: return "lock.open"
        case .biometric:
            switch LAContext().biometryType {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            case .none: return "lock.shield"
            @unknown default: return "lock.shield"
            }
        }
    }
}

@MainActor
@Observable
final class AppLockManager {
    static let storageKey = "appLockMode"

    private(set) var isLocked: Bool
    private(set) var authError: String?

    /// Locking always allows passcode fallback, so a failed or unavailable
    /// biometric scan can never permanently lock the owner out of their data.
    private static let policy: LAPolicy = .deviceOwnerAuthentication

    private(set) var mode: AppLockMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let stored = AppLockMode(rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? "") ?? .off
        self.mode = stored
        // Start locked so the first rendered frame is the lock screen, never app content.
        self.isLocked = stored != .off
    }

    var isEnabled: Bool { mode != .off }

    var biometryName: String {
        switch LAContext().biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Passcode"
        @unknown default: return "Biometrics"
        }
    }

    /// Whether the device can authenticate at all (biometrics or passcode).
    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(Self.policy, error: nil)
    }

    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
        authError = nil
    }

    func authenticate() {
        guard isLocked else { return }
        evaluate(reason: "Unlock LifeOS") { [weak self] success, message in
            guard let self else { return }
            if success {
                self.isLocked = false
                self.authError = nil
            } else {
                self.authError = message
            }
        }
    }

    /// Turning the lock on *or* off requires proving device ownership, so someone
    /// holding a briefly-unlocked phone can't quietly disable protection.
    func setEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        guard enabled != isEnabled else {
            completion(true)
            return
        }

        let reason = enabled
            ? "Confirm identity to turn on App Lock"
            : "Confirm identity to turn off App Lock"

        evaluate(reason: reason) { [weak self] success, _ in
            guard let self else { return }
            if success {
                self.mode = enabled ? .biometric : .off
                self.isLocked = false
                self.authError = nil
            }
            completion(success)
        }
    }

    private func evaluate(reason: String, completion: @escaping @MainActor (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(Self.policy, error: &error) else {
            completion(false, error?.localizedDescription ?? "Authentication is unavailable on this device.")
            return
        }

        // `evaluatePolicy` resumes on a background executor; hop back to the main
        // actor before touching `isLocked`, `authError`, or `mode`.
        Task { @MainActor in
            do {
                let success = try await context.evaluatePolicy(Self.policy, localizedReason: reason)
                completion(success, success ? nil : "Authentication failed.")
            } catch let policyError {
                completion(false, policyError.localizedDescription)
            }
        }
    }
}
