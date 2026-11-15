import Foundation
import Testing
@testable import TossBar

@Suite("Secret storage")
struct SecretStoreTests {
    @Test func locationDefaultsToLocal() {
        // Installs that never turned on iCloud keep their connections in local files.
        #expect(SecretLocation.parse(nil) == .local)
        #expect(SecretLocation.parse("") == .local)
        #expect(SecretLocation.parse("somethingElse") == .local)
        #expect(SecretLocation.parse("local") == .local)
        #expect(SecretLocation.parse("iCloudKeychain") == .iCloudKeychain)
    }

    @Test func tokenUsability() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let token = CachedToken(clientId: "a", accessToken: "t", expiresAt: now.addingTimeInterval(3600))
        #expect(token.isUsable(for: "a", now: now))
        // A token issued for other keys is never reused.
        #expect(!token.isUsable(for: "b", now: now))
        // Within a minute of expiry it counts as expired.
        #expect(!token.isUsable(for: "a", now: now.addingTimeInterval(3600 - 30)))
        #expect(token.isUsable(for: "a", now: now.addingTimeInterval(3600 - 90)))
    }

    @Test func cachedTokenDecodesSavedFormat() throws {
        // The token file written by earlier versions keeps loading.
        let json = #"{"clientId":"a","accessToken":"t","expiresAt":800000000}"#
        let token = try JSONDecoder().decode(CachedToken.self, from: Data(json.utf8))
        #expect(token == CachedToken(clientId: "a", accessToken: "t", expiresAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }
}
