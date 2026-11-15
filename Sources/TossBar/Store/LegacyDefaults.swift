import Foundation

/// Carries settings over from the bundle id the app shipped with before it was renamed.
///
/// UserDefaults are stored per bundle id, so the renamed app starts with an empty domain.
/// On the first launch, everything in the old domain is copied over: the item list, app
/// settings, the secret location and the saved menu bar positions (`NSStatusItem Preferred
/// Position TossBar.<uuid>`). The old domain is left untouched, so the old app keeps working.
enum LegacyDefaults {
    static let legacyBundleID = "dev.tossbar.TossBar"
    static let migratedKey = "migratedFromLegacyBundleID"

    /// Runs once per Mac, before anything reads the settings.
    static func migrateIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID != legacyBundleID else { return }
        migrate(from: legacyValues(), into: .standard)
    }

    /// Copies `legacy` into `defaults` unless that was done before or `defaults` already has
    /// items. Keys already set in `defaults` win over the legacy values.
    static func migrate(from legacy: [String: Any], into defaults: UserDefaults) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard defaults.object(forKey: ItemStore.defaultsKey) == nil else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    /// The old app's own preferences, without the global domain that `UserDefaults(suiteName:)`
    /// would mix in.
    private static func legacyValues() -> [String: Any] {
        let app = legacyBundleID as CFString
        let user = kCFPreferencesCurrentUser
        let host = kCFPreferencesAnyHost
        guard let keys = CFPreferencesCopyKeyList(app, user, host) as? [String], !keys.isEmpty,
              let values = CFPreferencesCopyMultiple(keys as CFArray, app, user, host) as? [String: Any]
        else { return [:] }
        return values
    }
}
