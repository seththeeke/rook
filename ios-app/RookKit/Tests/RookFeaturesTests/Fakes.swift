import Foundation
import RookAuth
import RookModels
import RookNetworking
@testable import RookFeatures

/// Thread-safe mutable box for fakes.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
    func mutate<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}

struct TestError: Error, Equatable {}

// MARK: - Auth

final class FakeAuth: AuthService, @unchecked Sendable {
    let calls = Locked<[String]>([])
    var hasSessionResult = true
    var signInResults: [Result<SignInOutcome, Error>] = [.success(.signedIn)]
    var failure: Error?

    private func record(_ call: String) throws {
        calls.mutate { $0.append(call) }
        if let failure { throw failure }
    }

    func hasSession() async -> Bool { hasSessionResult }
    func idToken(forceRefresh: Bool) async throws -> String { "token" }

    func signIn(email: String, password: String) async throws -> SignInOutcome {
        try record("signIn:\(email)")
        let result = signInResults.count > 1 ? signInResults.removeFirst() : signInResults[0]
        return try result.get()
    }
    func signUp(email: String, password: String) async throws { try record("signUp:\(email)") }
    func confirmSignUp(email: String, code: String) async throws { try record("confirm:\(code)") }
    func resendSignUpCode(email: String) async throws { try record("resend") }
    func resetPassword(email: String) async throws { try record("reset:\(email)") }
    func confirmResetPassword(email: String, newPassword: String, code: String) async throws {
        try record("confirmReset:\(code)")
    }
    func signOut() async { calls.mutate { $0.append("signOut") } }
}

// MARK: - API

/// Configurable fake backend. Each operation returns its configured result (or throws `failures[op]`)
/// and appends its name to `calls`.
final class FakeAPI: RookAPI, @unchecked Sendable {
    enum Op: String { case profile, updateProfile, delete, gyms, createGym, global, exerciseMetrics, exercises, workouts, workout, create, update }

    let calls = Locked<[String]>([])
    let failures = Locked<[Op: Error]>([:])
    let updates = Locked<[UserProfileUpdate]>([])
    let workoutUpdates = Locked<[(String, UpdateWorkoutRequest)]>([])
    let createdWorkouts = Locked<[CreateWorkoutRequest]>([])
    let createdGyms = Locked<[CreateGymRequest]>([])
    let exerciseQueries = Locked<[(String?, String?)]>([])

    var profile = UserProfile(userId: "u1", username: "lifter", displayName: "Lee Lifter", weightUnit: .lbs, createdAt: Date(timeIntervalSince1970: 1_772_000_000))
    var gyms = GymsListResponse(gyms: [], defaultGymId: nil)
    var global = GlobalMetrics.empty
    var exerciseMetrics: [ExerciseMetricsSummary] = []
    var exercises: [ExerciseCatalogItem] = []
    /// Pages returned in order for `fetchWorkouts` (keyed by incoming nextToken; nil = first page).
    var workoutPages: [String?: WorkoutListPage] = [nil: WorkoutListPage(items: [], nextToken: nil)]
    var workoutsById: [String: WorkoutInstance] = [:]
    var createWorkoutResult: WorkoutInstance?

    private func record(_ op: Op, _ detail: String = "") throws {
        calls.mutate { $0.append(detail.isEmpty ? op.rawValue : "\(op.rawValue):\(detail)") }
        if let error = failures.get()[op] { throw error }
    }

    func fail(_ op: Op, with error: Error) { failures.mutate { $0[op] = error } }
    func succeed(_ op: Op) { failures.mutate { $0[op] = nil } }
    func count(_ op: Op) -> Int { calls.get().filter { $0 == op.rawValue || $0.hasPrefix(op.rawValue + ":") }.count }

