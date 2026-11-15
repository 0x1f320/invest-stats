import CryptoKit
import Foundation

/// A service the app can read prices and holdings from.
///
/// A raw value is saved in each connection, so keep existing values stable. A connection
/// whose provider this build doesn't know, for example one synced from a newer version on
/// another Mac, is skipped when loading.
enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case tossinvest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tossinvest: return "토스증권"
        }
    }

    var systemImage: String {
        switch self {
        case .tossinvest: return "building.columns"
        }
    }

    /// The values a connection to this provider needs, in the order the form shows them.
    var fields: [ProviderField] {
        switch self {
        case .tossinvest:
            return [
                ProviderField(key: "clientId", label: "Client ID", placeholder: "발급받은 client_id", isSecret: false),
                ProviderField(key: "clientSecret", label: "Client Secret", placeholder: "발급받은 client_secret", isSecret: true),
            ]
        }
    }

    /// The field that identifies the keys. Two connections with the same value would fight
    /// over one access token, so the same keys can't be added twice.
    var identityField: String {
        switch self {
        case .tossinvest: return "clientId"
        }
    }
}

struct ProviderField: Hashable, Identifiable, Sendable {
    let key: String
    let label: String
    let placeholder: String
    /// Masked in the form and never shown again once saved.
    let isSecret: Bool

    var id: String { key }
}

