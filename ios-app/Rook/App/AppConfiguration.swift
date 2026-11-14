import Foundation

/// Backend configuration read from Info.plist (populated from `Config/Base.xcconfig` at build time).
struct AppConfiguration: Equatable, Sendable {
    let apiBaseURL: URL
    let aiStreamURL: URL
    let cognitoUserPoolID: String
    let cognitoClientID: String
    let cognitoRegion: String

    enum Key: String, CaseIterable {
        case apiBaseURL = "RookAPIBaseURL"
        case aiStreamURL = "RookAIStreamURL"
        case cognitoUserPoolID = "RookCognitoUserPoolID"
        case cognitoClientID = "RookCognitoClientID"
        case cognitoRegion = "RookCognitoRegion"
    }

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(Key)
        case invalidURL(Key, String)

        var description: String {
            switch self {
            case .missing(let key):
                "Missing \(key.rawValue) in Info.plist — check Config/Base.xcconfig."
            case .invalidURL(let key, let value):
                "\(key.rawValue) is not a valid https URL: \(value)"
            }
        }
    }

    /// Parses configuration from an Info.plist-style dictionary. Unexpanded `$(VAR)` values count as missing.
    init(infoDictionary: [String: Any]) throws {
        func string(_ key: Key) throws -> String {
            guard let raw = infoDictionary[key.rawValue] as? String else { throw LoadError.missing(key) }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("$(") else { throw LoadError.missing(key) }
            return value
        }
        func httpsURL(_ key: Key) throws -> URL {
            let value = try string(key)
            guard let url = URL(string: value), url.scheme == "https", url.host() != nil else {
                throw LoadError.invalidURL(key, value)
            }
            return url
        }
        apiBaseURL = try httpsURL(.apiBaseURL)
        aiStreamURL = try httpsURL(.aiStreamURL)
        cognitoUserPoolID = try string(.cognitoUserPoolID)
        cognitoClientID = try string(.cognitoClientID)
        cognitoRegion = try string(.cognitoRegion)
    }

    /// Loads from the main bundle. A misconfigured build is a programmer error, so this traps
    /// with a clear message instead of showing users a broken app.
    static func fromMainBundle() -> AppConfiguration {
        do {
            return try AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
        } catch {
            fatalError("Rook build misconfigured: \(error)")
        }
    }
}
