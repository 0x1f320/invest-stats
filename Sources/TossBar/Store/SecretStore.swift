import Foundation
import Security

/// Where the API keys and the cached access token are kept on this Mac.
enum SecretLocation: String, Sendable {
    /// User-only files under `~/Library/Application Support/TossBar/`. The default.
    case local
    /// The iCloud Keychain, shared with the user's other Macs. Opt-in, and only available
    /// in builds signed with the provisioning profile that grants a keychain access group.
    case iCloudKeychain

    private static let key = "secretLocation"

    /// The saved choice. Anything missing or unknown means `.local`.
    static func parse(_ raw: String?) -> SecretLocation {
        raw.flatMap(SecretLocation.init(rawValue:)) ?? .local
    }

    static var current: SecretLocation {
        get { parse(UserDefaults.standard.string(forKey: key)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

enum SecretStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "iCloud 키체인에 접근하지 못했습니다: \(detail)"
        }
    }
}

/// Storage for the API keys and the cached access token.
///
/// By default values live in user-only files under `~/Library/Application Support/TossBar/`
/// (directory `0700`, files `0600`). The login Keychain is avoided because it asks for the
/// password again every time the code signature changes, which happens on every rebuild of
/// an ad-hoc signed app. The iCloud Keychain does not have that problem: access is granted
/// by the signed keychain access group, not by a per-item ACL. Users opt into it to share
/// the keys with their other Macs.
enum SecretStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TossBar", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(
                at: base,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        // The folder may already exist with looser permissions, so tighten it every time.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        return base
    }

    static func read<T: Decodable>(_ type: T.Type, name: String, from location: SecretLocation = .current) -> T? {
        guard let data = readData(name: name, from: location) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, name: String, to location: SecretLocation = .current) throws {
        let data = try JSONEncoder().encode(value)
        switch location {
        case .local: try LocalFiles.write(data, name: name)
        case .iCloudKeychain: try SyncedKeychain.write(data, name: name)
        }
    }

    static func delete(name: String, from location: SecretLocation = .current) {
        switch location {
        case .local: LocalFiles.delete(name: name)
        case .iCloudKeychain: SyncedKeychain.delete(name: name)
        }
    }

    private static func readData(name: String, from location: SecretLocation) -> Data? {
        switch location {
        case .local: return LocalFiles.read(name: name)
        case .iCloudKeychain: return SyncedKeychain.read(name: name)
        }
    }

    private enum LocalFiles {
        static func url(_ name: String) -> URL {
            directory.appendingPathComponent("\(name).json")
        }

        static func read(name: String) -> Data? {
            try? Data(contentsOf: url(name))
        }

        static func write(_ data: Data, name: String) throws {
            let target = url(name)
            // Create the file as 0600 before writing, so it is never readable by others.
            if !FileManager.default.fileExists(atPath: target.path) {
                FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try data.write(to: target, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }

        static func delete(name: String) {
            try? FileManager.default.removeItem(at: url(name))
        }
    }
}

/// Generic password items in the iCloud Keychain, synced to the user's other Macs.
///
/// Items go to the data protection keychain under the app's default access group (the
/// first entry of its `keychain-access-groups` entitlement), so no Keychain password
/// prompt ever appears. Only builds signed with the provisioning profile carry that
/// entitlement; ad-hoc builds report `isAvailable == false` and keep using local files.
enum SyncedKeychain {
    private static let service = "dev.tossbar.TossBar"

    /// Whether this build is signed with a keychain access group.
    static let isAvailable: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) as? [String]
        else { return false }
        return !groups.isEmpty
    }()

    private static func query(_ name: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
            kSecAttrSynchronizable: kCFBooleanTrue!,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    static func read(name: String) -> Data? {
        guard isAvailable else { return nil }
        var q = query(name)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, name: String) throws {
        guard isAvailable else { throw SecretStoreError.keychain(errSecMissingEntitlement) }
        let q = query(name)
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel] = "TossBar \(name)"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    static func delete(name: String) {
        guard isAvailable else { return }
        SecItemDelete(query(name) as CFDictionary)
    }
}

struct Credentials: Codable, Hashable, Sendable {
    var clientId: String
    var clientSecret: String

    static let fileName = "credentials"

    static func load(from location: SecretLocation = .current) -> Credentials? {
        SecretStore.read(Credentials.self, name: fileName, from: location)
    }
    static func save(_ value: Credentials, to location: SecretLocation = .current) throws {
        try SecretStore.write(value, name: fileName, to: location)
    }
    static func clear(from location: SecretLocation = .current) {
        SecretStore.delete(name: fileName, from: location)
    }
}

struct CachedToken: Codable, Hashable, Sendable {
    var clientId: String
    var accessToken: String
    var expiresAt: Date

    static let fileName = "access-token"

    /// Whether the token can still be used for `clientId`. A token that expires within the
    /// next minute is treated as expired, so a request never goes out with one about to lapse.
    func isUsable(for clientId: String, now: Date = Date()) -> Bool {
        self.clientId == clientId && expiresAt > now.addingTimeInterval(60)
    }

    static func load(from location: SecretLocation = .current) -> CachedToken? {
        SecretStore.read(CachedToken.self, name: fileName, from: location)
    }
    static func save(_ value: CachedToken, to location: SecretLocation = .current) {
        try? SecretStore.write(value, name: fileName, to: location)
    }
    static func clear(from location: SecretLocation = .current) {
        SecretStore.delete(name: fileName, from: location)
    }
}
