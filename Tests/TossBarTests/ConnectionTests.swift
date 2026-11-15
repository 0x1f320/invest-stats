import Foundation
import Testing
@testable import TossBar

@Suite("Connections")
struct ConnectionTests {
    private let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test func decodesMinimalRecord() throws {
        // Fields added later fall back to defaults instead of failing the whole record.
        let json = #"{"id":"00000000-0000-0000-0000-00000000000A","provider":"tossinvest"}"#
        let connection = try JSONDecoder().decode(Connection.self, from: Data(json.utf8))
        #expect(connection.id == idA)
        #expect(connection.provider == .tossinvest)
        #expect(connection.name == "")
        #expect(connection.values.isEmpty)
        #expect(connection.displayName == "토스증권")
        #expect(!connection.isComplete)
    }

    @Test func unknownProviderIsRejected() {
        // A record synced from a newer version with a provider this build lacks is skipped.
        let json = #"{"id":"00000000-0000-0000-0000-00000000000A","provider":"someNewBroker"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Connection.self, from: Data(json.utf8))
        }
    }

    @Test func roundTrips() throws {
        let connection = Connection(
            id: idA, provider: .tossinvest, name: "부모님 계좌",
            values: ["clientId": "id", "clientSecret": "secret"],
            createdAt: Date(timeIntervalSinceReferenceDate: 1000)
        )
        let decoded = try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(connection))
        #expect(decoded == connection)
        #expect(decoded.displayName == "부모님 계좌")
        #expect(decoded.identity == "id")
        #expect(decoded.tossCredentials == Credentials(clientId: "id", clientSecret: "secret"))
    }

    @Test func incompleteConnectionHasNoCredentials() {
        let connection = Connection(id: idA, provider: .tossinvest, values: ["clientId": "id", "clientSecret": "  "])
        #expect(!connection.isComplete)
        #expect(connection.tossCredentials == nil)
    }

    @Test func legacyIDIsStablePerKey() {
        let first = Connection.legacyID(provider: .tossinvest, identity: "client-1")
        #expect(first == Connection.legacyID(provider: .tossinvest, identity: "client-1"))
        #expect(first != Connection.legacyID(provider: .tossinvest, identity: "client-2"))
        // A well-formed name-based UUID.
        let string = first.uuidString
        #expect(string[string.index(string.startIndex, offsetBy: 14)] == "5")
    }

    @Test func listSortsByAge() {
        let old = Connection(id: idB, provider: .tossinvest, createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let new = Connection(id: idA, provider: .tossinvest, createdAt: Date(timeIntervalSinceReferenceDate: 200))
        let list = StoredConnection.list([new, old], in: .iCloudKeychain)
        #expect(list.map(\.id) == [idB, idA])
        #expect(list.allSatisfy { $0.location == .iCloudKeychain })
    }

    @Test func syncCopiesOnlyWhatTheTargetLacks() {
        // Turning sync on keeps the copy other Macs already use for a shared connection.
        let local = [
            Connection(id: idA, provider: .tossinvest, name: "local A"),
            Connection(id: idB, provider: .tossinvest, name: "local B"),
        ]
        let synced = [Connection(id: idA, provider: .tossinvest, name: "synced A")]
        let copies = StoredConnection.missing(from: synced, in: local)
        #expect(copies.map(\.name) == ["local B"])
        #expect(StoredConnection.missing(from: local, in: synced).isEmpty)
    }
}

