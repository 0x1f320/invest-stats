import Foundation
import Testing
@testable import TossBar

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@MainActor
@Suite("One-time alerts")
struct OneTimeAlertTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OneTimeAlertTests.\(UUID().uuidString)")!
    }

    @Test func addsOnlyAlertsWithAThreshold() {
        let store = OneTimeAlertStore(defaults: makeDefaults())
        let item = UUID()
        store.add(PriceAlert(metric: .price), to: item)
        #expect(store.alerts.isEmpty)

        store.add(PriceAlert(metric: .price, threshold: 72000), to: item)
        #expect(store.alerts(of: item).map(\.threshold) == [72000])
        #expect(store.alerts(of: UUID()).isEmpty)
    }

    @Test func alwaysOnAndOnce() {
        let alert = OneTimeAlert(itemID: UUID(), alert: PriceAlert(metric: .price, threshold: 1, repeatMode: .everyCross, isEnabled: false))
        #expect(alert.alert.isEnabled)
        #expect(alert.alert.repeatMode == .once)
        #expect(alert.id == alert.alert.id)
    }

    @Test func persistsApartFromTheItems() {
        let defaults = makeDefaults()
        let item = UUID()
        let alert = PriceAlert(metric: .holdingRate, direction: .atOrBelow, threshold: dec("-0.1"))
        OneTimeAlertStore(defaults: defaults).add(alert, to: item)

        let reloaded = OneTimeAlertStore(defaults: defaults)
        #expect(reloaded.alerts(of: item).map(\.id) == [alert.id])
        #expect(reloaded.alerts(of: item).first?.threshold == dec("-0.1"))
        #expect(defaults.data(forKey: ItemStore.defaultsKey) == nil)
    }

    @Test func skipsAlertsANewerBuildSaved() throws {
        let defaults = makeDefaults()
        let item = UUID()
        let known = OneTimeAlert(itemID: item, alert: PriceAlert(metric: .price, threshold: 100))
        var list = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([known])) as? [[String: Any]])
        var unknown = list[0]
        unknown["alert"] = ["id": UUID().uuidString, "metric": "volume", "threshold": "1"]
        list.append(unknown)
        defaults.set(try JSONSerialization.data(withJSONObject: list), forKey: OneTimeAlertStore.defaultsKey)

        #expect(OneTimeAlertStore(defaults: defaults).alerts.map(\.id) == [known.id])
    }

    @Test func removesByIDAndWithTheirItem() {
        let store = OneTimeAlertStore(defaults: makeDefaults())
        let kept = UUID(), deleted = UUID()
        let first = PriceAlert(metric: .price, threshold: 1)
        let second = PriceAlert(metric: .changeRate, threshold: dec("0.05"))
        store.add(first, to: kept)
        store.add(second, to: kept)
        store.add(PriceAlert(metric: .profitRate, threshold: dec("0.1")), to: deleted)

        store.remove(first.id)
        #expect(store.alerts(of: kept).map(\.id) == [second.id])

        store.keepOnly(items: [kept])
        #expect(store.alerts(of: deleted).isEmpty)
        #expect(store.alerts.count == 1)
    }

    @Test func switchingTheStockDropsPriceAndProfitAlerts() {
        let store = OneTimeAlertStore(defaults: makeDefaults())
        let item = UUID(), other = UUID()
        let rate = PriceAlert(metric: .changeRate, threshold: dec("0.05"))
        store.add(PriceAlert(metric: .price, threshold: 100), to: item)
        store.add(PriceAlert(metric: .holdingProfit, threshold: 1000), to: item)
        store.add(rate, to: item)
        store.add(PriceAlert(metric: .price, threshold: 100), to: other)

        store.removePriceAlerts(of: item)
        #expect(store.alerts(of: item).map(\.id) == [rate.id])
        #expect(store.alerts(of: other).count == 1)
    }

    @Test func oneTimeHoldingAlertsFetchHoldingsAndTheRate() {
        let item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")))
        let other = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "MSFT")))
        #expect([item, other].holdingStockConfigs.isEmpty)
        #expect(![item, other].needsUsdKrwForStocks)

        let oneTime = [OneTimeAlert(itemID: item.id, alert: PriceAlert(metric: .holdingProfit, threshold: 1, currency: .krw))]
        let effective = [item, other].includingOneTimeAlerts(oneTime)
        #expect(effective.holdingStockConfigs.map(\.symbol) == ["AAPL"])
        #expect(effective.needsUsdKrwForStocks)
        // The item's own alerts are untouched.
        #expect(item.alerts.isEmpty)
    }
}
