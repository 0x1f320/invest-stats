import Foundation
import Testing
@testable import TossBar

@Suite("Stock holding")
struct StockHoldingTests {
    private func overview() throws -> HoldingsOverview {
        try TossAPIClient.makeDecoder().decode(HoldingsOverview.self, from: Data(Fixtures.holdingsJSON.utf8))
    }

    private func holding(_ symbol: String, _ config: StockItemConfig, usdKrw: Decimal? = 1375) throws -> StockHolding {
        let item = try #require(try overview().holding(of: symbol))
        return StockHolding(item: item, config: config, usdKrw: usdKrw)
    }

    @Test func findsTheHoldingBySymbol() throws {
        let overview = try overview()
        #expect(overview.holding(of: "AAPL")?.name == "애플")
        #expect(overview.holding(of: "TSLA") == nil)
    }

    @Test func domesticHolding() throws {
        let holding = try holding("005930", StockItemConfig(symbol: "005930"))
        #expect(holding.currency == .krw)
        #expect(holding.profitText == "+700,000₩")
        #expect(holding.rateText == "+14.00%")
        #expect(holding.quantityText == "100")
        #expect(holding.marketValueText == "5,700,000₩")
        #expect(holding.averagePriceText == "50,000")
    }

    @Test func usHoldingInDollars() throws {
        let holding = try holding("AAPL", StockItemConfig(symbol: "AAPL"))
        #expect(holding.currency == .usd)
        #expect(holding.profitText == "+$232.00")
        #expect(holding.marketValueText == "$1,232.00")
        #expect(holding.averagePriceText == "$125.00")
    }

    @Test func usHoldingConvertedAtTheBaseRate() throws {
        let holding = try holding("AAPL", StockItemConfig(symbol: "AAPL", displayCurrency: .krw))
        #expect(holding.currency == .krw)
        // 232 × 1,375
        #expect(holding.profit == 319_000)
        #expect(holding.profitText == "+319,000₩")
        // The rate is the API's, never converted.
        #expect(holding.rateText == "+23.20%")
        // 125 × 1,375, with 원 so it can't pass for a domestic price.
        #expect(holding.averagePriceText == "171,875원")
    }

    @Test func staysInDollarsUntilTheRateArrives() throws {
        let holding = try holding("AAPL", StockItemConfig(symbol: "AAPL", displayCurrency: .krw), usdKrw: nil)
        #expect(holding.currency == .usd)
        #expect(holding.profitText == "+$232.00")
    }

    @Test func afterCostBasis() throws {
        let holding = try holding("AAPL", StockItemConfig(symbol: "AAPL", afterCost: true))
        #expect(holding.profit == Decimal(string: "123.52")!)
        #expect(holding.rateText == "+12.35%")
        #expect(holding.marketValue == 1228)
    }
}
