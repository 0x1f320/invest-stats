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
    let alertNotifier: AlertNotifier
    let alertMonitor: AlertMonitor

    var openSettings: () -> Void = {}
    /// Opens an add dialog or an item's settings window.
    var openEditor: (EditorTarget) -> Void = { _ in }

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
        alertNotifier = AlertNotifier()
        alertMonitor = AlertMonitor(store: store, data: data, notifier: alertNotifier)
        alertNotifier.onSellAction = { [weak self] action in
            guard let self, self.store.item(action.itemID) != nil else { return }
            self.openEditor(.sell(action))
        }
    }

    /// Opens an item's settings window, from a menu, popover or the settings list.
    func editItem(_ id: UUID) {
        guard store.item(id) != nil else { return }
        openEditor(.item(id))
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
