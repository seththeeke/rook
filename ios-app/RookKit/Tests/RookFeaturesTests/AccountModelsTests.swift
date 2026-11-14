import Foundation
import Testing
import RookModels
import RookNetworking
@testable import RookFeatures

@MainActor
@Suite("Onboarding")
struct OnboardingModelTests {
    let api = FakeAPI()
    let clock = MutableClock()

    @Test func createsGymInCanonicalOrderThenCompletesProfile() async throws {
        let model = OnboardingModel(api: api, clock: clock.clock)
        model.selected = []
        model.toggle(.cardio)
        model.toggle(.dumbbells)
        let profile = try await model.finish()
        #expect(profile?.defaultGymId == "gym-new")
        #expect(profile?.onboardingCompletedAt == clock.now)
        #expect(api.createdGyms.get().first == CreateGymRequest(name: "My Gym", equipmentTypes: ["dumbbells", "cardio"]))
        #expect(api.calls.get() == ["createGym", "updateProfile"])
    }

    @Test func retryAfterProfileFailureReusesGym() async throws {
        api.fail(.updateProfile, with: APIError.server(status: 500))
        let model = OnboardingModel(api: api, clock: clock.clock)
        #expect(try await model.finish() == nil)
        #expect(model.errorMessage != nil)
        api.succeed(.updateProfile)
        #expect(try await model.finish() != nil)
        #expect(api.count(.createGym) == 1)
    }

    @Test func presetsAndEmptySelection() async throws {
        let model = OnboardingModel(api: api, clock: clock.clock)
        model.apply(.minimalist)
        #expect(model.isPresetActive(.minimalist))
        #expect(!model.isPresetActive(.home))
        model.toggle(.dumbbells)
        #expect(!model.canFinish)
        #expect(try await model.finish() == nil)
        #expect(api.calls.get().isEmpty)
    }

    @Test func skipUsesAllEquipment() async throws {
        let model = OnboardingModel(api: api, clock: clock.clock)
        model.apply(.minimalist)
        _ = try await model.skip()
        #expect(api.createdGyms.get().first?.equipmentTypes.count == EquipmentType.allCases.count)
    }

    @Test func expiredSessionPropagates() async {
        api.fail(.createGym, with: APIError.unauthorized)
        let model = OnboardingModel(api: api, clock: clock.clock)
        await #expect(throws: APIError.unauthorized) { try await model.finish() }
    }
}

@Suite("Profile summary")
struct ProfileSummaryTests {
    @Test func formatsHandleNameInitialsAndMemberSince() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let profile = UserProfile(
            userId: "u", username: "lee", displayName: "Lee Lifter",
            createdAt: cal.date(from: DateComponents(year: 2026, month: 3, day: 2))
        )
        let summary = ProfileSummary(profile: profile, calendar: cal, locale: Locale(identifier: "en_US"))
        #expect(summary.handle == "@lee")
        #expect(summary.displayName == "Lee Lifter")
        #expect(summary.initials == "LL")
        #expect(summary.memberSince == "March 2026")
    }

    @Test func fallbacks() {
        let summary = ProfileSummary(profile: UserProfile(userId: "u", username: "solo"))
        #expect(summary.displayName == "solo")
        #expect(summary.initials == "S")
        #expect(summary.memberSince == nil)
    }
}

@MainActor
@Suite("Settings")
struct SettingsModelTests {
    let api = FakeAPI()
    let biometrics = FakeBiometrics()
    let preferences = MemoryPreferences()
    let events = Locked<[String]>([])

    func makeModel() -> SettingsModel {
        SettingsModel(
            profile: api.profile, api: api, biometrics: biometrics, preferences: preferences, appVersion: "1.0 (7)",
            onProfileChanged: { [events] p in events.mutate { $0.append("changed:\(p.preferredUnit.rawValue)") } },
            onSessionExpired: { [events] in events.mutate { $0.append("expired") } },
            onAccountDeleted: { [events] in events.mutate { $0.append("deleted") } }
        )
    }

    @Test func changesUnits() async {
        let model = makeModel()
        await model.setWeightUnit(.kg)
        #expect(model.weightUnit == .kg)
        #expect(api.updates.get() == [UserProfileUpdate(weightUnit: .kg)])
        #expect(events.get() == ["changed:KG"])
        await model.setWeightUnit(.kg) // no-op
        #expect(api.count(.updateProfile) == 1)
    }

    @Test func unitChangeRollsBackOnFailure() async {
        api.fail(.updateProfile, with: APIError.network(.timedOut))
        let model = makeModel()
        await model.setWeightUnit(.kg)
        #expect(model.weightUnit == .lbs)
        #expect(model.errorMessage?.contains("Couldn't change units") == true)
        #expect(events.get().isEmpty)
    }

    @Test func unitChangeWithExpiredSession() async {
        api.fail(.updateProfile, with: APIError.unauthorized)
        await makeModel().setWeightUnit(.kg)
        #expect(events.get() == ["expired"])
    }

    @Test func enablingBiometricsRequiresSuccessfulCheck() async {
        let model = makeModel()
        #expect(model.biometry == .faceID)
        biometrics.succeeds = false
        await model.setBiometricEnabled(true)
        #expect(!model.biometricEnabled)
        #expect(!preferences.biometricUnlockEnabled)

        biometrics.succeeds = true
        await model.setBiometricEnabled(true)
        #expect(model.biometricEnabled)
        #expect(preferences.biometricUnlockEnabled)

        await model.setBiometricEnabled(false)
        #expect(!preferences.biometricUnlockEnabled)
        #expect(biometrics.prompts.get() == 2) // disabling doesn't prompt
    }

    @Test func noBiometryMeansNoToggle() async {
        biometrics.kind = nil
        preferences.biometricUnlockEnabled = true
        let model = makeModel()
        #expect(model.biometry == nil)
        #expect(!model.biometricEnabled)
        await model.setBiometricEnabled(true)
        #expect(biometrics.prompts.get() == 0)
    }

    @Test func deleteRequiresAcknowledgement() async {
        let model = makeModel()
        await model.deleteAccount()
        #expect(api.calls.get().isEmpty)
        model.deleteAcknowledged = true
        preferences.biometricUnlockEnabled = true
        await model.deleteAccount()
        #expect(api.calls.get() == ["delete"])
        #expect(events.get() == ["deleted"])
        #expect(!preferences.biometricUnlockEnabled)
    }

    @Test func deleteFailureShowsError() async {
        api.fail(.delete, with: APIError.server(status: 500))
        let model = makeModel()
        model.deleteAcknowledged = true
        await model.deleteAccount()
        #expect(model.errorMessage?.contains("Couldn't delete") == true)
        #expect(events.get().isEmpty)
        #expect(!model.isDeleting)
    }

    @Test func userDefaultsPreferencesPersist() {
        let suite = "rook.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = UserDefaultsPreferences(defaults: defaults)
        #expect(!prefs.biometricUnlockEnabled)
        prefs.biometricUnlockEnabled = true
        #expect(UserDefaultsPreferences(defaults: defaults).biometricUnlockEnabled)
    }
}
