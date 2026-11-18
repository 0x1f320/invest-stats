import AppKit
import UserNotifications

/// Delivers alerts through Notification Center and tracks whether macOS allows them.
///
/// `UNUserNotificationCenter` needs an app bundle: in a bare executable, such as
/// `.build/debug/TossBar`, `current()` raises an exception. There the notifier never
/// touches it, reports `.unavailable`, and prints alerts to stdout instead.
@MainActor
final class AlertNotifier: NSObject, ObservableObject {
    enum Authorization: Equatable {
        /// Not running from an app bundle, so Notification Center can't be used.
        case unavailable
        /// The user hasn't been asked yet.
        case notDetermined
        /// The user turned notifications off in System Settings.
        case denied
        /// Notifications are allowed, possibly delivered quietly.
        case allowed
    }

    @Published private(set) var authorization: Authorization

    /// Called when the user chooses a sell action on a holding alert's notification.
    var onSellAction: (SellAction) -> Void = { _ in }

    /// nil outside an app bundle.
    private let center: UNUserNotificationCenter?
    private var activationObserver: NSObjectProtocol?

    /// Whether this process can use Notification Center: it must be an app bundle with a
    /// bundle id.
    nonisolated static func canUseNotificationCenter(bundle: Bundle = .main) -> Bool {
        bundle.bundleIdentifier != nil && bundle.bundleURL.pathExtension == "app"
    }

    init(bundle: Bundle = .main) {
        center = Self.canUseNotificationCenter(bundle: bundle) ? UNUserNotificationCenter.current() : nil
        authorization = center == nil ? .unavailable : .notDetermined
        super.init()
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories([Self.sellCategory])
        refreshAuthorization()
        // The user may have changed the setting in System Settings meanwhile.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAuthorization() }
        }
    }

    func refreshAuthorization() {
        guard let center else { return }
        Task {
            let status = await center.notificationSettings().authorizationStatus
            let mapped = Self.authorization(for: status)
            if authorization != mapped { authorization = mapped }
        }
    }

    nonisolated static func authorization(for status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Asks for permission the first time the user sets up an alert. Does nothing once the
    /// user has answered; after a denial only System Settings can change it.
    func requestAuthorizationIfNeeded() {
        guard let center, authorization == .notDetermined else { return }
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                print("[alert] notification permission request failed: \(error.localizedDescription)")
            }
            refreshAuthorization()
        }
    }

    /// The actions on a holding alert's notification. Each opens the app's sell
    /// dialog, which asks for the quantity and a confirmation before ordering.
    private static var sellCategory: UNNotificationCategory {
        let actions = OrderType.allCases.map {
            UNNotificationAction(identifier: SellAction.actionIdentifier(for: $0),
                                 title: SellAction.actionTitle(for: $0),
                                 options: [.foreground])
        }
        return UNNotificationCategory(identifier: SellAction.category, actions: actions, intentIdentifiers: [])
    }

    /// Posts a notification. `thread` groups an item's notifications together, and
    /// `sellItem` adds the sell actions for that item.
    func post(title: String, subtitle: String? = nil, body: String, thread: String, sellItem: UUID? = nil) {
        guard let center else {
            print("[alert] \(title)\(subtitle.map { " (\($0))" } ?? "") — \(body)")
            fflush(stdout)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        if let sellItem {
            content.categoryIdentifier = SellAction.category
            content.userInfo = SellAction.userInfo(itemID: sellItem)
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { print("[alert] could not post a notification: \(error.localizedDescription)") }
        }
    }

    /// Opens this app's page in the Notifications settings, or the Notifications pane.
    func openSystemSettings() {
        var candidates = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
        if let bundleID = Bundle.main.bundleIdentifier {
            candidates.insert("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)", at: 0)
        }
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

extension AlertNotifier: UNUserNotificationCenterDelegate {
    /// Shows banners while the app is active too, such as while a settings window is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Hands a chosen sell action to the app. Clicks on the notification itself and
    /// dismissals do nothing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let action = SellAction(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo,
            deliveredAt: response.notification.date
        ) else { return }
        await MainActor.run { self.onSellAction(action) }
    }
}
