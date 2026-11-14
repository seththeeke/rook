import Foundation
import Testing
import RookAuth
import RookModels
import RookNetworking
@testable import RookFeatures

@MainActor
@Suite("App model")
struct AppModelTests {
    let auth = FakeAuth()
    let api = FakeAPI()
    let biometrics = FakeBiometrics()
    let preferences = MemoryPreferences()
    let clock = MutableClock()

    func makeModel() -> AppModel {
        AppModel(auth: auth, api: api, biometrics: biometrics, preferences: preferences, clock: clock.clock, relockAfter: 300)
    }

    @Test func noSessionShowsSignIn() async {
        auth.hasSessionResult = false
        let model = makeModel()
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(api.calls.get().isEmpty)
    }

    @Test func onboardedUserIsReady() async {
        api.profile.onboardingCompletedAt = Date()
        let model = makeModel()
        await model.start()
        #expect(model.phase == .ready(api.profile))
        #expect(model.profile?.username == "lifter")
        #expect(!model.isLocked)
    }

    @Test func newUserGoesToOnboarding() async {
        let model = makeModel()
        await model.start()
        #expect(model.phase == .onboarding(api.profile))
        let done = UserProfile(userId: "u1", username: "lifter", onboardingCompletedAt: Date())
        model.completeOnboarding(with: done)
        #expect(model.phase == .ready(done))
    }

    @Test func expiredSessionSignsOutWithNotice() async {
        api.fail(.profile, with: APIError.unauthorized)
        var cleanedUp = false
        let model = makeModel()
        model.onSignedOut = { cleanedUp = true }
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(model.signOutNotice == AuthNotice.sessionExpired)
        #expect(auth.calls.get() == ["signOut"])
        #expect(cleanedUp)
    }

    @Test func missingProfileAndNetworkErrorsAreRetryable() async {
        api.fail(.profile, with: APIError.notFound("Profile"))
        let model = makeModel()
        await model.start()
        guard case .failed(let message) = model.phase else { Issue.record("expected failure"); return }
        #expect(message.contains("profile"))

        api.fail(.profile, with: APIError.network(.notConnectedToInternet))
        await model.loadProfile()
        #expect(model.phase == .failed(APIError.network(.notConnectedToInternet).userMessage))

        api.succeed(.profile)
        await model.loadProfile()
        #expect(model.profile != nil)
    }

    @Test func biometricLockOnLaunchAndUnlock() async {
        preferences.biometricUnlockEnabled = true
        api.profile.onboardingCompletedAt = Date()
        let model = makeModel()
        await model.start()
        #expect(model.isLocked)
        biometrics.succeeds = false
        await model.unlock()
        #expect(model.isLocked)
        #expect(model.unlockError != nil)
        biometrics.succeeds = true
        await model.unlock()
        #expect(!model.isLocked)
        #expect(model.unlockError == nil)
    }

    @Test func lockIgnoredWhenDeviceLacksBiometrics() async {
        preferences.biometricUnlockEnabled = true
        biometrics.kind = nil
        let model = makeModel()
        await model.start()
        #expect(!model.isLocked)
        #expect(!model.biometricLockActive)
    }

    @Test func relocksOnlyAfterBeingAwayLongEnough() async {
        preferences.biometricUnlockEnabled = true
        api.profile.onboardingCompletedAt = Date()
        let model = makeModel()
        await model.start()
        await model.unlock()

        model.didEnterBackground()
        clock.advance(120)
        model.willEnterForeground()
        #expect(!model.isLocked)

        model.didEnterBackground()
        clock.advance(301)
        model.willEnterForeground()
        #expect(model.isLocked)
    }

    @Test func foregroundWithoutBackgroundIsIgnored() async {
        preferences.biometricUnlockEnabled = true
        let model = makeModel()
        await model.start()
        await model.unlock()
        model.willEnterForeground()
        #expect(!model.isLocked)
    }

    @Test func signInClearsNoticeAndLoads() async {
        auth.hasSessionResult = false
        let model = makeModel()
        await model.start()
        await model.signOut(notice: "bye")
        #expect(model.signOutNotice == "bye")
        await model.didSignIn()
        #expect(model.signOutNotice == nil)
        #expect(model.profile != nil)
    }

    @Test func profileChangesOnlyApplyWhenReady() async {
        let model = makeModel()
        await model.start() // onboarding
        var changed = api.profile
        changed.weightUnit = .kg
        model.profileDidChange(changed)
        #expect(model.phase == .onboarding(api.profile))

        model.completeOnboarding(with: api.profile)
        model.profileDidChange(changed)
        #expect(model.profile?.preferredUnit == .kg)
    }

    @Test func sessionExpiredHelper() async {
        let model = makeModel()
        await model.start()
        await model.sessionExpired()
        #expect(model.phase == .signedOut)
        #expect(model.signOutNotice == AuthNotice.sessionExpired)
    }
}
