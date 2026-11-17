import Foundation
import Testing
@testable import TossBar

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Price alert conditions")
struct PriceAlertConditionTests {
    @Test func priceAtOrAbove() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 72000)
        #expect(alert.isMet(by: 72000))
        #expect(alert.isMet(by: 72100))
        #expect(!alert.isMet(by: 71900))
    }

    @Test func priceAtOrBelow() {
        let alert = PriceAlert(metric: .price, direction: .atOrBelow, threshold: dec("185.5"))
        #expect(alert.isMet(by: dec("185.5")))
        #expect(alert.isMet(by: dec("185.49")))
        #expect(!alert.isMet(by: dec("185.51")))
    }

    @Test func changeBeyondEitherWay() {
        let alert = PriceAlert(metric: .changeRate, direction: .beyond, threshold: dec("0.05"))
        #expect(alert.isMet(by: dec("0.05")))
        #expect(alert.isMet(by: dec("-0.0512")))
        #expect(!alert.isMet(by: dec("0.0499")))
        #expect(!alert.isMet(by: dec("-0.03")))
    }

    @Test func unsetThresholdNeverMeets() {
        let alert = PriceAlert(metric: .price, threshold: nil)
        #expect(!alert.isMet(by: 0))
        #expect(!alert.isMet(by: 1_000_000))
    }

    @Test func priceRearmMarginIsHalfAPercentOfTheThreshold() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 80000)
        #expect(alert.rearmMargin() == 400)
        #expect(!alert.hasCleared(79600))
        #expect(alert.hasCleared(79599))
    }

    @Test func rateRearmMarginIsHalfAPercentagePoint() {
        let alert = PriceAlert(metric: .profitRate, direction: .atOrBelow, threshold: dec("-0.1"))
        #expect(alert.rearmMargin() == dec("0.005"))
        #expect(!alert.hasCleared(dec("-0.095")))
        #expect(alert.hasCleared(dec("-0.0949")))
    }

    @Test func smallBeyondAlertRearmsHalfwayToZero() {
        let alert = PriceAlert(metric: .changeRate, direction: .beyond, threshold: dec("0.004"))
        #expect(alert.rearmMargin() == dec("0.002"))
        #expect(alert.hasCleared(dec("0.0019")))
        #expect(alert.hasCleared(dec("-0.0019")))
        #expect(!alert.hasCleared(dec("-0.002")))
    }

    @Test func directionsOfferedPerMetric() {
        #expect(AlertMetric.price.directions == [.atOrAbove, .atOrBelow])
        #expect(AlertMetric.changeRate.directions == [.atOrAbove, .atOrBelow, .beyond])
        #expect(AlertMetric.holdingProfit.directions == [.atOrAbove, .atOrBelow, .beyond])
        #expect(AlertMetric.available(for: .stock(StockItemConfig(symbol: "AAPL")))
            == [.price, .changeRate, .holdingProfit, .holdingRate])
        #expect(AlertMetric.available(for: .asset(AssetItemConfig())) == [.profitRate])
        #expect(AlertMetric.available(for: .indicator(IndicatorItemConfig(symbol: "KOSPI"))).isEmpty)
    }
}

