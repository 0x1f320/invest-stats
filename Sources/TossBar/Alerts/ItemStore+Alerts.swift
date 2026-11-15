import Foundation

extension ItemStore {
    func alerts(of id: UUID) -> [PriceAlert] {
        item(id)?.alerts ?? []
    }

    /// Adds an alert to an item. Does nothing for a missing item.
    func addAlert(_ alert: PriceAlert, to id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].alerts.append(alert)
    }

    /// Changes one alert of an item in place. Does nothing for a missing item or alert, or
    /// when nothing changes.
    func updateAlert(_ alertID: UUID, of id: UUID, _ change: (inout PriceAlert) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let alertIndex = items[index].alerts.firstIndex(where: { $0.id == alertID }) else { return }
        var alert = items[index].alerts[alertIndex]
        change(&alert)
        guard alert != items[index].alerts[alertIndex] else { return }
        items[index].alerts[alertIndex] = alert
    }

    func removeAlert(_ alertID: UUID, of id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].alerts.contains(where: { $0.id == alertID }) else { return }
        items[index].alerts.removeAll { $0.id == alertID }
    }

    /// Drops an item's price alerts. A price threshold belongs to one stock, so it goes when
    /// the item switches to another; rate alerts still make sense and stay.
    func removePriceAlerts(of id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].alerts.contains(where: { $0.metric == .price }) else { return }
        items[index].alerts.removeAll { $0.metric == .price }
    }
}
