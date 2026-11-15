import AppKit
import Combine
import Foundation

enum ConnectionError: LocalizedError {
    case incomplete
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .incomplete:
            return "모든 항목을 입력하세요."
        case .duplicate(let name):
            return "같은 키를 쓰는 연결 '\(name)' 이(가) 이미 있습니다. 토큰이 서로 무효화되니 연결마다 다른 키를 쓰세요."
        }
    }
}

/// The connections this Mac uses, kept either in local files or, when the Mac syncs them,
/// in the iCloud Keychain together with the user's other Macs. Also owns one API client per
/// connection.
@MainActor
final class ConnectionStore: ObservableObject {
    /// Oldest first. The first one is used by items that don't name a connection.
    @Published private(set) var connections: [StoredConnection] = []
    /// Where this Mac keeps its connections. Changed only through `setSync`.
    @Published private(set) var location: SecretLocation
    /// While this Mac doesn't sync: how many connections in the iCloud Keychain it doesn't
    /// have, put there by another Mac. Turning sync on brings them in.
    @Published private(set) var unsyncedSharedCount = 0

    /// Whether this build can use the iCloud Keychain at all (release builds only).
    let canSync = SyncedKeychain.isAvailable

    private var clients: [UUID: TossAPIClient] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        let saved = SecretLocation.saved()
        // A build without the keychain entitlement can't read synced connections.
        location = (saved == .iCloudKeychain && canSync) ? .iCloudKeychain : .local
        reload()
        // Connections from other Macs arrive in the background. Look for them when the app
        // comes forward, and every minute while it sits in the menu bar.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        if canSync {
            Timer.publish(every: 60, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.reload() }
                .store(in: &cancellables)
        }
    }

    var syncsWithICloud: Bool { location == .iCloudKeychain }

    var isEmpty: Bool { connections.isEmpty }

    func connection(_ id: UUID) -> StoredConnection? {
        connections.first { $0.id == id }
    }

    /// The connection an item uses. Items saved before connections existed have none and
    /// use the first connection; an item whose connection was deleted gets nil.
    func resolve(_ id: UUID?) -> StoredConnection? {
        guard let id else { return connections.first }
        return connection(id)
    }

    /// The API client for a connection, created on first use.
    func client(for id: UUID) -> TossAPIClient? {
        connection(id).map(client(for:))
    }

    /// Takes the connection itself, because subscribers to `$connections` hear about a new
    /// connection before `connections` contains it.
    func client(for stored: StoredConnection) -> TossAPIClient {
        if let client = clients[stored.id] { return client }
        let client = TossAPIClient(
            connectionID: stored.id,
            credentials: stored.connection.tossCredentials,
            location: stored.location
        )
        clients[stored.id] = client
        return client
    }

    /// Reads the connections again. Clients of edited connections get the new keys, and
    /// clients of connections deleted elsewhere are dropped.
    func reload() {
        let loaded = StoredConnection.list(ConnectionVault.loadAll(from: location), in: location)
        if canSync, location == .local {
            let shared = ConnectionVault.loadAll(from: .iCloudKeychain)
            let count = StoredConnection.missing(from: loaded.map(\.connection), in: shared).count
            if count != unsyncedSharedCount { unsyncedSharedCount = count }
        } else if unsyncedSharedCount != 0 {
            unsyncedSharedCount = 0
        }
        guard loaded != connections else { return }
        let previous = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
        for stored in loaded {
            guard let client = clients[stored.id], previous[stored.id] != stored else { continue }
            let credentials = stored.connection.tossCredentials
            let location = stored.location
            Task { await client.update(credentials: credentials, location: location) }
        }
        let ids = Set(loaded.map(\.id))
        clients = clients.filter { ids.contains($0.key) }
        connections = loaded
    }

    /// Starts or stops syncing all of this Mac's connections through the iCloud Keychain.
    ///
    /// Turning it on moves the local connections, with their tokens, into the iCloud Keychain
    /// and joins them with those from the user's other Macs. Turning it off copies the synced
    /// connections into local files and stops reading the iCloud Keychain; the synced copies
    /// stay, so the other Macs keep working.
    func setSync(_ enabled: Bool) throws {
        let target: SecretLocation = (enabled && canSync) ? .iCloudKeychain : .local
        guard target != location else { return }
        let source = location
        let copies = StoredConnection.missing(
            from: ConnectionVault.loadAll(from: target),
            in: ConnectionVault.loadAll(from: source)
        )
        for connection in copies {
            try ConnectionVault.save(connection, to: target)
            if let token = CachedToken.load(connection: connection.id, from: source) {
                CachedToken.save(token, connection: connection.id, to: target)
            }
        }
        if source == .local {
            // Now in iCloud, so drop the local copies, including ones iCloud already had.
            for connection in ConnectionVault.loadAll(from: .local) {
                ConnectionVault.delete(connection.id, from: .local)
            }
        }
        location = target
        target.save()
        reload()
    }

    /// Saves a new or edited connection and returns it as saved.
    /// A blank secret field keeps the saved value, so other fields can be edited alone.
    func save(id: UUID?, provider: Provider, name: String, values: [String: String]) throws -> StoredConnection {
        let previous = id.flatMap(connection)
        var merged = previous?.connection.values ?? [:]
        for field in provider.fields {
            if let value = values[field.key]?.nilIfBlank {
                merged[field.key] = value
            } else if !field.isSecret {
                merged[field.key] = nil
            }
        }
        let connection = Connection(
            id: previous?.id ?? UUID(),
            provider: provider,
            name: name.nilIfBlank ?? "",
            values: merged,
            createdAt: previous?.connection.createdAt ?? Date()
        )
        guard connection.isComplete else { throw ConnectionError.incomplete }
        if let other = connections.first(where: {
            $0.id != connection.id && $0.connection.provider == provider && $0.connection.identity == connection.identity
        }) {
            throw ConnectionError.duplicate(other.connection.displayName)
        }
        try ConnectionVault.save(connection, to: location)
        reload()
        return StoredConnection(connection: connection, location: location)
    }

    /// Checks a connection by listing its accounts.
    func test(_ id: UUID) async throws -> [Account] {
        guard let stored = connection(id) else { throw ConnectionError.incomplete }
        let client = client(for: stored)
        // Hand the saved keys to the client first, rather than waiting for the update that
        // `reload` queued, so the test never runs with the old token.
        await client.update(credentials: stored.connection.tossCredentials, location: stored.location)
        return try await client.accounts()
    }

    /// Deletes a connection. While this Mac syncs, that deletes it from the user's other
    /// Macs as well.
    func delete(_ id: UUID) {
        guard let stored = connection(id) else { return }
        ConnectionVault.delete(id, from: stored.location)
        clients[id] = nil
        reload()
    }
}
