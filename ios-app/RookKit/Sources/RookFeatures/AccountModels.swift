import Foundation
import Observation
import RookFormatting
import RookModels
import RookNetworking

/// First-run setup: pick the equipment you train with; creates "My Gym" and marks onboarding complete.
@MainActor
@Observable
public final class OnboardingModel {
    public var selected: Set<EquipmentType> = Set(EquipmentType.allCases)
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    private let api: RookAPI
    private let clock: Clock
    /// Remembered so a retry after a failed profile update doesn't create a second gym.
    private var createdGymId: String?

    public init(api: RookAPI, clock: Clock = .system) {
        self.api = api
        self.clock = clock
    }

    public var canFinish: Bool { !selected.isEmpty && !isWorking }

    public func toggle(_ type: EquipmentType) {
        if selected.contains(type) { selected.remove(type) } else { selected.insert(type) }
    }

    public func apply(_ preset: EquipmentType.Preset) {
        selected = Set(preset.equipment)
    }

    public func isPresetActive(_ preset: EquipmentType.Preset) -> Bool {
        selected == Set(preset.equipment)
    }

    /// Returns the updated profile on success.
    public func finish() async throws -> UserProfile? {
        guard canFinish else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let gymId: String
            if let createdGymId {
                gymId = createdGymId
            } else {
                // Keep the catalog's canonical order regardless of tap order.
                let equipment = EquipmentType.allCases.filter(selected.contains).map(\.rawValue)
                gymId = try await api.createGym(CreateGymRequest(name: "My Gym", equipmentTypes: equipment)).gymId
                createdGymId = gymId
            }
            return try await api.updateProfile(
                UserProfileUpdate(defaultGymId: gymId, onboardingCompletedAt: clock.now())
            )
        } catch {
            if isSessionExpired(error) { throw error }
            errorMessage = userMessage(for: error)
            return nil
        }
    }

    /// Skips choosing: all equipment, same as the web app.
    public func skip() async throws -> UserProfile? {
        selected = Set(EquipmentType.allCases)
        return try await finish()
    }
}

/// What the simplified profile shows.
public struct ProfileSummary: Equatable, Sendable {
    public let handle: String
    public let displayName: String
    public let memberSince: String?
    public let initials: String

    public init(profile: UserProfile, calendar: Calendar = .current, locale: Locale = .current) {
        handle = "@\(profile.username)"
        displayName = profile.resolvedDisplayName
        memberSince = profile.createdAt.map { RookFormat.monthYear($0, calendar: calendar, locale: locale) }
        let words = displayName.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        initials = letters.isEmpty ? "?" : letters.joined()
    }
}

/// Settings: units, biometric unlock, sign out, account deletion.
@MainActor
@Observable
public final class SettingsModel {
    public private(set) var profile: UserProfile
    public private(set) var biometricEnabled: Bool
    public private(set) var isSavingUnit = false
    public private(set) var isDeleting = false
    public private(set) var errorMessage: String?
    public var deleteAcknowledged = false

    public let biometry: BiometryKind?
    public let appVersion: String

    private let api: RookAPI
    private let biometrics: BiometricAuthenticating
    private let preferences: AppPreferences
    private let onProfileChanged: @MainActor (UserProfile) -> Void
    private let onSessionExpired: @MainActor () async -> Void
    private let onAccountDeleted: @MainActor () async -> Void

    public init(
        profile: UserProfile,
        api: RookAPI,
        biometrics: BiometricAuthenticating,
        preferences: AppPreferences,
        appVersion: String,
        onProfileChanged: @escaping @MainActor (UserProfile) -> Void,
        onSessionExpired: @escaping @MainActor () async -> Void,
        onAccountDeleted: @escaping @MainActor () async -> Void
    ) {
        self.profile = profile
        self.api = api
        self.biometrics = biometrics
        self.preferences = preferences
        self.appVersion = appVersion
        self.onProfileChanged = onProfileChanged
        self.onSessionExpired = onSessionExpired
        self.onAccountDeleted = onAccountDeleted
        self.biometry = biometrics.availableBiometry()
        self.biometricEnabled = preferences.biometricUnlockEnabled && biometry != nil
    }

    public var weightUnit: WeightUnit { profile.preferredUnit }

    /// Optimistically switches units; rolls back if the server rejects it.
    public func setWeightUnit(_ unit: WeightUnit) async {
        guard unit != profile.preferredUnit, !isSavingUnit else { return }
        let previous = profile
        profile.weightUnit = unit
        isSavingUnit = true
        errorMessage = nil
        defer { isSavingUnit = false }
        do {
            let updated = try await api.updateProfile(UserProfileUpdate(weightUnit: unit))
            profile = updated
            onProfileChanged(updated)
        } catch {
            profile = previous
            if isSessionExpired(error) { await onSessionExpired(); return }
            errorMessage = "Couldn't change units. \(userMessage(for: error))"
        }
    }

    /// Enabling requires a successful biometric check so users can't lock themselves out.
    public func setBiometricEnabled(_ enabled: Bool) async {
        guard let biometry else { return }
        errorMessage = nil
        if enabled {
            guard await biometrics.authenticate(reason: "Turn on \(biometry.label) for Rook") else {
                biometricEnabled = false
                return
            }
        }
        preferences.biometricUnlockEnabled = enabled
        biometricEnabled = enabled
    }

    public func deleteAccount() async {
        guard deleteAcknowledged, !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await api.deleteAccount()
            preferences.biometricUnlockEnabled = false
            await onAccountDeleted()
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return }
            errorMessage = "Couldn't delete your account. \(userMessage(for: error))"
        }
    }
}