@Suite("Legacy key migration")
struct ConnectionMigrationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 500)
    private let keys = Credentials(clientId: "client-1", clientSecret: "secret-1")
    private let otherKeys = Credentials(clientId: "client-2", clientSecret: "secret-2")

    private func token(_ clientId: String) -> CachedToken {
        CachedToken(clientId: clientId, accessToken: "t-\(clientId)", expiresAt: now.addingTimeInterval(3600))
    }

    @Test func nothingToMigrate() {
        let plan = ConnectionMigration.plan(current: .local, legacy: [], existingIDs: [], now: now)
        #expect(plan.steps.isEmpty)
        #expect(plan.defaultID == nil)
    }

    @Test func localKeysBecomeLocalConnectionWithToken() {
        let plan = ConnectionMigration.plan(
            current: .local,
            legacy: [.init(credentials: keys, token: token("client-1"), location: .local)],
            existingIDs: [], now: now
        )
        let id = Connection.legacyID(provider: .tossinvest, identity: "client-1")
        #expect(plan.defaultID == id)
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].location == .local)
        #expect(plan.steps[0].connection.tossCredentials == keys)
        #expect(plan.steps[0].token == token("client-1"))
    }

    @Test func tokenForOtherKeysIsDropped() {
        let plan = ConnectionMigration.plan(
            current: .local,
            legacy: [.init(credentials: keys, token: token("client-2"), location: .local)],
            existingIDs: [], now: now
        )
        #expect(plan.steps.first?.token == nil)
    }

    @Test func syncingMacKeepsEverythingInICloud() {
        // A Mac that used the iCloud Keychain, with older local keys left behind. It syncs
        // all of its connections, so both end up in iCloud, and its own keys are the default.
        let plan = ConnectionMigration.plan(
            current: .iCloudKeychain,
            legacy: [
                .init(credentials: otherKeys, token: nil, location: .local),
                .init(credentials: keys, token: nil, location: .iCloudKeychain),
            ],
            existingIDs: [], now: now
        )
        #expect(plan.defaultID == Connection.legacyID(provider: .tossinvest, identity: "client-1"))
        #expect(plan.steps.map(\.location) == [.iCloudKeychain, .iCloudKeychain])
    }

    @Test func localMacLeavesSharedKeysInICloud() {
        // A Mac that didn't sync: its own keys stay local, and keys another Mac shared stay
        // in iCloud, where turning sync on picks them up.
        let plan = ConnectionMigration.plan(
            current: .local,
            legacy: [
                .init(credentials: otherKeys, token: nil, location: .iCloudKeychain),
                .init(credentials: keys, token: nil, location: .local),
            ],
            existingIDs: [], now: now
        )
        #expect(plan.defaultID == Connection.legacyID(provider: .tossinvest, identity: "client-1"))
        #expect(plan.steps.map(\.location) == [.local, .iCloudKeychain])
    }

    @Test func sameKeysInBothPlacesBecomeOneConnection() {
        let plan = ConnectionMigration.plan(
            current: .local,
            legacy: [
                .init(credentials: keys, token: nil, location: .iCloudKeychain),
                .init(credentials: keys, token: nil, location: .local),
            ],
            existingIDs: [], now: now
        )
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].location == .local)
    }

    @Test func keysMigratedByAnotherMacAreNotWrittenAgain() {
        let id = Connection.legacyID(provider: .tossinvest, identity: "client-1")
        let plan = ConnectionMigration.plan(
            current: .iCloudKeychain,
            legacy: [.init(credentials: keys, token: nil, location: .iCloudKeychain)],
            existingIDs: [id], now: now
        )
        #expect(plan.steps.isEmpty)
        // Existing items still point at the connection the other Mac created.
        #expect(plan.defaultID == id)
    }
}

@Suite("Item connections")
struct ItemConnectionTests {
    @Test func itemSavedBeforeConnectionsHasNone() throws {
        let json = #"[{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"asset": {"_0": {"label": "💰"}}}}]"#
        let items = try JSONDecoder().decode([MenuItemConfig].self, from: Data(json.utf8))
        #expect(items.first?.connectionID == nil)
    }

    @Test func connectionRoundTrips() throws {
        let item = MenuItemConfig(kind: .asset(AssetItemConfig(label: "a")), connectionID: UUID())
        let decoded = try JSONDecoder().decode(MenuItemConfig.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    @Test func helpersCoverOnlyTheGivenItems() {
        let items: [MenuItemConfig] = [
            MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL", displayCurrency: .krw))),
            MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL"))),
            MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930"))),
            MenuItemConfig(kind: .asset(AssetItemConfig(label: "x"))),
        ]
        #expect(items.stockSymbols == ["AAPL", "005930"])
        #expect(items.needsUsdKrwForStocks)
        #expect(items.assetConfigs.map(\.label) == ["x"])
        #expect(!Array(items.suffix(2)).needsUsdKrwForStocks)
    }
}
