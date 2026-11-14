import Testing
@testable import RookAuth

@Suite("Credential rules")
struct CredentialRulesTests {
    @Test func validPasswordMeetsEveryRequirement() {
        #expect(CredentialRules.isValidPassword("Lifting123"))
        #expect(CredentialRules.unmetRequirements(for: "Lifting123").isEmpty)
    }

    @Test(arguments: [
        ("short1A", [CredentialRules.PasswordRequirement.minimumLength]),
        ("alllowercase1", [.uppercase]),
        ("ALLUPPERCASE1", [.lowercase]),
        ("NoDigitsHere", [.digit]),
        ("", [.minimumLength, .lowercase, .uppercase, .digit]),
    ])
    func reportsUnmetRequirements(password: String, expected: [CredentialRules.PasswordRequirement]) {
        #expect(CredentialRules.unmetRequirements(for: password) == expected)
    }

    @Test func symbolsAreOptionalButAllowed() {
        #expect(CredentialRules.isValidPassword("Lift!ng123"))
    }

    @Test(arguments: ["a@b.co", " lifter@example.com ", "first.last+tag@sub.domain.io"])
    func acceptsEmails(email: String) {
        #expect(CredentialRules.isValidEmail(email))
    }

    @Test(arguments: ["", "lifter", "lifter@", "@example.com", "a b@example.com", "lifter@example"])
    func rejectsEmails(email: String) {
        #expect(!CredentialRules.isValidEmail(email))
    }

    @Test func normalizesEmail() {
        #expect(CredentialRules.normalizedEmail("  Lifter@Example.COM ") == "lifter@example.com")
    }

    @Test func codes() {
        #expect(CredentialRules.isValidCode("123456"))
        #expect(CredentialRules.isValidCode(" 123456 "))
        #expect(!CredentialRules.isValidCode("12345"))
        #expect(!CredentialRules.isValidCode("12a456"))
    }

    @Test func requirementLabelsAreHumanReadable() {
        #expect(CredentialRules.PasswordRequirement.minimumLength.label == "At least 8 characters")
    }

    @Test func failureMessages() {
        #expect(AuthFailure.invalidCredentials.userMessage == "Incorrect email or password.")
        #expect(AuthFailure.passwordRejected("").userMessage.contains("requirements"))
        #expect(AuthFailure.passwordRejected("Too common").userMessage == "Too common")
        #expect(AuthFailure.unsupportedChallenge("MFA").userMessage.contains("web"))
    }
}
