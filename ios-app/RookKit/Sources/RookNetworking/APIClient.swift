import Foundation
import RookModels

/// Supplies the Cognito **ID token** (the API Gateway authorizer and the AI Function URL both validate
/// ID tokens). `forceRefresh` is used once after a 401.
public protocol TokenProviding: Sendable {
    func idToken(forceRefresh: Bool) async throws -> String
}

/// Retry schedule for transient failures. Matches the web client (1s, 2s, 4s).
public struct RetryPolicy: Sendable {
    public var delays: [Duration]

    public init(delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]) {
        self.delays = delays
    }

    public static let none = RetryPolicy(delays: [])
}

/// The one way the app talks to the REST API.
public final class APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProviding
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: TokenProviding,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    /// Performs the request: attaches the ID token, retries transient failures on idempotent methods,
    /// refreshes the token once on 401, and maps error bodies to `APIError`.
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let data = try await perform(endpoint, attempt: 0, refreshedToken: false)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try RookJSON.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func perform<Response>(
        _ endpoint: Endpoint<Response>,
        attempt: Int,
        refreshedToken: Bool
    ) async throws -> Data {
        let token: String
        do {
            token = try await tokenProvider.idToken(forceRefresh: refreshedToken)
        } catch {
            throw APIError.unauthorized
        }

        let request = makeRequest(endpoint, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if let next = try await retryDelay(for: endpoint.method, attempt: attempt) {
                try await sleep(next)
                return try await perform(endpoint, attempt: attempt + 1, refreshedToken: refreshedToken)
            }
            throw APIError.network(error.code)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            if refreshedToken { throw APIError.unauthorized }
            return try await perform(endpoint, attempt: attempt, refreshedToken: true)
        case 404:
            throw APIError.notFound(Self.errorMessage(from: data))
        case 500..<600:
            if let next = try await retryDelay(for: endpoint.method, attempt: attempt) {
                try await sleep(next)
                return try await perform(endpoint, attempt: attempt + 1, refreshedToken: refreshedToken)
            }
            throw APIError.server(status: http.statusCode)
        default:
            throw APIError.rejected(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private func retryDelay(for method: HTTPMethod, attempt: Int) async throws -> Duration? {
        try Task.checkCancellation()
        guard method.isIdempotent, attempt < retryPolicy.delays.count else { return nil }
        return retryPolicy.delays[attempt]
    }

    func makeRequest<Response>(_ endpoint: Endpoint<Response>, token: String) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.percentEncodedPath = basePath + endpoint.path
        components.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func errorMessage(from data: Data) -> String {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) { return body.error }
        return ""
    }
}