    func fetchProfile() async throws -> UserProfile { try record(.profile); return profile }
    func updateProfile(_ update: UserProfileUpdate) async throws -> UserProfile {
        try record(.updateProfile)
        updates.mutate { $0.append(update) }
        if let unit = update.weightUnit { profile.weightUnit = unit }
        if let gym = update.defaultGymId { profile.defaultGymId = gym }
        if let done = update.onboardingCompletedAt { profile.onboardingCompletedAt = done }
        return profile
    }
    func deleteAccount() async throws { try record(.delete) }
    func fetchGyms() async throws -> GymsListResponse { try record(.gyms); return gyms }
    func createGym(_ request: CreateGymRequest) async throws -> Gym {
        try record(.createGym)
        createdGyms.mutate { $0.append(request) }
        return Gym(gymId: "gym-new", name: request.name, equipmentTypes: request.equipmentTypes)
    }
    func fetchGlobalMetrics() async throws -> GlobalMetrics { try record(.global); return global }
    func fetchExerciseMetrics() async throws -> [ExerciseMetricsSummary] { try record(.exerciseMetrics); return exerciseMetrics }
    func fetchExercises(muscleGroup: String?, search: String?) async throws -> [ExerciseCatalogItem] {
        try record(.exercises)
        exerciseQueries.mutate { $0.append((muscleGroup, search)) }
        return exercises.filter { item in
            (muscleGroup == nil || item.muscleGroup == muscleGroup)
                && (search == nil || item.name.localizedCaseInsensitiveContains(search!))
        }
    }
    func fetchWorkouts(limit: Int, nextToken: String?) async throws -> WorkoutListPage {
        try record(.workouts, nextToken ?? "")
        return workoutPages[nextToken] ?? WorkoutListPage(items: [], nextToken: nil)
    }
    func fetchWorkout(id: String) async throws -> WorkoutInstance {
        try record(.workout, id)
        guard let workout = workoutsById[id] else { throw APIError.notFound("Workout") }
        return workout
    }
    func createWorkout(_ request: CreateWorkoutRequest) async throws -> WorkoutInstance {
        try record(.create)
        createdWorkouts.mutate { $0.append(request) }
        return createWorkoutResult ?? WorkoutInstance(
            workoutInstanceId: "w-new", status: .inProgress, source: request.source,
            startedAt: Date(timeIntervalSince1970: 1_773_500_000), gymId: request.gymId, gymName: request.gymName,
            exercises: request.exercises.enumerated().map { i, ex in var e = ex; e.orderIndex = i; return e }
        )
    }
    func updateWorkout(id: String, _ request: UpdateWorkoutRequest) async throws -> WorkoutInstance {
        try record(.update, request.status?.rawValue ?? "progress")
        workoutUpdates.mutate { $0.append((id, request)) }
        return WorkoutInstance(
            workoutInstanceId: id, status: request.status ?? .inProgress,
            startedAt: Date(timeIntervalSince1970: 1_773_500_000), exercises: request.exercises ?? []
        )
    }
}

// MARK: - Device

final class FakeBiometrics: BiometricAuthenticating, @unchecked Sendable {
    var kind: BiometryKind? = .faceID
    var succeeds = true
    let prompts = Locked(0)
    func availableBiometry() -> BiometryKind? { kind }
    func authenticate(reason: String) async -> Bool {
        prompts.mutate { $0 += 1 }
        return succeeds
    }
}

final class MemoryPreferences: AppPreferences, @unchecked Sendable {
    var biometricUnlockEnabled = false
}

final class MutableClock: @unchecked Sendable {
    private let current: Locked<Date>
    init(_ start: Date = Date(timeIntervalSince1970: 1_773_500_000)) { current = Locked(start) }
    var now: Date { current.get() }
    func advance(_ seconds: TimeInterval) { current.mutate { $0 = $0.addingTimeInterval(seconds) } }
    var clock: Clock { Clock { [current] in current.get() } }
}

// MARK: - Builders

extension WorkoutInstance {
    static func completed(
        _ id: String,
        completedAt: Date,
        minutes: Int = 45,
        volume: Double = 1000,
        exercises: [WorkoutExercise] = [WorkoutExercise(exerciseId: "bench", exerciseName: "Bench Press", modality: .setsReps, sets: 3, reps: 8, weight: 100)]
    ) -> WorkoutInstance {
        WorkoutInstance(
            workoutInstanceId: id, status: .completed, source: .manual,
            startedAt: completedAt.addingTimeInterval(TimeInterval(-minutes * 60)), completedAt: completedAt,
            durationMinutes: minutes, totalVolume: volume, exercises: exercises
        )
    }
}
