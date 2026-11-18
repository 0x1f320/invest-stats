import Foundation

/// An alert added from a menu bar item's context menu. It watches one of the item's values
/// like the item's own alerts, but lives apart from them: it isn't part of the item's
/// settings, fires once, and is then deleted.
struct OneTimeAlert: Codable, Hashable, Identifiable {
    /// The item whose value the alert watches.
    var itemID: UUID
    /// The condition. Its repeat mode and on/off switch don't apply.
    var alert: PriceAlert
    var createdAt: Date

    var id: UUID { alert.id }

    init(itemID: UUID, alert: PriceAlert, createdAt: Date = Date()) {
        self.itemID = itemID
        self.alert = alert
        self.alert.isEnabled = true
        self.alert.repeatMode = .once
        self.createdAt = createdAt
    }
}

extension PriceAlert {
    /// A price or an amount of profit belongs to one stock, so an alert on it goes when its
    /// item switches to another stock; rate alerts still make sense and stay.
    var isAmountOfOneStock: Bool { metric == .price || metric == .holdingProfit }
}

/// The pending one-time alerts of every item, persisted in UserDefaults apart from the items.
@MainActor
final class OneTimeAlertStore: ObservableObject {
    nonisolated static let defaultsKey = "oneTimeAlerts.v1"

    @Published private(set) var alerts: [OneTimeAlert] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Lossy, so an alert saved by a newer build with a metric this one doesn't know is
        // skipped instead of dropping the rest.
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([LossyDecodable<OneTimeAlert>].self, from: data) {
            alerts = decoded.compactMap(\.value)
        } else {
            alerts = []
        }
    }

    /// An item's pending one-time alerts, oldest first.
    func alerts(of itemID: UUID) -> [PriceAlert] {
        alerts.filter { $0.itemID == itemID }.map(\.alert)
    }

    /// Adds a one-time alert on an item. An alert without a threshold would never fire, so
    /// it isn't added.
    func add(_ alert: PriceAlert, to itemID: UUID, now: Date = Date()) {
        guard alert.threshold != nil else { return }
        alerts.append(OneTimeAlert(itemID: itemID, alert: alert, createdAt: now))
    }

    func remove(_ ids: Set<UUID>) {
        guard alerts.contains(where: { ids.contains($0.id) }) else { return }
        alerts.removeAll { ids.contains($0.id) }
    }

    func remove(_ id: UUID) {
        remove([id])
    }

    /// Drops an item's price and holding profit alerts, when the item switches to another
    /// stock. See `PriceAlert.isAmountOfOneStock`.
    func removePriceAlerts(of itemID: UUID) {
        guard alerts.contains(where: { $0.itemID == itemID && $0.alert.isAmountOfOneStock }) else { return }
        alerts.removeAll { $0.itemID == itemID && $0.alert.isAmountOfOneStock }
    }

    /// Drops the alerts of items that no longer exist.
    func keepOnly(items ids: Set<UUID>) {
        guard alerts.contains(where: { !ids.contains($0.itemID) }) else { return }
        alerts.removeAll { !ids.contains($0.itemID) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(alerts) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

extension Array where Element == MenuItemConfig {
    /// The items with each one's pending one-time alerts counted among its alerts, so the
    /// data they read (a stock's holdings, the USD/KRW rate) is fetched for them too.
    func includingOneTimeAlerts(_ oneTime: [OneTimeAlert]) -> [MenuItemConfig] {
        guard !oneTime.isEmpty else { return self }
        let byItem = Dictionary(grouping: oneTime, by: \.itemID)
        return map { item in
            guard let extra = byItem[item.id] else { return item }
            var item = item
            item.alerts += extra.map(\.alert)
            return item
        }
    }
}
