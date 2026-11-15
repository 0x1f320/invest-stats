import AppKit
import SwiftUI

/// One tab of a toolbar-tab window.
struct ToolbarTab {
    let id: String
    let label: String
    /// SF Symbol shown in the toolbar.
    let symbol: String
    let content: AnyView

    init<Content: View>(_ id: String, _ label: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.content = AnyView(content())
    }
}

/// Tabs in the window toolbar, the way macOS settings windows show them: icons with labels in
/// a centered toolbar, and the window resized to fit each tab with its top edge kept in place.
/// Each tab's SwiftUI content decides its own size.
final class ToolbarTabController: NSTabViewController {
    /// Called with the tab id whenever the user switches tabs.
    var onSelect: (String) -> Void = { _ in }

    init(tabs: [ToolbarTab], selected: String? = nil) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        for tab in tabs {
            let hosting = NSHostingController(rootView: tab.content)
            // Report the content size, but add no constraints: this controller sizes the window.
            hosting.sizingOptions = [.preferredContentSize]
            hosting.title = tab.label
            let item = NSTabViewItem(viewController: hosting)
            item.identifier = tab.id
            item.label = tab.label
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.label)
            addTabViewItem(item)
        }
        if let selected, let index = tabViewItems.firstIndex(where: { $0.identifier as? String == selected }) {
            selectedTabViewItemIndex = index
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Makes a settings-style window around the tabs, sized to the selected tab.
    func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: self)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        fitWindow(animate: false)
        return window
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String { onSelect(id) }
        fitWindow(animate: view.window?.isVisible ?? false)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === selectedController else { return }
        fitWindow(animate: false)
    }

    private var selectedController: NSViewController? {
        tabViewItems.indices.contains(selectedTabViewItemIndex)
            ? tabViewItems[selectedTabViewItemIndex].viewController
            : nil
    }

    /// Resizes the window to the selected tab's content, keeping its top edge where it is.
    private func fitWindow(animate: Bool) {
        guard let window = view.window, let controller = selectedController else { return }
        var size = controller.preferredContentSize
        if size.width <= 0 || size.height <= 0 {
            size = controller.view.fittingSize
        }
        guard size.width > 0, size.height > 0, let current = window.contentView?.frame.size,
              current != size else { return }
        var frame = window.frame
        frame.size.width += size.width - current.width
        frame.size.height += size.height - current.height
        frame.origin.y -= size.height - current.height
        window.setFrame(frame, display: true, animate: animate)
    }
}
