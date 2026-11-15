import AppKit
import Foundation
import ServiceManagement

/// App-wide dependencies, shared by the menu bar items and the windows.
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: AppSettings
    let store: ItemStore
    let connections: ConnectionStore
    let data: MarketDataHub
    let universe: StockUniverse
    let updater: Updater

    var openSettings: () -> Void = {}

    /// Set by "편집…" in a menu or popover. The settings window opens the editor for it.
    @Published var pendingEdit: UUID?

    init() {
        settings = AppSettings()
        store = ItemStore()
        // Before the connections load: the keys an earlier version saved become one.
        if let migrated = ConnectionMigration.runIfNeeded() {
            store.assignConnection(migrated)
        }
        connections = ConnectionStore()
        data = MarketDataHub(connections: connections, store: store, settings: settings)
        universe = StockUniverse()
        updater = Updater()
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