/// A saved connection to a provider: which provider, a name, and its keys.
///
/// Connections are stored with the other secrets, either in user-only files on this Mac or
/// in the iCloud Keychain, where they sync to the user's other Macs. Where a connection is
/// kept is not part of the record; it follows from where the record was found.
struct Connection: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var provider: Provider
    /// Shown in the settings and item editors. Empty uses the provider's name.
    var name: String = ""
    /// Field key to value, as listed in `Provider.fields`.
    var values: [String: String] = [:]
    var createdAt: Date = Date()

    var displayName: String { name.nilIfBlank ?? provider.title }

    /// The value of the provider's identity field, such as the Client ID.
    var identity: String? { values[provider.identityField]?.nilIfBlank }

    /// Whether every field has a value.
    var isComplete: Bool {
        provider.fields.allSatisfy { values[$0.key]?.nilIfBlank != nil }
    }

    /// The keys for the Toss Securities API, when this is a complete Toss connection.
    var tossCredentials: Credentials? {
        guard provider == .tossinvest,
              let clientId = values["clientId"]?.nilIfBlank,
              let clientSecret = values["clientSecret"]?.nilIfBlank
        else { return nil }
        return Credentials(clientId: clientId, clientSecret: clientSecret)
    }

    /// A stable id for keys saved before connections existed. Every Mac that migrates the
    /// same keys arrives at the same id, so a synced connection is never added twice.
    static func legacyID(provider: Provider, identity: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(provider.rawValue):\(identity)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // Version 5 (name based).
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant.
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension Connection {
    private enum CodingKeys: String, CodingKey {
        case id, provider, name, values, createdAt
    }

    /// Fills defaults for keys that older records don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        provider = try c.decode(Provider.self, forKey: .provider)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        values = try c.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}

/// A connection and where this Mac found it.
struct StoredConnection: Hashable, Identifiable, Sendable {
    var connection: Connection
    var location: SecretLocation

    var id: UUID { connection.id }
    var syncsWithICloud: Bool { location == .iCloudKeychain }

    /// Combines the connections kept on this Mac and in the iCloud Keychain, oldest first.
    /// A connection found in both places is the synced one.
    static func merge(local: [Connection], synced: [Connection]) -> [StoredConnection] {
        var byID: [UUID: StoredConnection] = [:]
        for connection in local { byID[connection.id] = StoredConnection(connection: connection, location: .local) }
        for connection in synced { byID[connection.id] = StoredConnection(connection: connection, location: .iCloudKeychain) }
        return byID.values.sorted { lhs, rhs in
            if lhs.connection.createdAt != rhs.connection.createdAt {
                return lhs.connection.createdAt < rhs.connection.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// Reads and writes connection records in the secret store, one record per connection.
enum ConnectionVault {
    static let prefix = "connection."

    static func name(for id: UUID) -> String { prefix + id.uuidString }

    static func loadAll(from location: SecretLocation) -> [Connection] {
        SecretStore.names(in: location)
            .filter { $0.hasPrefix(prefix) }
            .compactMap { SecretStore.read(Connection.self, name: $0, from: location) }
    }

    static func save(_ connection: Connection, to location: SecretLocation) throws {
        try SecretStore.write(connection, name: name(for: connection.id), to: location)
    }

    static func delete(_ id: UUID, from location: SecretLocation) {
        SecretStore.delete(name: name(for: id), from: location)
        CachedToken.clear(connection: id, from: location)
    }
}

/// Turns the single set of keys that earlier versions saved into a connection.
///
/// Earlier versions kept one `credentials` record and one `access-token` record, either in
/// local files or in the iCloud Keychain (`secretLocation`). Keys found in either place
/// become a connection in the same place, with the same cached token, and the old records
/// are deleted. Runs once per Mac; a build without the iCloud Keychain entitlement migrates
/// only the local keys and tries again on the next launch, so keys in the iCloud Keychain
/// are still picked up once a signed build runs.
enum ConnectionMigration {
    static let doneKey = "connections.migratedLegacyCredentials"

    struct Legacy: Equatable {
        var credentials: Credentials
        var token: CachedToken?
        var location: SecretLocation
    }

    struct Step: Equatable {
        var connection: Connection
        var location: SecretLocation
        var token: CachedToken?
    }

    struct Plan: Equatable {
        var steps: [Step]
        /// The connection that items saved before connections existed should use.
        var defaultID: UUID?
    }

    /// Decides what to write. Keys from the location this Mac was using come first and
    /// become the default. Keys already migrated, here or by another Mac, aren't written again.
    static func plan(current: SecretLocation, legacy: [Legacy], existingIDs: Set<UUID>, now: Date = Date()) -> Plan {
        let ordered = legacy.filter { $0.location == current } + legacy.filter { $0.location != current }
        var steps: [Step] = []
        var seen = existingIDs
        var defaultID: UUID?
        for entry in ordered where !entry.credentials.clientId.isEmpty {
            let id = Connection.legacyID(provider: .tossinvest, identity: entry.credentials.clientId)
            if defaultID == nil { defaultID = id }
            guard seen.insert(id).inserted else { continue }
            let connection = Connection(
                id: id,
                provider: .tossinvest,
                values: ["clientId": entry.credentials.clientId, "clientSecret": entry.credentials.clientSecret],
                createdAt: now
            )
            let token = entry.token.flatMap { $0.clientId == entry.credentials.clientId ? $0 : nil }
            steps.append(Step(connection: connection, location: entry.location, token: token))
        }
        return Plan(steps: steps, defaultID: defaultID)
    }

    /// Migrates the old keys if this Mac hasn't yet. Returns the default connection's id
    /// when keys were found, so existing items can be pointed at it.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults = .standard, canSync: Bool = SyncedKeychain.isAvailable) -> UUID? {
        guard !defaults.bool(forKey: doneKey) else { return nil }

        var current = SecretLocation.parse(defaults.string(forKey: SecretLocation.legacyKey))
        if current == .iCloudKeychain, !canSync { current = .local }
        let locations: [SecretLocation] = canSync ? [.local, .iCloudKeychain] : [.local]

        var legacy: [Legacy] = []
        for location in locations {
            if let credentials = SecretStore.read(Credentials.self, name: Credentials.legacyName, from: location) {
                let token = SecretStore.read(CachedToken.self, name: CachedToken.legacyName, from: location)
                legacy.append(Legacy(credentials: credentials, token: token, location: location))
            }
        }
        let existing = Set(locations.flatMap { ConnectionVault.loadAll(from: $0).map(\.id) })
        let plan = plan(current: current, legacy: legacy, existingIDs: existing)

        do {
            for step in plan.steps {
                try ConnectionVault.save(step.connection, to: step.location)
                if let token = step.token {
                    CachedToken.save(token, connection: step.connection.id, to: step.location)
                }
            }
        } catch {
            // Leave the old keys in place and try again on the next launch.
            return nil
        }
        for entry in legacy {
            SecretStore.delete(name: Credentials.legacyName, from: entry.location)
            SecretStore.delete(name: CachedToken.legacyName, from: entry.location)
        }
        if canSync {
            defaults.removeObject(forKey: SecretLocation.legacyKey)
            defaults.set(true, forKey: doneKey)
        }
        return plan.defaultID
    }
}
