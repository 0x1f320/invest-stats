import Foundation

// MARK: - Catalog

/// A market indicator an item can show: the indices and Korean government bond yields of the
/// market indicator API, plus the USD/KRW base rate (매매기준율) from the exchange rate API.
struct MarketIndicator: Hashable, Identifiable, Sendable {
    enum Category: Hashable, Sendable {
        /// An index, in points.
        case index
        /// A bond yield, in percent: `3.25` is 3.25%.
        case bond
        /// The USD/KRW base rate, in won per dollar.
        case exchangeRate
    }

    /// The API symbol, or `usdKrw`'s own symbol for the exchange rate. Saved in item configs,
    /// so keep the values stable.
    let symbol: String
    /// The name shown in the menu bar and the settings.
    let name: String
    let category: Category

    var id: String { symbol }

    /// Whether `/api/v1/market-indicators` serves it. The exchange rate comes from
    /// `/api/v1/exchange-rate` instead.
    var isMarketIndicator: Bool { category != .exchangeRate }

    /// Minute candles exist for the indices only; bonds have daily candles only, and the
    /// exchange rate has no candles at all.
    var hasMinuteCandles: Bool { category == .index }
    var hasCandles: Bool { category != .exchangeRate }

    /// Not an API symbol: the app's name for the USD/KRW base rate.
    static let usdKrw = MarketIndicator(symbol: "USD_KRW", name: "원/달러", category: .exchangeRate)

    /// The symbol catalog of the market indicator API (all eight symbols it supports), then
    /// the exchange rate. Any other symbol gets 400 `unsupported-symbol`.
    static let catalog: [MarketIndicator] = [
        MarketIndicator(symbol: "KOSPI", name: "코스피", category: .index),
        MarketIndicator(symbol: "KOSDAQ", name: "코스닥", category: .index),
        MarketIndicator(symbol: "KR_BOND_2Y", name: "국고채 2년", category: .bond),
        MarketIndicator(symbol: "KR_BOND_3Y", name: "국고채 3년", category: .bond),
        MarketIndicator(symbol: "KR_BOND_5Y", name: "국고채 5년", category: .bond),
        MarketIndicator(symbol: "KR_BOND_10Y", name: "국고채 10년", category: .bond),
        MarketIndicator(symbol: "KR_BOND_20Y", name: "국고채 20년", category: .bond),
        MarketIndicator(symbol: "KR_BOND_30Y", name: "국고채 30년", category: .bond),
        usdKrw,
    ]

    static func find(_ symbol: String) -> MarketIndicator? {
        catalog.first { $0.symbol == symbol }
    }
}

// MARK: - Responses

/// `GET /api/v1/market-indicators/prices`. There is no currency, previous close or change:
/// the unit follows the catalog (points for indices, percent for bonds).
struct MarketIndicatorQuote: Decodable, Hashable, Sendable {
    let symbol: String
    /// nil when the API has no data for it.
    let timestamp: Date?
    let lastPrice: Dec
}

/// A candle of `GET /api/v1/market-indicators/{symbol}/candles`. Unlike a stock candle it has
/// no currency, and its timestamp is the start of the bar.
struct MarketIndicatorCandle: Decodable, Hashable, Sendable {
    let timestamp: Date
    let openPrice: Dec
    let highPrice: Dec
    let lowPrice: Dec
    let closePrice: Dec
    /// Required by the spec, but optional here so a bond without volume still decodes.
    let volume: Dec?
}

struct MarketIndicatorCandlePage: Decodable, Sendable {
    /// Newest first.
    let candles: [MarketIndicatorCandle]
    /// Passed back verbatim as `before` on the next request, so it stays a string.
    let nextBefore: String?
}
