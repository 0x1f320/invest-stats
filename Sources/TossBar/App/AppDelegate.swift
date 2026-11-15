import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let env = AppEnvironment()
    private var statusBar: StatusBarManager?
    private var editors: ItemEditorWindows?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var updateWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarManager(env: env)
        editors = ItemEditorWindows(env: env)
        env.openSettings = { [weak self] in self?.showSettings() }
        env.openEditor = { [weak self] in self?.editors?.open($0) }
        env.updater.presentOffer = { [weak self] in self?.showUpdate() }
        env.data.start()
        env.updater.start()

        // First launch (no connection yet, here or in iCloud): set one up.
        if env.connections.isEmpty {
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func makeWindow<V: View>(title: String, rootView: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(
                title: "Invest Stats",
                rootView: OnboardingView(env: env) { [weak self] in
                    self?.onboardingWindow?.close()
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if env.connections.isEmpty {
            showOnboarding()
            return
        }
        if settingsWindow == nil {
            let defaults = UserDefaults.standard
            let tabs = ToolbarTabController(
                tabs: SettingsTabs.make(env: env),
                selected: SettingsTabs.savedSelection
            )
            tabs.onSelect = { defaults.set($0, forKey: SettingsTabs.selectionKey) }
            let window = tabs.makeWindow()
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showUpdate() {
        if updateWindow == nil {
            updateWindow = makeWindow(
                title: "Invest Stats 업데이트",
                rootView: UpdateView(updater: env.updater) { [weak self] in
                    self?.updateWindow?.close()
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        updateWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow { onboardingWindow = nil }
        if window === settingsWindow { settingsWindow = nil }
        if window === updateWindow { updateWindow = nil }
    }
}
