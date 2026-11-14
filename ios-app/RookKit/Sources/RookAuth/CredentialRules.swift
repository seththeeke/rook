import Foundation

/// Client-side checks that mirror the Cognito user pool configuration in `packages/cdk/lib/auth.ts`
/// (min length 8, upper + lower + digit, symbols optional), so users see problems before a round trip.
public enum CredentialRules {
    public enum PasswordRequirement: CaseIterable, Equatable, Sendable {
        case minimumLength, lowercase, uppercase, digit

        public var label: String {
            switch self {
            case .minimumLength: "At least 8 characters"
            case .lowercase: "A lowercase letter"
            case .uppercase: "An uppercase letter"
            case .digit: "A number"
            }
        }

        public func isMet(by password: String) -> Bool {
            switch self {
            case .minimumLength: password.count >= 8
            case .lowercase: password.contains { $0.isLowercase }
            case .uppercase: password.contains { $0.isUppercase }
            case .digit: password.contains { $0.isNumber }
            }
        }
    }

    public static func unmetRequirements(for password: String) -> [PasswordRequirement] {
        PasswordRequirement.allCases.filter { !$0.isMet(by: password) }
    }

    public static func isValidPassword(_ password: String) -> Bool {
        unmetRequirements(for: password).isEmpty
    }

    /// Pragmatic email check (same as the web form): something@something.tld, no spaces.
    public static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }

    /// Emails are case-insensitive aliases in the pool; normalize before sending.
    public static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Cognito confirmation and reset codes are 6 digits.
    public static func isValidCode(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespaces).wholeMatch(of: /\d{6}/) != nil
    }
}
