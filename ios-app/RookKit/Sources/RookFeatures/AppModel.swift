import Foundation
import Observation
import RookAuth
import RookModels
import RookNetworking

/// Root state machine: decides whether the user sees sign-in, onboarding, or the app, and whether a
/// biometric lock covers it.
@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable {
        case launching
        case signedOut
        case loadingProfile
        case onboarding(UserProfile)
        case ready(UserProfile)
        case failed(String)
    }

    public private(set) var phase: Phase = .launching
    /// Covers the UI until the user passes Face ID / Touch ID (only when enabled in Settings).
    public private(set) var isLocked = false
    public private(set) var unlockError: String?
    /// Shown on the sign-in screen after an involuntary sign-out.
    public private(set) var signOutNotice: String?

    public let auth: AuthService
    public let api: RookAPI
    public let biometrics: BiometricAuthenticating
    public let preferences: AppPreferences
    private let clock: Clock
    private let relockAfter: TimeInterval
    private var backgroundedAt: Date?
    /// Runs on every sign-out (e.g. to discard a local workout session and its Live Activity).
    public var onSignedOut: (() async -> Void)?

    public init(
        auth: AuthService,
        api: RookAPI,
        biometrics: BiometricAuthenticating,
        preferences: AppPreferences,
        clock: Clock = .system,
        relockAfter: TimeInterval = 5 * 60
    ) {
        self.auth = auth
        self.api = api
        self.biometrics = biometrics
        self.preferences = preferences
        self.clock = clock
        self.relockAfter = relockAfter
    }

    public var profile: UserProfile? {
        switch phase {
        case .ready(let p), .onboarding(let p): p
        default: nil
        }
    }

    /// Whether biometric unlock is both enabled and possible on this device.
    public var biometricLockActive: Bool {
        preferences.biometricUnlockEnabled && biometrics.availableBiometry() != nil
    }

    // MARK: - Lifecycle

    public func start() async {
        guard await auth.hasSession() else {
            phase = .signedOut
            return
        }
        isLocked = biometricLockActive
        await loadProfile()
    }

    public func loadProfile() async {
        phase = .loadingProfile
        do {
            let profile = try await api.fetchProfile()
            phase = profile.needsOnboarding ? .onboarding(profile) : .ready(profile)
        } catch {
            if isSessionExpired(error) {
                await signOut(notice: AuthNotice.sessionExpired)
            } else if case APIError.notFound = error {
                phase = .failed("We couldn't find your profile. Please try again in a moment.")
            } else {
                phase = .failed(userMessage(for: error))
            }
        }
    }

    public func didSignIn() async {
        signOutNotice = nil
        isLocked = false
        await loadProfile()
    }

    public func completeOnboarding(with profile: UserProfile) {
        phase = .ready(profile)
    }

    /// Keeps the root profile current after Settings changes (e.g. weight unit).
    public func profileDidChange(_ profile: UserProfile) {
        if case .ready = phase { phase = .ready(profile) }
    }

    public func signOut(notice: String? = nil) async {
        await auth.signOut()
        await onSignedOut?()
        isLocked = false
        unlockError = nil
        signOutNotice = notice
        phase = .signedOut
    }

    /// Called by features when the API reports the session is gone.
    public func sessionExpired() async {
        await signOut(notice: AuthNotice.sessionExpired)
    }

    // MARK: - Biometric lock

    public func unlock() async {
        unlockError = nil
        if await biometrics.authenticate(reason: "Unlock Rook") {
            isLocked = false
        } else {
            unlockError = "Couldn't verify it's you. Try again or sign in with your password."
        }
    }

    public func didEnterBackground() {
        backgroundedAt = clock.now()
    }

    public func willEnterForeground() {
        defer { backgroundedAt = nil }
        guard let backgroundedAt, biometricLockActive, profile != nil else { return }
        if clock.now().timeIntervalSince(backgroundedAt) >= relockAfter {
            isLocked = true
        }
    }
}

public enum AuthNotice {
    public static let sessionExpired = "Your session expired. Please sign in again."
    public static let accountDeleted = "Your account has been deleted."
}