@Suite("Price alert evaluation")
struct AlertEvaluatorTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private var seoul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    /// Feeds values one by one and returns which observations fired.
    private func run(
        _ alert: PriceAlert,
        _ values: [Decimal],
        subject: String = "stock:005930",
        state: AlertState? = nil,
        spacing: TimeInterval = 10
    ) -> (fires: [Bool], state: AlertState?) {
        var state = state
        var fires: [Bool] = []
        let signature = AlertEvaluator.signature(for: alert, subject: subject)
        for (index, value) in values.enumerated() {
            let step = AlertEvaluator.step(
                alert, signature: signature, value: value, previous: state,
                now: start.addingTimeInterval(Double(index) * spacing), calendar: seoul
            )
            state = step.state
            fires.append(step.fires)
        }
        return (fires, state)
    }

    @Test func firesOnceWhenCrossingIn() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 72000)
        let result = run(alert, [71000, 71500, 72000, 72500, 73000])
        #expect(result.fires == [false, false, true, false, false])
        #expect(result.state?.phase == .triggered)
        #expect(result.state?.lastFiredAt == start.addingTimeInterval(20))
    }

    @Test func conditionAlreadyMetAtFirstLookDoesNotFire() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 70000)
        let result = run(alert, [72000, 72500])
        #expect(result.fires == [false, false])
        #expect(result.state?.phase == .triggered)
    }

    @Test func hoveringAtTheThresholdDoesNotRefire() {
        // 0.5% of 80,000 is 400: dipping to 79,700 doesn't re-arm.
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 80000)
        let result = run(alert, [79000, 80000, 79900, 80000, 79700, 80100])
        #expect(result.fires == [false, true, false, false, false, false])
    }

    @Test func rearmsAfterClearingTheMargin() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 80000)
        let result = run(alert, [79000, 80000, 79500, 80200])
        #expect(result.fires == [false, true, false, true])
    }

    @Test func beyondFiresOnEitherSideAfterRearming() {
        let alert = PriceAlert(metric: .changeRate, direction: .beyond, threshold: dec("0.05"))
        let result = run(alert, [dec("0.01"), dec("0.051"), dec("0.02"), dec("-0.06")])
        #expect(result.fires == [false, true, false, true])
    }

    @Test func oncePerDayLetsOneCrossingNotifyPerDay() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 80000, repeatMode: .oncePerDay)
        let sameDay = run(alert, [79000, 80000, 79000, 80000])
        #expect(sameDay.fires == [false, true, false, false])

        // A day later, the next crossing notifies again.
        let nextDay = run(alert, [79000, 80000], state: sameDay.state, spacing: 86_400)
        #expect(nextDay.fires == [false, true])
    }

    @Test func oncePerDayUsesTheGivenTimeZone() {
        // 23:59 and 00:01 in Seoul are different days even though only 2 minutes apart.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 23, minute: 59))!
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 100, repeatMode: .oncePerDay)
        let signature = AlertEvaluator.signature(for: alert, subject: "stock:X")
        let fired = AlertState(signature: signature, phase: .armed, lastFiredAt: beforeMidnight)
        let step = AlertEvaluator.step(alert, signature: signature, value: 101, previous: fired,
                                       now: beforeMidnight.addingTimeInterval(120), calendar: calendar)
        #expect(step.fires)
    }

    @Test func changedSignatureStartsOver() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 72000)
        let armed = run(alert, [71000]).state
        // Same alert, another stock: the old baseline doesn't count.
        let result = run(alert, [73000], subject: "stock:000660", state: armed)
        #expect(result.fires == [false])
        #expect(result.state?.phase == .triggered)
    }

    @Test func signatureCoversSubjectAndCondition() {
        let alert = PriceAlert(metric: .changeRate, direction: .atOrBelow, threshold: dec("-0.03"))
        #expect(AlertEvaluator.signature(for: alert, subject: "stock:AAPL") == "stock:AAPL|changeRate|atOrBelow|-0.03")
        var edited = alert
        edited.repeatMode = .once
        edited.isEnabled = false
        // Repeat and on/off don't change what is compared, so they keep the state.
        #expect(AlertEvaluator.signature(for: edited, subject: "stock:AAPL") == AlertEvaluator.signature(for: alert, subject: "stock:AAPL"))
        edited.threshold = dec("-0.04")
        #expect(AlertEvaluator.signature(for: edited, subject: "stock:AAPL") != AlertEvaluator.signature(for: alert, subject: "stock:AAPL"))
    }
}

@Suite("Price alert text")
struct AlertThresholdTests {
    @Test func parsesPrices() {
        #expect(AlertThreshold.parse("72,000", metric: .price) == 72000)
        #expect(AlertThreshold.parse(" 72000원 ", metric: .price) == 72000)
        #expect(AlertThreshold.parse("$185.5", metric: .price) == dec("185.5"))
        #expect(AlertThreshold.parse("0", metric: .price) == nil)
        #expect(AlertThreshold.parse("-5", metric: .price) == nil)
        #expect(AlertThreshold.parse("12abc", metric: .price) == nil)
        #expect(AlertThreshold.parse("", metric: .price) == nil)
        #expect(AlertThreshold.parse("-", metric: .price) == nil)
    }

