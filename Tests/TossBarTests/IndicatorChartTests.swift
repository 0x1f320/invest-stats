import Foundation
import Testing
@testable import TossBar

@Suite("Indicator charts")
struct IndicatorChartTests {
    private func candle(_ time: String) -> MarketIndicatorCandle {
        let price = Dec(2800)
        return MarketIndicatorCandle(
            timestamp: ISO8601DateFormatter().date(from: time)!,
            openPrice: price, highPrice: price, lowPrice: price, closePrice: price, volume: nil
        )
    }

    @Test func bondsHaveNoIntradayRange() {
        let kospi = MarketIndicator.find("KOSPI")!
        let bond = MarketIndicator.find("KR_BOND_3Y")!
        #expect(IndicatorChart.ranges(for: kospi) == ChartRange.allCases)
        #expect(IndicatorChart.ranges(for: bond) == [.month, .threeMonths, .sixMonths, .year])
        #expect(IndicatorChart.range(.day, for: kospi) == .day)
        #expect(IndicatorChart.range(.day, for: bond) == .month)
        #expect(IndicatorChart.range(.year, for: bond) == .year)
    }

    @Test func keepsTheNewestSessionInKST() {
        // Newest first. 00:30 KST on the 12th is still the 11th in UTC; it must count as the 12th.
        let candles = [
            candle("2026-06-12T09:01:00+09:00"),
            candle("2026-06-12T09:00:00+09:00"),
            candle("2026-06-11T15:30:00+09:00"),
            candle("2026-06-11T09:00:00+09:00"),
        ]
        #expect(IndicatorChart.sessionCandles(candles) == Array(candles.prefix(2)))
        #expect(IndicatorChart.sessionCandles([candle("2026-06-12T00:30:00+09:00"), candle("2026-06-11T23:59:00+09:00")]).count == 1)
        #expect(IndicatorChart.sessionCandles([]).isEmpty)
    }
}
