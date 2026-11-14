import Foundation
import RookModels

/// Every backend operation the app performs, as one protocol so feature models can be tested
/// against a fake. `LiveRookAPI` is the production implementation over `APIClient`.
public protocol RookAPI: Sendable {
    func fetchProfile() async throws -> UserProfile
    func updateProfile(_ update: UserProfileUpdate) async throws -> UserProfile
    func deleteAccount() async throws

    func fetchGyms() async throws -> GymsListResponse
    func createGym(_ request: CreateGymRequest) async throws -> Gym

    /// Global metrics, or `.empty` for users who haven't completed a workout (server returns 404).
    func fetchGlobalMetrics() async throws -> GlobalMetrics
    func fetchExerciseMetrics() async throws -> [ExerciseMetricsSummary]

    func fetchExercises(muscleGroup: String?, search: String?) async throws -> [ExerciseCatalogItem]

    func fetchWorkouts(limit: Int, nextToken: String?) async throws -> WorkoutListPage
    func fetchWorkout(id: String) async throws -> WorkoutInstance
    func createWorkout(_ request: CreateWorkoutRequest) async throws -> WorkoutInstance
    func updateWorkout(id: String, _ request: UpdateWorkoutRequest) async throws -> WorkoutInstance
}

public final class LiveRookAPI: RookAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchProfile() async throws -> UserProfile { try await client.send(Endpoints.getMe) }
    public func updateProfile(_ update: UserProfileUpdate) async throws -> UserProfile {
        try await client.send(Endpoints.updateMe(update))
    }
    public func deleteAccount() async throws { _ = try await client.send(Endpoints.deleteMe) }

    public func fetchGyms() async throws -> GymsListResponse { try await client.send(Endpoints.listGyms) }
    public func createGym(_ request: CreateGymRequest) async throws -> Gym {
        try await client.send(Endpoints.createGym(request))
    }

    public func fetchGlobalMetrics() async throws -> GlobalMetrics {
        do {
            return try await client.send(Endpoints.globalMetrics)
        } catch APIError.notFound {
            return .empty
        }
    }
    public func fetchExerciseMetrics() async throws -> [ExerciseMetricsSummary] {
        try await client.send(Endpoints.exerciseMetrics)
    }

    public func fetchExercises(muscleGroup: String?, search: String?) async throws -> [ExerciseCatalogItem] {
        try await client.send(Endpoints.listExercises(muscleGroup: muscleGroup, search: search))
    }

    public func fetchWorkouts(limit: Int, nextToken: String?) async throws -> WorkoutListPage {
        try await client.send(Endpoints.listWorkouts(limit: limit, nextToken: nextToken))
    }
    public func fetchWorkout(id: String) async throws -> WorkoutInstance {
        try await client.send(Endpoints.getWorkout(id: id))
    }
    public func createWorkout(_ request: CreateWorkoutRequest) async throws -> WorkoutInstance {
        try await client.send(Endpoints.createWorkout(request))
    }
    public func updateWorkout(id: String, _ request: UpdateWorkoutRequest) async throws -> WorkoutInstance {
        try await client.send(Endpoints.updateWorkout(id: id, request))
    }
}
