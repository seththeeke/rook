import Foundation
import Testing
import RookModels
@testable import RookNetworking

@Suite("API client")
struct APIClientTests {
    private let profileJSON = #"{"userId":"u1","username":"lifter","createdAt":"2026-03-01T00:00:00.000Z"}"#

    @Test func sendsAuthorizedRequestAndDecodes() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .json(200, profileJSON)
        }
        let profile = try await server.client().send(Endpoints.getMe)
        #expect(profile.username == "lifter")
        let request = try #require(log.requests.first)
        #expect(request.url?.path() == "/users/me")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test func encodesJSONBodyForPatch() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .json(200, profileJSON)
        }
        _ = try await server.client().send(Endpoints.updateMe(UserProfileUpdate(weightUnit: .kg)))
        let request = try #require(log.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"weightUnit":"KG"}"#)
    }

    @Test func buildsQueryItems() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .json(200, #"{"items":[]}"#)
        }
        _ = try await server.client().send(Endpoints.listWorkouts(limit: 500, nextToken: "abc+/="))
        let url = try #require(log.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "limit", value: "50")))
        #expect(items.contains(URLQueryItem(name: "nextToken", value: "abc+/=")))
        #expect(!items.contains { $0.name == "status" })
    }

    @Test func omitsEmptyExerciseFilters() {
        let endpoint = Endpoints.listExercises(muscleGroup: nil, search: "   ")
        #expect(endpoint.queryItems.isEmpty)
        let filtered = Endpoints.listExercises(muscleGroup: "chest", search: " press ")
        #expect(filtered.queryItems == [.init(name: "muscleGroup", value: "chest"), .init(name: "search", value: "press")])
    }

    @Test func escapesPathIdentifiers() {
        #expect(Endpoints.getWorkout(id: "a/b c").path == "/workout-instances/a%2Fb%20c")
    }

    @Test func deleteReturnsEmptyResponse() async throws {
        let server = StubServer()
        server.respond { _ in .json(204, "") }
        let result = try await server.client().send(Endpoints.deleteMe)
        #expect(result == EmptyResponse())
    }

    @Test func mapsNotFoundWithServerMessage() async {
        let server = StubServer()
        server.respond { _ in .json(404, #"{"error":"Global metrics not found"}"#) }
        await #expect(throws: APIError.notFound("Global metrics not found")) {
            try await server.client().send(Endpoints.globalMetrics)
        }
    }

    @Test func mapsClientErrorsWithoutRetrying() async {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .json(400, #"{"error":"Cannot modify completed or cancelled workout"}"#)
        }
        await #expect(throws: APIError.rejected(status: 400, message: "Cannot modify completed or cancelled workout")) {
            try await server.client().send(Endpoints.updateWorkout(id: "w", .cancel))
        }
        #expect(log.requests.count == 1)
    }

    @Test func retriesServerErrorsWithBackoffThenSucceeds() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return log.requests.count < 3 ? .json(503, "") : .json(200, profileJSON)
        }
        let sleeps = SleepRecorder()
        _ = try await server.client(sleeps: sleeps).send(Endpoints.getMe)
        #expect(log.requests.count == 3)
        #expect(await sleeps.delays == [.seconds(1), .seconds(2)])
    }

    @Test func givesUpAfterRetryBudget() async {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .json(500, "")
        }
        await #expect(throws: APIError.server(status: 500)) {
            try await server.client().send(Endpoints.getMe)
        }
        #expect(log.requests.count == 4) // 1 attempt + 3 retries
    }

    @Test func neverRetriesPostToAvoidDuplicateWorkouts() async {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .json(502, "")
        }
        let create = Endpoints.createWorkout(CreateWorkoutRequest(exercises: [], source: .manual))
        await #expect(throws: APIError.server(status: 502)) {
            try await server.client().send(create)
        }
        #expect(log.requests.count == 1)
    }

    @Test func retriesNetworkFailures() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return log.requests.count == 1 ? .failure(.networkConnectionLost) : .json(200, profileJSON)
        }
        _ = try await server.client().send(Endpoints.getMe)
        #expect(log.requests.count == 2)
    }

    @Test func reportsOfflineAfterRetries() async {
        let server = StubServer()
        server.respond { _ in .failure(.notConnectedToInternet) }
        await #expect(throws: APIError.network(.notConnectedToInternet)) {
            try await server.client(retry: .none).send(Endpoints.getMe)
        }
    }

    @Test func refreshesTokenOnceOn401() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1"
                ? .json(401, #"{"message":"Unauthorized"}"#)
                : .json(200, profileJSON)
        }
        _ = try await server.client().send(Endpoints.getMe)
        #expect(server.tokens.forcedRefreshes == 1)
        #expect(log.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
    }

    @Test func persistent401IsUnauthorized() async {
        let server = StubServer()
        server.respond { _ in .json(401, "") }
        await #expect(throws: APIError.unauthorized) {
            try await server.client().send(Endpoints.getMe)
        }
    }

    @Test func missingSessionIsUnauthorized() async {
        struct NoSession: Error {}
        let server = StubServer(tokens: FakeTokenProvider(failure: NoSession()))
        await #expect(throws: APIError.unauthorized) {
            try await server.client().send(Endpoints.getMe)
        }
    }

    @Test func malformedBodyIsDecodingError() async {
        let server = StubServer()
        server.respond { _ in .json(200, #"{"unexpected":true}"#) }
        await #expect {
            try await server.client().send(Endpoints.getMe)
        } throws: { error in
            if case APIError.decoding = error { return true }
            return false
        }
    }

    @Test func userMessagesAreFriendly() {
        #expect(APIError.network(.notConnectedToInternet).userMessage.contains("offline"))
        #expect(APIError.rejected(status: 400, message: "Bad gym").userMessage == "Bad gym")
        #expect(APIError.server(status: 500).isTransient)
        #expect(!APIError.unauthorized.isTransient)
    }
}
