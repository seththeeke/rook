import Foundation
import RookAuth
import RookNetworking

/// Injectable "now", so time-dependent logic is testable.
public struct Clock: Sendable {
    public var now: @Sendable () -> Date
    public init(now: @escaping @Sendable () -> Date) { self.now = now }
    public static let system = Clock { Date() }
}

/// Injectable sleep used for debouncing and delays.
public typealias Sleeper = @Sendable (Duration) async throws -> Void
public let systemSleeper: Sleeper = { try await Task.sleep(for: $0) }

/// A user-presentable message for any error a feature can hit.
public func userMessage(for error: Error) -> String {
    switch error {
    case let api as APIError: api.userMessage
    case let auth as AuthFailure: auth.userMessage
    case let ai as AIStreamError: ai.userMessage
    default: "Something went wrong. Please try again."
    }
}

/// True when the error means the session is gone and the user must sign in again.
public func isSessionExpired(_ error: Error) -> Bool {
    (error as? APIError) == .unauthorized || (error as? AIStreamError) == .unauthorized
}

/// The kind of biometry the device offers (drives labels like "Face ID").
public enum BiometryKind: Sendable, Equatable {
    case faceID, touchID, opticID

    public var label: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        }
    }
}

/// Device biometrics (LocalAuthentication in the app; fakes in tests).
public protocol BiometricAuthenticating: Sendable {
    /// nil when the device has no enrolled biometry.
    func availableBiometry() -> BiometryKind?
    /// Prompts for biometrics with passcode fallback; true on success.
    func authenticate(reason: String) async -> Bool
}

/// Small persisted user preferences.
public protocol AppPreferences: AnyObject, Sendable {
    var biometricUnlockEnabled: Bool { get set }
}

/// UserDefaults-backed preferences.
public final class UserDefaultsPreferences: AppPreferences, @unchecked Sendable {
    static let biometricKey = "rook.biometricUnlockEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var biometricUnlockEnabled: Bool {
        get { defaults.bool(forKey: Self.biometricKey) }
        set { defaults.set(newValue, forKey: Self.biometricKey) }
    }
}
