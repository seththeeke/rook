import Foundation
import Testing
@testable import Rook

@Suite("App configuration")
struct AppConfigurationTests {
    private let valid: [String: Any] = [
        "RookAPIBaseURL": "https://api.example.com",
        "RookAIStreamURL": "https://stream.example.com/",
        "RookCognitoUserPoolID": "us-east-1_abc",
        "RookCognitoClientID": "client123",
        "RookCognitoRegion": "us-east-1",
    ]

    @Test func parsesValidConfiguration() throws {
        let config = try AppConfiguration(infoDictionary: valid)
        #expect(config.apiBaseURL.absoluteString == "https://api.example.com")
        #expect(config.cognitoRegion == "us-east-1")
    }

    @Test(arguments: AppConfiguration.Key.allCases)
    func missingKeyFails(key: AppConfiguration.Key) {
        var info = valid
        info.removeValue(forKey: key.rawValue)
        #expect(throws: AppConfiguration.LoadError.missing(key)) {
            try AppConfiguration(infoDictionary: info)
        }
    }

    @Test func unexpandedBuildVariableCountsAsMissing() {
        var info = valid
        info["RookCognitoClientID"] = "$(ROOK_COGNITO_CLIENT_ID)"
        #expect(throws: AppConfiguration.LoadError.missing(.cognitoClientID)) {
            try AppConfiguration(infoDictionary: info)
        }
    }

    @Test func rejectsNonHTTPSURL() {
        var info = valid
        info["RookAPIBaseURL"] = "http://api.example.com"
        #expect(throws: AppConfiguration.LoadError.invalidURL(.apiBaseURL, "http://api.example.com")) {
            try AppConfiguration(infoDictionary: info)
        }
    }

    @Test func shippedBundleIsConfigured() throws {
        // Guards the real xcconfig → Info.plist wiring of the app under test.
        let config = try AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
        #expect(config.apiBaseURL.host() != nil)
    }
}
