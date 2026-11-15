import Foundation

extension MarketIndicator {
    /// The symbol as shown to the user: `USD/KRW` for the exchange rate.
    var displaySymbol: String { category == .exchangeRate ? "USD/KRW" : symbol }

    /// Formats one of the indicator's values: points with two decimals for an index, a yield
    /// such as `3.25%` for a bond, and won per dollar with two decimals for the exchange rate.
    func format(_ value: Decimal) -> String {
        switch category {
        case .index, .exchangeRate: return Fmt.number(value, fraction: 2)
        case .bond: return Fmt.number(value, fraction: 2, maxFraction: 3) + "%"
        }
    }

    /// Formats a change of the value. A bond's change is in percentage points.
    func formatChange(_ change: Decimal) -> String {
        switch category {
        case .index, .exchangeRate: return Fmt.number(change, fraction: 2, signed: true)
        case .bond: return Fmt.number(change, fraction: 2, maxFraction: 3, signed: true) + "%p"
        }
    }
}

extension MarketIndicator.Category {
    var title: String {
        switch self {
        case .index: return "지수"
        case .bond: return "국고채 금리"
        case .exchangeRate: return "환율"
        }
    }
}

/// What an indicator item shows: the indicator's latest value from the API and, when the API
/// has one, its previous close.
///
/// The indicator price API returns only the last value, with no change. Like a stock item, the
/// change is the last value against the previous daily candle's close, both from the API. The
/// exchange rate API has no previous value at all, so the exchange rate shows no change, only
/// the direction the API reports.
struct IndicatorReading: Equatable {
    let indicator: MarketIndicator
    let value: Decimal
    let previousClose: Decimal?
    /// The direction the exchange rate API reports (`rateChangeType`). nil for the others.
    let reportedTrend: Trend?

    init(indicator: MarketIndicator, value: Decimal, previousClose: Decimal?) {
        self.indicator = indicator
        self.value = value
        self.previousClose = previousClose
        reportedTrend = nil
    }

    /// The USD/KRW reading: the base rate (매매기준율) and the reported direction.
    init(exchangeRate: ExchangeRate) {
        indicator = .usdKrw
        value = exchangeRate.midRate.value
        previousClose = nil
        switch exchangeRate.rateChangeType {
        case "UP": reportedTrend = .up
        case "DOWN": reportedTrend = .down
        case "EQUAL": reportedTrend = .flat
        default: reportedTrend = nil
        }
    }

    /// From the price API's quote and the latest daily candles, newest first.
    init(indicator: MarketIndicator, quote: MarketIndicatorQuote, dailyCandles: [MarketIndicatorCandle]) {
        self.init(
            indicator: indicator,
            value: quote.lastPrice.value,
            previousClose: Self.previousClose(dailyCandles, asOf: quote.timestamp)
        )
    }

    /// Whether the indicator has a change since the previous close at all.
    var hasChange: Bool { indicator.category != .exchangeRate }

    var change: Decimal? { previousClose.map { value - $0 } }

    /// The change as a ratio of the previous close.
    var changeRate: Decimal? {
        guard let previousClose, previousClose != 0 else { return nil }
        return (value - previousClose) / previousClose
    }

    var trend: Trend? { change.map(Trend.init) ?? reportedTrend }

    var formattedValue: String { indicator.format(value) }
    var formattedChange: String? { change.map(indicator.formatChange) }
    var formattedChangeRate: String? { changeRate.map { Fmt.percent(ratio: $0) } }

    /// The close of the newest daily candle from a session before `date`'s (KST), so that a
    /// value from today's session is compared with yesterday's close even before today's
    /// candle shows up. Without a date, the second newest candle's close.
    static func previousClose(_ candles: [MarketIndicatorCandle], asOf date: Date?) -> Decimal? {
        guard let date else { return candles.dropFirst().first?.closePrice.value }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = calendar.startOfDay(for: date)
        return candles.first { calendar.startOfDay(for: $0.timestamp) < day }?.closePrice.value
    }
}
