import Foundation

/// Errors surfaced by the API layer. `userMessage` is safe to show in the UI.
public enum APIError: Error, Equatable, Sendable {
    /// No valid session (missing token, or the server rejected it after a refresh). The app signs out.
    case unauthorized
    /// 404, with the server's message (e.g. "Global metrics not found").
    case notFound(String)
    /// 400/403/409/422…, with the server's message.
    case rejected(status: Int, message: String)
    /// 5xx after retries were exhausted.
    case server(status: Int)
    /// Transport failure (offline, timeout, TLS…) after retries were exhausted.
    case network(URLError.Code)
    /// The response body didn't match the expected shape.
    case decoding(String)
    /// Non-HTTP response or other unexpected condition.
    case invalidResponse

    public var userMessage: String {
        switch self {
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case .notFound:
            "We couldn't find that."
        case .rejected(_, let message):
            message.isEmpty ? "That request couldn't be completed." : message
        case .server:
            "Something went wrong on our end. Please try again."
        case .network(let code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                "You're offline. Check your connection and try again."
            case .timedOut:
                "The request timed out. Please try again."
            default:
                "We couldn't reach the server. Please try again."
            }
        case .decoding, .invalidResponse:
            "Something went wrong. Please try again."
        }
    }

    /// True when retrying the same request later could succeed.
    public var isTransient: Bool {
        switch self {
        case .server, .network: true
        default: false
        }
    }
}
