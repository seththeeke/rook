import Foundation
@testable import RookNetworking

/// Intercepts URLSession requests in tests. Each test registers a handler under its own unique host,
/// so tests can run in parallel without sharing state.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var chunks: [Data]
        var error: URLError?

        static func json(_ status: Int, _ body: String) -> Reply {
            Reply(status: status, chunks: [Data(body.utf8)], error: nil)
        }
        static func failure(_ code: URLError.Code) -> Reply {
            Reply(status: 0, chunks: [], error: URLError(code))
        }
        static func stream(_ chunks: [String], status: Int = 200) -> Reply {
            Reply(status: status, chunks: chunks.map { Data($0.utf8) }, error: nil)
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.withLock { handlers[host] = handler }
    }

    static func unregister(host: String) {
        _ = lock.withLock { handlers.removeValue(forKey: host) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        guard let handler = Self.lock.withLock({ Self.handlers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // URLSession moves httpBody into a stream; restore it so handlers can inspect the body.
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            captured.httpBody = Data(reading: stream)
        }
        let reply = handler(captured)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            append(buffer, count: read)
        }
    }
}

/// A per-test harness: unique host, stub session, and a recording token provider.
final class StubServer: Sendable {
    let host = "test-\(UUID().uuidString.lowercased()).example.com"
    let session: URLSession
    let tokens: FakeTokenProvider

    init(tokens: FakeTokenProvider = FakeTokenProvider()) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        self.tokens = tokens
    }

    var baseURL: URL { URL(string: "https://\(host)")! }

    func respond(_ handler: @escaping StubURLProtocol.Handler) {
        StubURLProtocol.register(host: host, handler: handler)
    }

    deinit { StubURLProtocol.unregister(host: host) }

    func client(retry: RetryPolicy = RetryPolicy(), sleeps: SleepRecorder = SleepRecorder()) -> APIClient {
        APIClient(
            baseURL: baseURL, session: session, tokenProvider: tokens, retryPolicy: retry,
            sleep: { await sleeps.record($0) }
        )
    }
}

/// Returns "token-N" and records whether a refresh was forced.
final class FakeTokenProvider: TokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var _forcedRefreshes = 0
    private let failure: Error?

    init(failure: Error? = nil) { self.failure = failure }

    var forcedRefreshes: Int { lock.withLock { _forcedRefreshes } }

    func idToken(forceRefresh: Bool) async throws -> String {
        if let failure { throw failure }
        return lock.withLock {
            count += 1
            if forceRefresh { _forcedRefreshes += 1 }
            return "token-\(count)"
        }
    }
}

actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ d: Duration) { delays.append(d) }
}

/// Thread-safe request log for assertions.
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    func append(_ r: URLRequest) { lock.withLock { _requests.append(r) } }
    var requests: [URLRequest] { lock.withLock { _requests } }
}
