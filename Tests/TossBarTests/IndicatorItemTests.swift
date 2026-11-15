import Foundation
import Testing
@testable import TossBar

@Suite("Indicator items")
struct IndicatorItemTests {
    private let kospi = MarketIndicator.find("KOSPI")!
    private let bond = MarketIndicator.find("KR_BOND_10Y")!

    private func candle(_ day: String, close: String) -> MarketIndicatorCandle {
        let date = ISO8601DateFormatter().date(from: "\(day)T00:00:00Z")!.addingTimeInterval(-9 * 3600)
        let price = Dec(Decimal(string: close)!)
        return MarketIndicatorCandle(timestamp: date, openPrice: price, highPrice: price, lowPrice: price, closePrice: price, volume: nil)
    }

    private func kst(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    // MARK: Saved configs

    @Test func loadsItemsSavedBeforeIndicators() throws {
        let json = #"""
        [{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"stock": {"_0": {"symbol": "AAPL", "showName": false}}}},
         {"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E11", "kind": {"asset": {"_0": {"label": "💰"}}},
          "connectionID": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E12"}]
        """#
        let items = try JSONDecoder().decode([MenuItemConfig].self, from: Data(json.utf8))
        #expect(items.count == 2)
        #expect(items[0].kind == .stock(StockItemConfig(symbol: "AAPL", showName: false)))
        #expect(items[1].kind == .asset(AssetItemConfig(label: "💰")))
        #expect(items.indicatorSymbols.isEmpty)
        #expect(!items.needsUsdKrwForIndicators)
    }

    @MainActor
    @Test func storeLoadsSavedItemsNextToANewIndicator() throws {
        let defaults = UserDefaults(suiteName: "IndicatorItemTests.\(UUID().uuidString)")!
        let json = #"""
        [{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"stock": {"_0": {"symbol": "005930"}}}},
         {"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E11", "kind": {"indicator": {"_0": {"symbol": "KOSPI"}}}}]
        """#
        defaults.set(Data(json.utf8), forKey: ItemStore.defaultsKey)
        let items = ItemStore(defaults: defaults).items
        #expect(items.map(\.typeTitle) == ["주가", "지표"])
    }

    @Test func fillsDefaultsForAMinimalIndicatorConfig() throws {
        let json = #"{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"indicator": {"_0": {"symbol": "KR_BOND_3Y"}}}}"#
        let item = try JSONDecoder().decode(MenuItemConfig.self, from: Data(json.utf8))
        guard case .indicator(let config) = item.kind else {
            Issue.record("expected an indicator item")
            return
        }
        #expect(config == IndicatorItemConfig(symbol: "KR_BOND_3Y"))
        #expect(config.showName && config.showChange)
        #expect(config.displayName == nil && config.format == nil)
        #expect(item.connectionID == nil)
    }

    @Test func roundTripsAnIndicatorItem() throws {
        let item = MenuItemConfig(
            kind: .indicator(IndicatorItemConfig(symbol: "USD_KRW", displayName: "달러", showName: false, format: "%n %p")),
            connectionID: UUID()
        )
        let decoded = try JSONDecoder().decode(MenuItemConfig.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    @Test func keepsAnUnknownSymbol() throws {
        let json = #"{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"indicator": {"_0": {"symbol": "NIKKEI"}}}}"#
        let item = try JSONDecoder().decode(MenuItemConfig.self, from: Data(json.utf8))
        guard case .indicator(let config) = item.kind else {
            Issue.record("expected an indicator item")
            return
        }
        #expect(config.indicator == nil)
        #expect([item].indicatorSymbols.isEmpty)
    }

    // MARK: Polling

    @Test func batchesIndicatorSymbolsWithoutTheExchangeRate() {
        let items = [
            MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: "KOSPI"))),
            MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930"))),
            MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: "KR_BOND_10Y"))),
            MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: "KOSPI", showName: false))),
            MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: "USD_KRW"))),
        ]
        #expect(items.indicatorSymbols == ["KOSPI", "KR_BOND_10Y"])
        #expect(items.stockSymbols == ["005930"])
        #expect(items.needsUsdKrwForIndicators)
        #expect(!items.needsUsdKrwForStocks)
        #expect(!Array(items.prefix(4)).needsUsdKrwForIndicators)
    }

    @MainActor
    @Test func updatesOnlyTheIndicatorItem() {
        let store = ItemStore(defaults: UserDefaults(suiteName: "IndicatorItemTests.\(UUID().uuidString)")!)
        let connection = UUID()
        let indicator = MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: "KOSPI")), connectionID: connection)
        let stock = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")))
        store.upsert(indicator)
        store.upsert(stock)

        store.updateIndicator(indicator.id) { $0.symbol = "KOSDAQ" }
        store.updateIndicator(stock.id) { $0.symbol = "KOSPI" }

        #expect(store.indicatorConfig(indicator.id)?.symbol == "KOSDAQ")
        #expect(store.item(indicator.id)?.connectionID == connection)
        #expect(store.item(stock.id) == stock)
        #expect(store.indicatorConfig(stock.id) == nil)
    }

    @MainActor
    @Test func indicesAndBondsFollowKRXAndTheExchangeRateNeverIdles() {
        let client = TossAPIClient(connectionID: UUID(), credentials: nil, location: .local)
        let service = MarketDataService(connectionID: UUID(), client: client) { [] }
        func regions(_ symbol: String) -> Set<MarketRegion>? {
            service.regions(for: MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: symbol))))
        }
        #expect(regions("KOSDAQ") == [.kr])
        #expect(regions("KR_BOND_3Y") == [.kr])
        #expect(regions("USD_KRW") == nil)
        #expect(regions("NIKKEI") == [])

        // With every market closed, an exchange rate item keeps its connection polling.
        let next = MarketSession(kind: .regular, start: Date().addingTimeInterval(3600), end: Date().addingTimeInterval(7200))
        let closed: (MarketRegion) -> MarketStatus? = { _ in .closed(next: next) }
        #expect(PollingPolicy.isIdle(itemRegions: [regions("KOSPI"), regions("KR_BOND_3Y")], status: closed))
        #expect(!PollingPolicy.isIdle(itemRegions: [regions("KOSPI"), regions("USD_KRW")], status: closed))
    }

    // MARK: Format

    @Test func defaultFormatFollowsTheCategory() {
        #expect(IndicatorItemConfig(symbol: "KOSPI").defaultFormat == "%n %p %r")
        #expect(IndicatorItemConfig(symbol: "KR_BOND_2Y").defaultFormat == "%n %p %a")
        #expect(IndicatorItemConfig(symbol: "USD_KRW").defaultFormat == "%n %p")
        #expect(IndicatorItemConfig(symbol: "KOSDAQ", showName: false, showChange: false).defaultFormat == "%p")
        var config = IndicatorItemConfig(symbol: "KOSPI", format: " ")
        #expect(config.titleFormat == TitleFormat("%n %p %r"))
        config.format = "%c %p (%a)"
        #expect(config.titleFormat == TitleFormat("%c %p (%a)"))
    }

    @Test func tokenLettersMatchTheStockItem() {
        #expect(Set(IndicatorTitleToken.allCases.map(\.letter)).count == IndicatorTitleToken.allCases.count)
        #expect(IndicatorTitleToken.allCases.map(\.letter) == StockTitleToken.allCases.map(\.letter))
    }

    // MARK: Readings

    @Test func formatsAnIndex() {
        let reading = IndicatorReading(indicator: kospi, value: Decimal(string: "2812.45")!, previousClose: Decimal(string: "2798.1")!)
        #expect(reading.formattedValue == "2,812.45")
        #expect(reading.formattedChange == "+14.35")
        #expect(reading.formattedChangeRate == "+0.51%")
        #expect(reading.trend == .up)
    }

    @Test func formatsABondYieldInPercentagePoints() {
        let reading = IndicatorReading(indicator: bond, value: Decimal(string: "3.215")!, previousClose: Decimal(string: "3.25")!)
        #expect(reading.formattedValue == "3.215%")
        #expect(reading.formattedChange == "-0.035%p")
        #expect(reading.trend == .down)
        #expect(IndicatorReading(indicator: bond, value: 3, previousClose: 3).formattedChange == "0.00%p")
        #expect(bond.format(Decimal(string: "3.25")!) == "3.25%")
    }

    @Test func waitsForThePreviousClose() {
        let reading = IndicatorReading(indicator: kospi, value: 2800, previousClose: nil)
        #expect(reading.hasChange)
        #expect(reading.formattedChange == nil)
        #expect(reading.formattedChangeRate == nil)
        #expect(reading.trend == nil)
    }

    @Test func exchangeRateShowsTheBaseRateAndTheReportedDirection() throws {
        let json = #"{"rate": "1380.5", "midRate": "1375", "basisPoint": "40", "rateChangeType": "DOWN"}"#
        let rate = try TossAPIClient.makeDecoder().decode(ExchangeRate.self, from: Data(json.utf8))
        let reading = IndicatorReading(exchangeRate: rate)
        #expect(reading.indicator == .usdKrw)
        #expect(reading.formattedValue == "1,375.00")
        #expect(!reading.hasChange)
        #expect(reading.formattedChange == nil)
        #expect(reading.trend == .down)
        #expect(MarketIndicator.usdKrw.displaySymbol == "USD/KRW")
    }

    @Test func previousCloseIsFromTheSessionBeforeTheQuote() {
        let candles = [candle("2026-06-11", close: "2812.45"), candle("2026-06-10", close: "2798.1")]
        // During today's session: yesterday's close.
        #expect(IndicatorReading.previousClose(candles, asOf: kst("2026-06-11T10:00:00+09:00")) == Decimal(string: "2798.1")!)
        // Before today's daily candle shows up: still yesterday's close, not the day before.
        #expect(IndicatorReading.previousClose(Array(candles.dropFirst()) + [candle("2026-06-09", close: "2785")],
                                               asOf: kst("2026-06-11T09:00:30+09:00")) == Decimal(string: "2798.1")!)
        // Without a timestamp: the second newest candle.
        #expect(IndicatorReading.previousClose(candles, asOf: nil) == Decimal(string: "2798.1")!)
        #expect(IndicatorReading.previousClose([], asOf: nil) == nil)
    }

    @Test func readingFromAQuoteUsesTheDailyCandles() {
        let quote = MarketIndicatorQuote(symbol: "KOSPI", timestamp: kst("2026-06-11T15:30:00+09:00"), lastPrice: Dec(Decimal(string: "2812.45")!))
        let reading = IndicatorReading(indicator: kospi, quote: quote,
                                       dailyCandles: [candle("2026-06-11", close: "2812.45"), candle("2026-06-10", close: "2798.1")])
        #expect(reading.previousClose == Decimal(string: "2798.1")!)
        #expect(reading.formattedChangeRate == "+0.51%")
    }
}
