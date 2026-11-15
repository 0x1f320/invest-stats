import Foundation
import Testing
@testable import TossBar

@Suite("Settings from the previous bundle id")
struct LegacyDefaultsTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "LegacyDefaultsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private let legacy: [String: Any] = [
        "menuItems.v1": Data("[]".utf8),
        "secretLocation": "iCloudKeychain",
        "NSStatusItem Preferred Position TossBar.ABC": 120.0,
    ]

    @Test func copiesEverythingOnFirstLaunch() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        LegacyDefaults.migrate(from: legacy, into: defaults)

        #expect(defaults.data(forKey: "menuItems.v1") == Data("[]".utf8))
        #expect(defaults.string(forKey: "secretLocation") == "iCloudKeychain")
        #expect(defaults.double(forKey: "NSStatusItem Preferred Position TossBar.ABC") == 120)
        #expect(defaults.bool(forKey: LegacyDefaults.migratedKey))
    }

    @Test func runsOnlyOnce() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        LegacyDefaults.migrate(from: [:], into: defaults)
        LegacyDefaults.migrate(from: legacy, into: defaults)

        // Items the user deleted after the first launch must not come back.
        #expect(defaults.object(forKey: "menuItems.v1") == nil)
        #expect(defaults.object(forKey: "secretLocation") == nil)
    }

    @Test func leavesExistingItemsAlone() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("[1]".utf8), forKey: "menuItems.v1")

        LegacyDefaults.migrate(from: legacy, into: defaults)

        #expect(defaults.data(forKey: "menuItems.v1") == Data("[1]".utf8))
        #expect(defaults.object(forKey: "secretLocation") == nil)
        #expect(defaults.bool(forKey: LegacyDefaults.migratedKey))
    }
}
