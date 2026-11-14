import Amplify
import AWSCognitoAuthPlugin
import Foundation
import RookAuth
import Testing
@testable import Rook

/// Covers the offline-testable parts of the Amplify integration: configuration shape and the mapping
/// from Amplify/Cognito errors to `AuthFailure`. Live sign-in is exercised in Phase 1 device testing.
@Suite("Amplify auth service")
struct AmplifyAuthServiceTests {
    private let configuration = try! AppConfiguration(infoDictionary: [
        "RookAPIBaseURL": "https://api.example.com",
        "RookAIStreamURL": "https://stream.example.com",
        "RookCognitoUserPoolID": "us-east-1_pool",
        "RookCognitoClientID": "client",
        "RookCognitoRegion": "us-east-1",
    ])

    @Test func buildsSRPCognitoConfiguration() throws {
        let config = AmplifyAuthService.authCategoryConfiguration(configuration)
        let plugin = try #require(config.plugins["awsCognitoAuthPlugin"])
        let pool = plugin["CognitoUserPool"]?["Default"]
        #expect(pool?["PoolId"] == .string("us-east-1_pool"))
        #expect(pool?["AppClientId"] == .string("client"))
        #expect(pool?["Region"] == .string("us-east-1"))
        #expect(plugin["Auth"]?["Default"]?["authenticationFlowType"] == .string("USER_SRP_AUTH"))
    }

    @Test(arguments: [
        (AWSCognitoAuthError.userNotFound, AuthFailure.invalidCredentials),
        (.userNotConfirmed, .userNotConfirmed),
        (.usernameExists, .accountExists),
        (.aliasExists, .accountExists),
        (.invalidPassword, .passwordRejected("")),
        (.codeMismatch, .invalidCode),
        (.codeExpired, .expiredCode),
        (.limitExceeded, .tooManyAttempts),
        (.requestLimitExceeded, .tooManyAttempts),
        (.failedAttemptsLimitExceeded, .tooManyAttempts),
        (.network, .network),
        (.lambda, .unknown("desc")),
    ])
    func mapsCognitoServiceErrors(cognito: AWSCognitoAuthError, expected: AuthFailure) {
        let error = AuthError.service("desc", "recover", cognito)
        #expect(AmplifyAuthService.map(error) == expected)
    }

    @Test func wrongPasswordIsInvalidCredentials() {
        #expect(AmplifyAuthService.map(.notAuthorized("Incorrect username or password.", "")) == .invalidCredentials)
        #expect(AmplifyAuthService.map(.sessionExpired("expired", "")) == .invalidCredentials)
    }

    @Test func transportErrorsAreNetwork() {
        #expect(AmplifyAuthService.map(.unknown("x", URLError(.notConnectedToInternet))) == .network)
    }

    @Test func otherErrorsAreUnknown() {
        #expect(AmplifyAuthService.map(.configuration("bad config", "")) == .unknown("bad config"))
        #expect(AmplifyAuthService.map(.service("plain", "", nil)) == .unknown("plain"))
    }

    @Test func signInSteps() throws {
        #expect(try AmplifyAuthService.outcome(for: .done) == .signedIn)
        #expect(try AmplifyAuthService.outcome(for: .confirmSignUp(nil)) == .needsConfirmation)
        #expect(throws: AuthFailure.self) {
            try AmplifyAuthService.outcome(for: .confirmSignInWithTOTPCode)
        }
    }
}
