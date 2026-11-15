import AppKit
import Foundation
import ServiceManagement

/// App-wide dependencies, shared by the menu bar items and the windows.
@MainActor
final class AppEnvironment: ObservableObject {
    let client = TossAPIClient.shared
    let settings: AppSettings
    let store: ItemStore
    let credentials: CredentialStore
    let data: MarketDataService
    let universe: StockUniverse

    var openSettings: () -> Void = {}

    /// Set by "편집…" in a menu or popover. The settings window opens the editor for it.
    @Published var pendingEdit: UUID?

    init() {
        settings = AppSettings()
        store = ItemStore()
        credentials = CredentialStore(client: client)
        data = MarketDataService(client: client, store: store, settings: settings)
        universe = StockUniverse(client: client)
        credentials.onChange = { [weak self] in self?.data.reset() }
    }

    func editItem(_ id: UUID) {
        UserDefaults.standard.set("items", forKey: "settingsTab")
        openSettings()
        pendingEdit = id
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class CredentialStore: ObservableObject {
    @Published private(set) var clientId: String
    @Published private(set) var hasSecret: Bool
    /// Where this Mac keeps the keys. Changed only through `saveAndTest` or `useSharedKeys`.
    @Published private(set) var location: SecretLocation
    /// Keys found in the iCloud Keychain, put there by another Mac, while this Mac has none.
    @Published private(set) var sharedClientId: String?

    /// Whether this build can use the iCloud Keychain at all (release builds only).
    let canSync = SyncedKeychain.isAvailable

    /// Called when the saved keys change, so cached data from the old keys can be dropped.
    var onChange: () -> Void = {}
    private let client: TossAPIClient

    init(client: TossAPIClient) {
        self.client = client
        var location = SecretLocation.current
        if location == .iCloudKeychain, !SyncedKeychain.isAvailable {
            // A build without the keychain entitlement cannot read the shared keys.
            location = .local
        }
        self.location = location
        let stored = Credentials.load(from: location)
        clientId = stored?.clientId ?? ""
        hasSecret = !(stored?.clientSecret.isEmpty ?? true)
        sharedClientId = nil
        if stored == nil, location == .local, canSync {
            sharedClientId = Credentials.load(from: .iCloudKeychain)?.clientId
        }
    }

    var isConfigured: Bool { !clientId.isEmpty && hasSecret }
    var syncsWithICloud: Bool { location == .iCloudKeychain }

    /// Saves the keys, then checks them by issuing a token and listing the accounts.
    /// An empty secret keeps the one already saved, so the ID can be edited alone.
    /// `syncWithICloud` moves the keys between local files and the iCloud Keychain.
    func saveAndTest(clientId: String, clientSecret: String?, syncWithICloud: Bool) async throws -> [Account] {
        let trimmedId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = Credentials.load(from: location)
        let resolvedSecret: String
        if let secret, !secret.isEmpty {
            resolvedSecret = secret
        } else if let existing = previous?.clientSecret, !existing.isEmpty {
            resolvedSecret = existing
        } else {
            throw TossAPIError.missingCredentials
        }
        let credentials = Credentials(clientId: trimmedId, clientSecret: resolvedSecret)
        let target: SecretLocation = (syncWithICloud && canSync) ? .iCloudKeychain : .local

        try Credentials.save(credentials, to: target)
        if target != location {
            move(from: location, to: target)
        }
        let changed = credentials != previous
        self.clientId = trimmedId
        self.hasSecret = true
        self.sharedClientId = nil
        // Hand the new keys to the client before anyone refreshes with the old token.
        await client.updateCredentials(credentials)
        if changed { onChange() }
        return try await client.accounts()
    }

    /// Switches this Mac to the keys another Mac shared through the iCloud Keychain.
    func useSharedKeys() async throws -> [Account] {
        guard canSync, let shared = Credentials.load(from: .iCloudKeychain) else {
            throw TossAPIError.missingCredentials
        }
        setLocation(.iCloudKeychain)
        clientId = shared.clientId
        hasSecret = !shared.clientSecret.isEmpty
        sharedClientId = nil
        await client.updateCredentials(shared)
        onChange()
        return try await client.accounts()
    }

    /// Deletes the keys from where this Mac keeps them. In the iCloud Keychain that also
    /// removes them from the user's other Macs.
    func clear() async {
        Credentials.clear(from: location)
        CachedToken.clear(from: location)
        setLocation(.local)
        clientId = ""
        hasSecret = false
        await client.updateCredentials(nil)
        onChange()
    }

    /// Moves the cached token to `target` and switches to it. Local copies are removed when
    /// moving to iCloud. Leaving iCloud keeps the shared copies, so other Macs still work.
    private func move(from source: SecretLocation, to target: SecretLocation) {
        if let token = CachedToken.load(from: source) {
            CachedToken.save(token, to: target)
        }
        if source == .local {
            Credentials.clear(from: .local)
            CachedToken.clear(from: .local)
        }
        setLocation(target)
    }

    private func setLocation(_ newValue: SecretLocation) {
        SecretLocation.current = newValue
        location = newValue
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
