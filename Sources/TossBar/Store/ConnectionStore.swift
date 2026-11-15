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

/// The connections this Mac can use: those kept in local files and those synced through
/// the iCloud Keychain. Also owns one API client per connection.
@MainActor
final class ConnectionStore: ObservableObject {
    /// Oldest first. The first one is used by items that don't name a connection.
    @Published private(set) var connections: [StoredConnection] = []

    /// Whether this build can use the iCloud Keychain at all (release builds only).
    let canSync = SyncedKeychain.isAvailable

    private var clients: [UUID: TossAPIClient] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        reload()
        // Connections synced from another Mac arrive in the background. Look for them when
        // the app comes forward, and every minute while it sits in the menu bar.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        if canSync {
            Timer.publish(every: 60, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.reload() }
                .store(in: &cancellables)
        }
    }

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
        let synced = canSync ? ConnectionVault.loadAll(from: .iCloudKeychain) : []
        let merged = StoredConnection.merge(local: ConnectionVault.loadAll(from: .local), synced: synced)
        guard merged != connections else { return }
        let previous = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
        for stored in merged {
            guard let client = clients[stored.id], previous[stored.id] != stored else { continue }
            let credentials = stored.connection.tossCredentials
            let location = stored.location
            Task { await client.update(credentials: credentials, location: location) }
        }
        let ids = Set(merged.map(\.id))
        clients = clients.filter { ids.contains($0.key) }
        connections = merged
    }

    /// Saves a new or edited connection and returns it as saved.
    ///
    /// A blank secret field keeps the saved value, so other fields can be edited alone.
    /// `syncWithICloud` moves the connection, with its cached token, between this Mac and
    /// the iCloud Keychain. Moving it out of iCloud removes it from the user's other Macs.
    func save(
        id: UUID?,
        provider: Provider,
        name: String,
        values: [String: String],
        syncWithICloud: Bool
    ) throws -> StoredConnection {
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

        let target: SecretLocation = (syncWithICloud && canSync) ? .iCloudKeychain : .local
        try ConnectionVault.save(connection, to: target)
        if let previous, previous.location != target {
            if let token = CachedToken.load(connection: connection.id, from: previous.location) {
                CachedToken.save(token, connection: connection.id, to: target)
            }
            ConnectionVault.delete(connection.id, from: previous.location)
        }
        reload()
        return StoredConnection(connection: connection, location: target)
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

    /// Deletes a connection. A synced one is deleted from the user's other Macs as well.
    func delete(_ id: UUID) {
        guard let stored = connection(id) else { return }
        ConnectionVault.delete(id, from: stored.location)
        clients[id] = nil
        reload()
    }
}