    @Test func parsesPercentagesAsRatios() {
        #expect(AlertThreshold.parse("5", metric: .changeRate) == dec("0.05"))
        #expect(AlertThreshold.parse("+5%", metric: .changeRate) == dec("0.05"))
        #expect(AlertThreshold.parse("-3.5", metric: .profitRate) == dec("-0.035"))
        #expect(AlertThreshold.parse("0", metric: .profitRate) == 0)
    }

    @Test func textRoundTrips() {
        #expect(AlertThreshold.text(72000, metric: .price) == "72000")
        #expect(AlertThreshold.text(dec("185.5"), metric: .price) == "185.5")
        #expect(AlertThreshold.text(dec("-0.035"), metric: .profitRate) == "-3.5")
        #expect(AlertThreshold.text(nil, metric: .price) == "")
        #expect(AlertThreshold.parse(AlertThreshold.text(dec("1234567.25"), metric: .price), metric: .price) == dec("1234567.25"))
    }

    @Test func units() {
        #expect(AlertThreshold.unit(metric: .price, currency: .krw) == "원")
        #expect(AlertThreshold.unit(metric: .price, currency: .usd) == "$")
        #expect(AlertThreshold.unit(metric: .changeRate, currency: .usd) == "%")
    }

    @Test func conditionText() {
        #expect(PriceAlert(metric: .price, direction: .atOrAbove, threshold: 72000).conditionText(currency: .krw) == "가격 72,000원 이상")
        #expect(PriceAlert(metric: .price, direction: .atOrBelow, threshold: dec("185.7")).conditionText(currency: .usd) == "가격 $185.70 이하")
        #expect(PriceAlert(metric: .changeRate, direction: .atOrAbove, threshold: dec("0.05")).conditionText(currency: .krw) == "전일 대비 +5.00% 이상")
        #expect(PriceAlert(metric: .changeRate, direction: .beyond, threshold: dec("-0.05")).conditionText(currency: .krw) == "전일 대비 ±5.00% 이상 변동")
        #expect(PriceAlert(metric: .profitRate, direction: .atOrBelow, threshold: dec("-0.1")).conditionText(currency: .krw) == "수익률 -10.00% 이하")
        #expect(PriceAlert(metric: .price, threshold: nil).conditionText(currency: .krw) == "가격 기준값 미설정")
    }
}

@Suite("Price alert storage")
struct PriceAlertStorageTests {
    @Test func itemsSavedBeforeAlertsLoadWithNone() throws {
        let json = #"[{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"stock": {"_0": {"symbol": "005930"}}}, "connectionID": "1F0E5D61-2F3B-4C64-9D4B-0B1B7B3C7E10"}]"#
        let items = try JSONDecoder().decode([MenuItemConfig].self, from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.alerts == [])
    }

