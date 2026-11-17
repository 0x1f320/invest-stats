import AppKit
import Combine
import SwiftUI

/// What an item window adds or configures.
enum EditorTarget {
    /// The dialog that adds a stock item.
    case newStock
    /// The dialog that adds an asset item.
    case newAsset
    /// The dialog that adds an indicator item.
    case newIndicator
    /// An existing item's settings window.
    case item(UUID)
    /// The sell dialog for a stock item's holding, from an alert's notification.
    case sell(SellAction)

    var key: String {
        switch self {
        case .newStock: return "newStock"
        case .newAsset: return "newAsset"
        case .newIndicator: return "newIndicator"
        case .item(let id): return "item.\(id.uuidString)"
        // One sell dialog per item: a second action brings the open one forward.
        case .sell(let action): return "sell.\(action.itemID.uuidString)"
        }
    }

    var itemID: UUID? {
        switch self {
        case .item(let id): return id
        case .sell(let action): return action.itemID
        default: return nil
        }
    }

    /// Whether the window's title follows the item's name.
    var isSettings: Bool {
        if case .item = self { return true }
        return false
    }
}

/// Opens the add dialogs and the item settings windows, each in its own window instead of a
/// sheet over the settings window, so a menu or popover can open them on their own.
/// Each target has at most one window; opening it again brings that window to the front.
@MainActor
final class ItemEditorWindows: NSObject, NSWindowDelegate {
    private struct Entry {
        let window: NSWindow
        let itemID: UUID?
        let isSettings: Bool
    }

    private let env: AppEnvironment
    private var entries: [String: Entry] = [:]
    private var cascadePoint = NSPoint.zero
    private var itemsObserver: AnyCancellable?

    init(env: AppEnvironment) {
        self.env = env
        super.init()
        itemsObserver = env.store.$items.sink { [weak self] items in
            self?.itemsChanged(items)
        }
    }

    func open(_ target: EditorTarget) {
        if let window = entries[target.key]?.window {
            activate(window)
            return
        }
        guard let window = makeWindow(target) else { return }
        window.delegate = self
        if entries.isEmpty {
            window.center()
            cascadePoint = .zero
        }
        // Offsets each window from the previous one so they don't stack exactly.
        cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        entries[target.key] = Entry(window: window, itemID: target.itemID, isSettings: target.isSettings)
        activate(window)
    }

    private func makeWindow(_ target: EditorTarget) -> NSWindow? {
        let key = target.key
        let close: () -> Void = { [weak self] in self?.entries[key]?.window.close() }
        // Adding closes the dialog and continues in the new item's settings window.
        let added: (UUID) -> Void = { [weak self] id in
            close()
            self?.open(.item(id))
        }

        switch target {
        case .newStock:
            return makeDialog(title: "주가 항목 추가", StockAddDialog(env: env, cancel: close, added: added))
        case .newAsset:
            return makeDialog(title: "자산 항목 추가", AssetAddDialog(env: env, cancel: close, added: added))
        case .newIndicator:
            return makeDialog(title: "지표 항목 추가", IndicatorAddDialog(env: env, cancel: close, added: added))
        case .sell(let action):
            guard env.store.item(action.itemID) != nil else { return nil }
            return makeDialog(title: "매도 주문", SellOrderView(env: env, action: action, close: close))
        case .item(let id):
            guard let item = env.store.item(id) else { return nil }
            let tabs = ToolbarTabController(tabs: settingsTabs(for: item))
            // The window shows which item it configures, not the tab name.
            tabs.canPropagateSelectedChildViewControllerTitle = false
            let window = tabs.makeWindow()
            window.title = title(for: item)
            return window
        }
    }

    private func makeDialog<Content: View>(title: String, _ content: Content) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        // Size to the laid-out content before placing the window. Otherwise it shrinks after
        // it appears, and because AppKit keeps the bottom edge, its top edge moves.
        window.setContentSize(hosting.view.fittingSize)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }

    private func settingsTabs(for item: MenuItemConfig) -> [ToolbarTab] {
        let id = item.id
        switch item.kind {
        case .stock:
            return [
                ToolbarTab("symbol", "종목", symbol: "chart.xyaxis.line") {
                    StockSymbolPane(env: env, id: id)
                },
                ToolbarTab("display", "표시", symbol: "menubar.rectangle") {
                    StockDisplayPane(env: env, id: id)
                },
                ToolbarTab("holding", "보유", symbol: "briefcase") {
                    StockHoldingPane(env: env, id: id)
                },
                ToolbarTab("alerts", "알림", symbol: "bell") {
                    ItemAlertsPane(env: env, id: id)
                },
            ]
        case .asset:
            return [
                ToolbarTab("account", "계좌", symbol: "building.columns") {
                    AssetAccountPane(env: env, id: id)
                },
                ToolbarTab("profit", "손익", symbol: "wonsign.circle") {
                    AssetProfitPane(id: id, store: env.store)
                },
                ToolbarTab("display", "표시", symbol: "menubar.rectangle") {
                    AssetDisplayPane(env: env, id: id)
                },
                ToolbarTab("alerts", "알림", symbol: "bell") {
                    ItemAlertsPane(env: env, id: id)
                },
            ]
        case .indicator:
            return [
                ToolbarTab("indicator", "지표", symbol: "chart.line.uptrend.xyaxis") {
                    IndicatorSourcePane(env: env, id: id)
                },
                ToolbarTab("display", "표시", symbol: "menubar.rectangle") {
                    IndicatorDisplayPane(env: env, id: id)
                },
            ]
        }
    }

    /// The item settings window's title, matching the item's row in the settings list.
    private func title(for item: MenuItemConfig) -> String {
        switch item.kind {
        case .stock(let config):
            let name = config.displayName?.nilIfBlank
                ?? env.universe.entries.first { $0.symbol == config.symbol }?.name
                ?? env.data.service(for: item)?.stockInfo[config.symbol]?.name
                ?? config.symbol
            return "주가 · \(name)"
        case .asset(let config):
            return "자산" + (config.label.nilIfBlank.map { " · \($0)" } ?? "")
        case .indicator(let config):
            return "지표 · \(config.displayName?.nilIfBlank ?? config.indicator?.name ?? config.symbol)"
        }
    }

    private func itemsChanged(_ items: [MenuItemConfig]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for entry in entries.values {
            guard let id = entry.itemID else { continue }
            if let item = byID[id] {
                if entry.isSettings { entry.window.title = title(for: item) }
            } else {
                // The item was deleted elsewhere; its settings window has nothing left to edit.
                entry.window.close()
            }
        }
    }

    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = entries.first(where: { $0.value.window === window })?.key else { return }
        entries[key] = nil
    }
}
