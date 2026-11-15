import AppKit

// Before anything reads the settings: bring them over from the app's previous bundle id.
LegacyDefaults.migrateIfNeeded()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar only: no Dock icon and no main menu.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
