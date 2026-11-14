import Foundation
import Testing
import RookModels
@testable import RookNetworking

@Suite("AI workout stream")
struct AIWorkoutStreamTests {
    private let generate = AIGenerateRequest(
        aiPrompt: "Push day", weightUnit: .kg, equipmentTypes: ["dumbbells"], builderSessionId: "session-1"
    )

    private func client(_ server: StubServer) -> AIWorkoutStreamClient {
        AIWorkoutStreamClient(url: server.baseURL, session: server.session, tokenProvider: server.tokens)
    }

    private func collect(_ stream: AsyncThrowingStream<AIStreamEvent, Error>) async throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    /// A recorded-shape stream as written by `writeSSE` in lambdas/ai, delivered in awkward chunks.
    private let recorded = [
        "event: progress\ndata: {\"step\":\"analyzing_goals\",\"message\":\"Analyzing your goals...\"}\n\n",
        "event: progress\ndata: {\"step\":\"scanning_cat",
        "alog\",\"message\":\"Scanning catalog...\"}\n\nevent: complete\ndata: {\"exercises\":[",
        "{\"exerciseId\":\"bench\",\"exerciseName\":\"Bench Press\",\"modality\":\"sets_reps\",\"sets\":4,\"reps\":8}]}\n\n",
    ]

    @Test func streamsProgressThenComplete() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .stream(recorded)
        }
        let events = try await collect(client(server).generate(generate))
        #expect(events.count == 3)
        #expect(events[0] == .progress(step: "analyzing_goals", message: "Analyzing your goals..."))
        #expect(events[1] == .progress(step: "scanning_catalog", message: "Scanning catalog..."))
        guard case .complete(let exercises) = events[2] else { Issue.record("expected complete"); return }
        #expect(exercises.map(\.exerciseId) == ["bench"])

        let request = try #require(log.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["aiPrompt"] as? String == "Push day")
        #expect(body["weightUnit"] as? String == "KG")
        #expect(body["builderSessionId"] as? String == "session-1")
        #expect(body["equipmentTypes"] as? [String] == ["dumbbells"])
    }

    @Test func serverErrorEventThrowsItsMessage() async {
        let server = StubServer()
        server.respond { _ in .stream(["event: error\ndata: {\"message\":\"No exercises match your gym\"}\n\n"]) }
        await #expect(throws: AIStreamError.server("No exercises match your gym")) {
            try await collect(client(server).generate(generate))
        }
    }

    @Test func streamEndingWithoutTerminalEventIsIncomplete() async {
        let server = StubServer()
        server.respond { _ in .stream(["event: progress\ndata: {\"step\":\"a\",\"message\":\"m\"}\n\n"]) }
        await #expect(throws: AIStreamError.incomplete) {
            try await collect(client(server).generate(generate))
        }
    }

    @Test func completeWithoutTrailingBlankLineStillCompletes() async throws {
        let server = StubServer()
        server.respond { _ in .stream(["event: complete\ndata: {\"exercises\":[]}"]) }
        let events = try await collect(client(server).generate(generate))
        #expect(events == [.complete([])])
    }

    @Test func malformedCompletePayloadThrows() async {
        let server = StubServer()
        server.respond { _ in .stream(["event: complete\ndata: not-json\n\n"]) }
        await #expect(throws: AIStreamError.malformed) {
            try await collect(client(server).generate(generate))
        }
    }

    @Test func httpFailureStatus() async {
        let server = StubServer()
        server.respond { _ in .json(502, "Bad gateway") }
        await #expect(throws: AIStreamError.http(status: 502)) {
            try await collect(client(server).generate(generate))
        }
    }

    @Test func unauthorizedStatus() async {
        let server = StubServer()
        server.respond { _ in .json(403, "") }
        await #expect(throws: AIStreamError.unauthorized) {
            try await collect(client(server).generate(generate))
        }
    }

    @Test func networkFailure() async {
        let server = StubServer()
        server.respond { _ in .failure(.timedOut) }
        await #expect(throws: AIStreamError.network(.timedOut)) {
            try await collect(client(server).generate(generate))
        }
    }

    @Test func regenerateSendsContextAndCurrentExercises() async throws {
        let server = StubServer()
        let log = RequestLog()
        server.respond { request in
            log.append(request)
            return .stream(["event: complete\ndata: {\"exercises\":[]}\n\n"])
        }
        let current = [WorkoutExercise(exerciseId: "a", exerciseName: "A", modality: .setsReps)]
        let request = AIRegenerateRequest(
            regenerateContext: .init(
                exerciseIndices: [0], currentExerciseIds: ["a"], targetMuscleGroups: ["chest"],
                userPrompt: "Push day", equipmentTypes: nil
            ),
            currentExercises: current,
            builderSessionId: "session-1"
        )
        _ = try await collect(client(server).regenerate(request))
        let body = try #require(
            JSONSerialization.jsonObject(with: log.requests.first?.httpBody ?? Data()) as? [String: Any]
        )
        let context = try #require(body["regenerateContext"] as? [String: Any])
        #expect(context["exerciseIndices"] as? [Int] == [0])
        #expect(context["targetMuscleGroups"] as? [String] == ["chest"])
        #expect((body["currentExercises"] as? [[String: Any]])?.count == 1)
        #expect(body["aiPrompt"] == nil)
    }

    @Test func mapIgnoresUnknownEventsAndBadProgress() throws {
        #expect(try AIWorkoutStreamClient.map(SSEEvent(event: "heartbeat", data: "{}")) == nil)
        #expect(try AIWorkoutStreamClient.map(SSEEvent(event: "progress", data: "oops")) == nil)
        #expect(
            try AIWorkoutStreamClient.map(SSEEvent(event: "progress", data: #"{"step":"x"}"#))
                == .progress(step: "x", message: "")
        )
    }

    @Test func errorEventWithPlainTextUsesRawData() {
        #expect(throws: AIStreamError.server("boom")) {
            try AIWorkoutStreamClient.map(SSEEvent(event: "error", data: "boom"))
        }
    }

    @Test func userMessages() {
        #expect(AIStreamError.server("").userMessage.contains("generation failed"))
        #expect(AIStreamError.server("Try a shorter prompt").userMessage == "Try a shorter prompt")
        #expect(AIStreamError.network(.notConnectedToInternet).userMessage.contains("offline"))
    }
}
