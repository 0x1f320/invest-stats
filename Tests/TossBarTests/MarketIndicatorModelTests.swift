import Foundation
import Testing
@testable import TossBar

@Suite("Market indicator models")
struct MarketIndicatorModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try TossAPIClient.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decodesIndicatorPrices() throws {
        let json = #"""
        {"result": [
          {"symbol": "KOSPI", "timestamp": "2026-06-11T15:30:00+09:00", "lastPrice": "2812.45"},
          {"symbol": "KR_BOND_10Y", "timestamp": null, "lastPrice": "3.25"}
        ]}
        """#
        let quotes = try decode(ApiEnvelope<[MarketIndicatorQuote]>.self, json).result
        #expect(quotes.map(\.symbol) == ["KOSPI", "KR_BOND_10Y"])
        #expect(quotes[0].lastPrice.value == Decimal(string: "2812.45")!)
        #expect(quotes[0].timestamp == ISO8601DateFormatter().date(from: "2026-06-11T06:30:00Z"))
        #expect(quotes[1].timestamp == nil)
        #expect(quotes[1].lastPrice.value == Decimal(string: "3.25")!)
    }

    @Test func decodesIndicatorCandlesWithoutCurrency() throws {
        let json = #"""
        {"result": {"candles": [
          {"timestamp": "2026-06-11T09:00:00+09:00", "openPrice": "2798.32", "highPrice": "2820.15",
           "lowPrice": "2790.1", "closePrice": "2812.45", "volume": "542000000"},
          {"timestamp": "2026-06-10T09:00:00+09:00", "openPrice": "3.3", "highPrice": "3.31",
           "lowPrice": "3.2", "closePrice": "3.25"}
        ], "nextBefore": null}}
        """#
        let page = try decode(ApiEnvelope<MarketIndicatorCandlePage>.self, json).result
        #expect(page.candles.count == 2)
        #expect(page.candles[0].closePrice.value == Decimal(string: "2812.45")!)
        #expect(page.candles[0].volume?.value == 542_000_000)
        #expect(page.candles[1].volume == nil)
        #expect(page.nextBefore == nil)
    }

    @Test func decodesTheWholeExchangeRate() throws {
        let json = #"""
        {"result": {"baseCurrency": "USD", "quoteCurrency": "KRW", "rate": "1372.3", "midRate": "1375",
                    "basisPoint": "-19.6", "rateChangeType": "DOWN",
                    "validFrom": "2026-03-25T09:30:00+09:00", "validUntil": "2026-03-25T09:31:00+09:00"}}
        """#
        let rate = try decode(ApiEnvelope<ExchangeRate>.self, json).result
        #expect(rate.midRate.value == 1375)
        #expect(rate.rate.value == Decimal(string: "1372.3")!)
        #expect(rate.basisPoint?.value == Decimal(string: "-19.6")!)
        #expect(rate.rateChangeType == "DOWN")
        #expect(rate.validUntil!.timeIntervalSince(rate.validFrom!) == 60)
    }

    @Test func exchangeRateStillDecodesWithoutTheNewFields() throws {
        let rate = try decode(ExchangeRate.self, #"{"rate": "1380.5", "midRate": "1375"}"#)
        #expect(rate.basisPoint == nil)
        #expect(rate.validUntil == nil)
    }

    @Test func catalogHasTheAPISymbolsAndTheExchangeRate() {
        let symbols = MarketIndicator.catalog.map(\.symbol)
        #expect(Set(symbols).count == symbols.count)
        #expect(MarketIndicator.catalog.filter(\.isMarketIndicator).count == 8)
        #expect(MarketIndicator.find("KOSPI")?.category == .index)
        #expect(MarketIndicator.find("KR_BOND_30Y")?.category == .bond)
        #expect(MarketIndicator.find("USD_KRW") == .usdKrw)
        #expect(MarketIndicator.find("005930") == nil)
        // Minute candles are for indices only; bonds would get 400 invalid-request.
        #expect(MarketIndicator.catalog.filter(\.hasMinuteCandles).map(\.symbol) == ["KOSPI", "KOSDAQ"])
        #expect(!MarketIndicator.usdKrw.hasCandles)
    }

    @Test func unsupportedSymbolHasAKoreanMessage() {
        let error = TossAPIError.http(status: 400, code: "unsupported-symbol", message: nil)
        #expect(error.errorDescription == "지원하지 않는 지표입니다.")
    }
}
