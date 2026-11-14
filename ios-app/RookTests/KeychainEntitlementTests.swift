import Foundation
import Security
import Testing

/// Regression guard for the sign-in outage of 2026-11-14: without the keychain-access-groups
/// entitlement every Keychain call fails with errSecMissingEntitlement (-34018), and Amplify can't
/// store the Cognito session, so sign-in fails instantly. These tests run inside the app host, so they
/// exercise the app's real signing and entitlements.
@Suite("Keychain access", .serialized)
struct KeychainEntitlementTests {
    private let service = "com.rookfitness.app.tests.keychain-probe"

    @Test func appCanWriteReadAndDeleteKeychainItems() {
        let account = UUID().uuidString
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var add = base
        add[kSecValueData as String] = Data("probe".utf8)
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        #expect(addStatus != errSecMissingEntitlement, "Missing Keychain entitlement: sign-in will fail. Check Rook.entitlements and signing.")
        #expect(addStatus == errSecSuccess)

        var query = base
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        #expect((result as? Data) == Data("probe".utf8))

        #expect(SecItemDelete(base as CFDictionary) == errSecSuccess)
    }
}