    @Test func roundTripsExactThresholds() throws {
        var item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")))
        item.alerts = [
            PriceAlert(metric: .price, direction: .atOrBelow, threshold: dec("185.1"), repeatMode: .oncePerDay),
            PriceAlert(metric: .changeRate, direction: .beyond, threshold: dec("0.033"), isEnabled: false),
            PriceAlert(metric: .price, threshold: nil),
        ]
        let decoded = try JSONDecoder().decode(MenuItemConfig.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        #expect(decoded.alerts.first?.threshold == dec("185.1"))
    }

    @Test func fillsDefaultsForMissingAlertKeys() throws {
        let json = #"{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "metric": "changeRate", "threshold": "0.05"}"#
        let alert = try JSONDecoder().decode(PriceAlert.self, from: Data(json.utf8))
        #expect(alert.direction == .atOrAbove)
        #expect(alert.repeatMode == .everyCross)
        #expect(alert.isEnabled)
        #expect(alert.threshold == dec("0.05"))
    }

    @Test func skipsAlertsFromANewerBuild() throws {
        let json = #"""
        {"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"stock": {"_0": {"symbol": "005930"}}},
         "alerts": [
           {"id": "2A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "metric": "volume", "threshold": "1000"},
           {"id": "3A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "metric": "price", "threshold": "72000"}
         ]}
        """#
        let item = try JSONDecoder().decode(MenuItemConfig.self, from: Data(json.utf8))
        #expect(item.alerts.map(\.metric) == [.price])
    }
}

@MainActor
@Suite("Price alert store updates")
struct ItemStoreAlertTests {
    private func makeStore() -> ItemStore {
        ItemStore(defaults: UserDefaults(suiteName: "ItemStoreAlertTests.\(UUID().uuidString)")!)
    }

    @Test func addsUpdatesAndRemovesAlerts() {
        let store = makeStore()
        let item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930")))
        store.upsert(item)
        let alert = PriceAlert(metric: .price, threshold: 72000)

        store.addAlert(alert, to: item.id)
        store.updateAlert(alert.id, of: item.id) { $0.direction = .atOrBelow }
        #expect(store.alerts(of: item.id).map(\.direction) == [.atOrBelow])

        store.removeAlert(alert.id, of: item.id)
        #expect(store.alerts(of: item.id).isEmpty)
    }

    @Test func persistsAlerts() {
        let defaults = UserDefaults(suiteName: "ItemStoreAlertTests.\(UUID().uuidString)")!
        let item = MenuItemConfig(kind: .asset(AssetItemConfig()))
        let alert = PriceAlert(metric: .profitRate, direction: .atOrBelow, threshold: Decimal(string: "-0.1")!)
        let store = ItemStore(defaults: defaults)
        store.upsert(item)
        store.addAlert(alert, to: item.id)

        #expect(ItemStore(defaults: defaults).alerts(of: item.id) == [alert])
    }

    @Test func removesOnlyPriceAndHoldingProfitAlerts() {
        let store = makeStore()
        var item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930")))
        let rate = PriceAlert(metric: .changeRate, threshold: Decimal(string: "0.05")!)
        let holdingRate = PriceAlert(metric: .holdingRate, threshold: Decimal(string: "0.1")!)
        item.alerts = [PriceAlert(metric: .price, threshold: 72000), rate,
                       PriceAlert(metric: .holdingProfit, threshold: 1_000_000), holdingRate]
        store.upsert(item)

        store.removePriceAlerts(of: item.id)
        #expect(store.alerts(of: item.id) == [rate, holdingRate])
    }
}

@Suite("Holding alerts")
struct HoldingAlertTests {
    private func held(_ symbol: String) throws -> HoldingItem {
        let overview = try TossAPIClient.makeDecoder().decode(HoldingsOverview.self, from: Data(Fixtures.holdingsJSON.utf8))
        return try #require(overview.holding(of: symbol))
    }

    @Test func profitThresholdsMayBeZeroOrNegative() {
        #expect(AlertThreshold.parse("-500,000", metric: .holdingProfit) == -500_000)
        #expect(AlertThreshold.parse("0", metric: .holdingProfit) == 0)
        #expect(AlertThreshold.parse("+1,000,000원", metric: .holdingProfit) == 1_000_000)
        #expect(AlertThreshold.parse("-12.5", metric: .holdingRate) == dec("-0.125"))
        // A price still has to be positive.
        #expect(AlertThreshold.parse("0", metric: .price) == nil)
    }

    @Test func profitRearmMarginIsHalfAPercentOfThePurchaseAmount() {
        let alert = PriceAlert(metric: .holdingProfit, direction: .atOrAbove, threshold: 1_000_000)
        #expect(alert.rearmMargin(scale: 5_000_000) == 25_000)
        #expect(!alert.hasCleared(975_000, scale: 5_000_000))
        #expect(alert.hasCleared(974_999, scale: 5_000_000))
        // Without a purchase amount it falls back to the threshold, like a price.
        #expect(alert.rearmMargin() == 5_000)
    }

    @Test func breakEvenAlertStillHasAMargin() {
        let alert = PriceAlert(metric: .holdingProfit, direction: .atOrBelow, threshold: 0)
        #expect(alert.rearmMargin(scale: 5_000_000) == 25_000)
        #expect(!alert.hasCleared(20_000, scale: 5_000_000))
        #expect(alert.hasCleared(25_001, scale: 5_000_000))
    }

    @Test func crossingBelowBreakEvenFiresOnce() {
        let alert = PriceAlert(metric: .holdingProfit, direction: .atOrBelow, threshold: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var state: AlertState?
        var fired: [Bool] = []
        for value: Decimal in [100_000, -1_000, -5_000, 10_000, 30_000, -2_000] {
            let step = AlertEvaluator.step(alert, signature: "s", value: value, scale: 5_000_000,
                                           previous: state, now: Date(), calendar: calendar)
            state = step.state
            fired.append(step.fires)
        }
        // 10,000 is inside the 25,000 margin, so only 30,000 re-arms it.
        #expect(fired == [false, true, false, false, false, true])
    }

    @Test func thresholdCurrency() {
        var alert = PriceAlert(metric: .holdingProfit)
        #expect(alert.thresholdCurrency(trading: .usd) == .usd)
        alert.currency = .krw
        #expect(alert.thresholdCurrency(trading: .usd) == .krw)
        #expect(alert.thresholdCurrency(trading: .krw) == .krw)
        // Prices stay in the trading currency whatever the field says.
        alert.metric = .price
        #expect(alert.thresholdCurrency(trading: .usd) == .usd)
    }

    @Test func conditionText() {
        let profit = PriceAlert(metric: .holdingProfit, direction: .atOrBelow, threshold: -500_000)
        #expect(profit.conditionText(currency: .krw) == "보유 수익금 -500,000원 이하")
        let dollars = PriceAlert(metric: .holdingProfit, direction: .beyond, threshold: 200)
        #expect(dollars.conditionText(currency: .usd) == "보유 수익금 ±$200.00 이상 변동")
        let rate = PriceAlert(metric: .holdingRate, direction: .atOrAbove, threshold: dec("0.2"))
        #expect(rate.conditionText(currency: .usd) == "보유 수익률 +20.00% 이상")
    }

    @Test func readsTheHoldingInTheAlertsCurrency() throws {
        let config = StockItemConfig(symbol: "AAPL", afterCost: true)
        var alert = PriceAlert(metric: .holdingProfit, currency: .krw)
        let krw = AlertMonitor.holding(try held("AAPL"), config: config, alert: alert, usdKrw: 1375)
        #expect(krw.currency == .krw)
        // 123.52 × 1,375, on the item's after-cost basis
        #expect(krw.profit == dec("169840"))
        #expect(krw.purchaseAmount == 1_375_000)

        alert.currency = .native
        let usd = AlertMonitor.holding(try held("AAPL"), config: config, alert: alert, usdKrw: 1375)
        #expect(usd.currency == .usd)
        #expect(usd.profit == dec("123.52"))
    }

    @Test func rateAlertsKeepTheItemsCurrency() throws {
        let config = StockItemConfig(symbol: "AAPL", displayCurrency: .krw)
        let alert = PriceAlert(metric: .holdingRate, currency: .native)
        let holding = AlertMonitor.holding(try held("AAPL"), config: config, alert: alert, usdKrw: 1375)
        #expect(holding.currency == .krw)
        #expect(holding.rate == dec("0.232"))
    }

    @Test func holdingAlertsFetchHoldingsAndTheRate() {
        var item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")))
        #expect(!item.needsHoldings)
        #expect(![item].needsUsdKrwForStocks)

        item.alerts = [PriceAlert(metric: .holdingRate, isEnabled: false)]
        #expect(!item.needsHoldings)

        item.alerts = [PriceAlert(metric: .holdingProfit, currency: .krw)]
        #expect(item.needsHoldings)
        #expect([item].needsUsdKrwForStocks)
        #expect([item].holdingStockConfigs.map(\.symbol) == ["AAPL"])
    }

    @Test func savesTheCurrencyAndDefaultsToTheTradingOne() throws {
        let alert = PriceAlert(metric: .holdingProfit, direction: .atOrBelow, threshold: -300, currency: .krw)
        let decoded = try JSONDecoder().decode(PriceAlert.self, from: JSONEncoder().encode(alert))
        #expect(decoded == alert)

        let old = #"{"id":"6B0F1C9E-8E0B-4E39-9A57-1D1B0B7C1F00","metric":"holdingRate","threshold":"0.1"}"#
        #expect(try JSONDecoder().decode(PriceAlert.self, from: Data(old.utf8)).currency == .native)
    }
}
