import Foundation
import RookModels

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", patch = "PATCH", put = "PUT", delete = "DELETE"

    /// Methods safe to retry automatically. POST is excluded: retrying a create after an ambiguous
    /// 5xx could create a duplicate workout or gym.
    var isIdempotent: Bool { self != .post }
}

/// Placeholder response type for endpoints that return no body (e.g. 204).
public struct EmptyResponse: Decodable, Equatable, Sendable {
    public init() {}
}

/// A typed description of one API call.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var queryItems: [URLQueryItem]
    public var body: Data?

    public init(method: HTTPMethod, path: String, queryItems: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
    }

    init<Body: Encodable>(method: HTTPMethod, path: String, json body: Body) {
        // Encoding our own request structs cannot fail; a failure here is a programming error.
        let data = try! RookJSON.makeEncoder().encode(body)
        self.init(method: method, path: path, body: data)
    }
}

/// Every backend route Rook uses (see spec §3.3). Paths mirror `packages/cdk/lib/repwise-stack.ts`.
public enum Endpoints {
    // MARK: Users
    public static let getMe = Endpoint<UserProfile>(method: .get, path: "/users/me")
    public static func updateMe(_ update: UserProfileUpdate) -> Endpoint<UserProfile> {
        .init(method: .patch, path: "/users/me", json: update)
    }
    public static let deleteMe = Endpoint<EmptyResponse>(method: .delete, path: "/users/me")

    // MARK: Gyms
    public static let listGyms = Endpoint<GymsListResponse>(method: .get, path: "/users/me/gyms")
    public static func createGym(_ request: CreateGymRequest) -> Endpoint<Gym> {
        .init(method: .post, path: "/users/me/gyms", json: request)
    }

    // MARK: Metrics
    public static let globalMetrics = Endpoint<GlobalMetrics>(method: .get, path: "/metrics/me/global")
    public static let exerciseMetrics = Endpoint<[ExerciseMetricsSummary]>(method: .get, path: "/metrics/me/exercises")

    // MARK: Exercises
    public static func listExercises(muscleGroup: String? = nil, search: String? = nil) -> Endpoint<[ExerciseCatalogItem]> {
        var query: [URLQueryItem] = []
        if let muscleGroup, !muscleGroup.isEmpty { query.append(.init(name: "muscleGroup", value: muscleGroup)) }
        let trimmed = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { query.append(.init(name: "search", value: trimmed)) }
        return .init(method: .get, path: "/exercises", queryItems: query)
    }

    // MARK: Workouts
    /// Lists the user's workouts, newest first. Note: no `status` filter — the server applies it after
    /// the page limit, which yields sparse pages (spec §6.3). Filter client-side instead.
    public static func listWorkouts(limit: Int = 20, nextToken: String? = nil) -> Endpoint<WorkoutListPage> {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))]
        if let nextToken { query.append(.init(name: "nextToken", value: nextToken)) }
        return .init(method: .get, path: "/workout-instances", queryItems: query)
    }
    public static func getWorkout(id: String) -> Endpoint<WorkoutInstance> {
        .init(method: .get, path: "/workout-instances/\(pathEscaped(id))")
    }
    public static func createWorkout(_ request: CreateWorkoutRequest) -> Endpoint<WorkoutInstance> {
        .init(method: .post, path: "/workout-instances", json: request)
    }
    public static func updateWorkout(id: String, _ request: UpdateWorkoutRequest) -> Endpoint<WorkoutInstance> {
        .init(method: .patch, path: "/workout-instances/\(pathEscaped(id))", json: request)
    }

    static func pathEscaped(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? segment
    }
}
