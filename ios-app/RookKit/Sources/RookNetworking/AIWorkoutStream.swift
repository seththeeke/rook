import Foundation
import RookModels

/// Body for a full AI generation (`StreamBody` in `lambdas/ai/src/index.ts`).
public struct AIGenerateRequest: Encodable, Equatable, Sendable {
    public var aiPrompt: String
    public var weightUnit: WeightUnit
    public var equipmentTypes: [String]?
    public var builderSessionId: String

    public init(aiPrompt: String, weightUnit: WeightUnit, equipmentTypes: [String]?, builderSessionId: String) {
        self.aiPrompt = aiPrompt
        self.weightUnit = weightUnit
        self.equipmentTypes = equipmentTypes
        self.builderSessionId = builderSessionId
    }
}

/// Body for regenerating selected exercises of an AI draft.
public struct AIRegenerateRequest: Encodable, Equatable, Sendable {
    public struct Context: Encodable, Equatable, Sendable {
        public var exerciseIndices: [Int]
        public var currentExerciseIds: [String]
        public var targetMuscleGroups: [String]
        public var userPrompt: String
        public var equipmentTypes: [String]?

        public init(
            exerciseIndices: [Int],
            currentExerciseIds: [String],
            targetMuscleGroups: [String],
            userPrompt: String,
            equipmentTypes: [String]?
        ) {
            self.exerciseIndices = exerciseIndices
            self.currentExerciseIds = currentExerciseIds
            self.targetMuscleGroups = targetMuscleGroups
            self.userPrompt = userPrompt
            self.equipmentTypes = equipmentTypes
        }
    }

    public var regenerateContext: Context
    public var currentExercises: [WorkoutExercise]
    public var builderSessionId: String

    public init(regenerateContext: Context, currentExercises: [WorkoutExercise], builderSessionId: String) {
        self.regenerateContext = regenerateContext
        self.currentExercises = currentExercises
        self.builderSessionId = builderSessionId
    }
}

/// Events emitted while the AI builds a workout.
public enum AIStreamEvent: Equatable, Sendable {
    /// `step` is one of analyzing_goals, reviewing_history, scanning_catalog, balancing_muscles,
    /// optimizing_structure; `message` is the server's human-readable label.
    case progress(step: String, message: String)
    case complete([WorkoutExercise])
}

public enum AIStreamError: Error, Equatable, Sendable {
    /// The server reported an error event (message is user-presentable).
    case server(String)
    /// The HTTP request itself failed.
    case http(status: Int)
    /// The stream ended without a `complete` or `error` event.
    case incomplete
    /// A terminal event's payload couldn't be decoded.
    case malformed
    case unauthorized
    case network(URLError.Code)

    public var userMessage: String {
        switch self {
        case .server(let message): message.isEmpty ? "Workout generation failed. Please try again." : message
        case .unauthorized: APIError.unauthorized.userMessage
        case .network(let code): APIError.network(code).userMessage
        case .http, .incomplete, .malformed: "Workout generation failed. Please try again."
        }
    }
}

/// Streams AI workout generation. A protocol so view models can be tested with a fake.
public protocol AIWorkoutStreaming: Sendable {
    func generate(_ request: AIGenerateRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func regenerate(_ request: AIRegenerateRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}

/// Calls the AI Lambda Function URL (`AiWorkoutStreamUrl`) and parses its SSE response.
public final class AIWorkoutStreamClient: AIWorkoutStreaming {
    /// Lambda timeout is 120 s; allow a little more before giving up on a silent connection.
    static let timeout: TimeInterval = 130

    private let url: URL
    private let session: URLSession
    private let tokenProvider: TokenProviding

    public init(url: URL, session: URLSession = .shared, tokenProvider: TokenProviding) {
        self.url = url
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func generate(_ request: AIGenerateRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        stream(body: request)
    }

    public func regenerate(_ request: AIRegenerateRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        stream(body: request)
    }

    private func stream<Body: Encodable & Sendable>(body: Body) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(body: body, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError {
                    continuation.finish(throwing: AIStreamError.network(error.code))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run<Body: Encodable>(
        body: Body,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        let token: String
        do {
            token = try await tokenProvider.idToken(forceRefresh: false)
        } catch {
            throw AIStreamError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try RookJSON.makeEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIStreamError.malformed }
        if http.statusCode == 401 || http.statusCode == 403 { throw AIStreamError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw AIStreamError.http(status: http.statusCode) }

        var parser = SSEParser()
        var pending = Data()
        for try await byte in bytes {
            pending.append(byte)
            // Hand complete lines to the parser so multi-byte UTF-8 characters are never split.
            guard byte == UInt8(ascii: "\n") else { continue }
            let events = parser.feed(String(decoding: pending, as: UTF8.self))
            pending.removeAll(keepingCapacity: true)
            if try handle(events, continuation) { return }
        }
        let trailing = parser.feed(String(decoding: pending, as: UTF8.self)) + parser.finish()
        if try handle(trailing, continuation) { return }
        throw AIStreamError.incomplete
    }

    /// Yields events; returns true once a terminal (`complete`) event finished the stream.
    private func handle(
        _ events: [SSEEvent],
        _ continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) throws -> Bool {
        for event in events {
            if let mapped = try Self.map(event) {
                continuation.yield(mapped)
                if case .complete = mapped {
                    continuation.finish()
                    return true
                }
            }
        }
        return false
    }

    /// Maps a raw SSE event to a domain event. Unknown events and bad progress payloads are ignored;
    /// `error` events and undecodable `complete` payloads throw.
    static func map(_ event: SSEEvent) throws -> AIStreamEvent? {
        let data = Data(event.data.utf8)
        switch event.event {
        case "progress":
            struct Progress: Decodable { let step: String; let message: String? }
            guard let p = try? JSONDecoder().decode(Progress.self, from: data) else { return nil }
            return .progress(step: p.step, message: p.message ?? "")
        case "complete":
            struct Complete: Decodable { let exercises: [WorkoutExercise]? }
            guard let c = try? RookJSON.makeDecoder().decode(Complete.self, from: data) else {
                throw AIStreamError.malformed
            }
            return .complete(c.exercises ?? [])
        case "error":
            struct Failure: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.message ?? event.data
            throw AIStreamError.server(message)
        default:
            return nil
        }
    }
}
