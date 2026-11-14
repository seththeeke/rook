import Foundation
import Testing
import RookModels
@testable import RookNetworking

@Suite("Live API")
struct LiveRookAPITests {
    private func api(_ server: StubServer) -> LiveRookAPI {
        LiveRookAPI(client: server.client(retry: .none))
    }

    @Test func missingGlobalMetricsMeansEmpty() async throws {
        let server = StubServer()
        server.respond { _ in .json(404, #"{"error":"Global metrics not found"}"#) }
        #expect(try await api(server).fetchGlobalMetrics() == .empty)
    }

    @Test func otherMetricsErrorsPropagate() async {
        let server = StubServer()
        server.respond { _ in .json(500, "") }
        await #expect(throws: APIError.server(status: 500)) {
            try await api(server).fetchGlobalMetrics()
        }
    }

    @Test func routesEachCallToItsEndpoint() async throws {
        let server = StubServer()
        let log = RequestLog()
        let workout = #"{"workoutInstanceId":"w","status":"in_progress","startedAt":"2026-03-14T00:00:00Z","exercises":[]}"#
        server.respond { request in
            log.append(request)
            switch (request.httpMethod ?? "", request.url?.path() ?? "") {
            case ("GET", "/users/me"), ("PATCH", "/users/me"):
                return .json(200, #"{"userId":"u","username":"n"}"#)
            case ("DELETE", "/users/me"): return .json(204, "")
            case ("GET", "/users/me/gyms"): return .json(200, #"{"gyms":[],"defaultGymId":null}"#)
            case ("POST", "/users/me/gyms"): return .json(201, #"{"gymId":"g","name":"My Gym","equipmentTypes":[]}"#)
            case ("GET", "/metrics/me/exercises"), ("GET", "/exercises"): return .json(200, "[]")
            case ("GET", "/workout-instances"): return .json(200, #"{"items":[]}"#)
            default: return .json(200, workout)
            }
        }
        let api = api(server)
        _ = try await api.fetchProfile()
        _ = try await api.updateProfile(.init(weightUnit: .kg))
        try await api.deleteAccount()
        _ = try await api.fetchGyms()
        _ = try await api.createGym(.init(name: "My Gym", equipmentTypes: []))
        _ = try await api.fetchExerciseMetrics()
        _ = try await api.fetchExercises(muscleGroup: "chest", search: nil)
        _ = try await api.fetchWorkouts(limit: 20, nextToken: nil)
        _ = try await api.fetchWorkout(id: "w")
        _ = try await api.createWorkout(.init(exercises: [], source: .manual))
        _ = try await api.updateWorkout(id: "w", .cancel)
        let calls = log.requests.map { "\($0.httpMethod!) \($0.url!.path())" }
        #expect(calls == [
            "GET /users/me", "PATCH /users/me", "DELETE /users/me", "GET /users/me/gyms", "POST /users/me/gyms",
            "GET /metrics/me/exercises", "GET /exercises", "GET /workout-instances", "GET /workout-instances/w",
            "POST /workout-instances", "PATCH /workout-instances/w",
        ])
    }
}
