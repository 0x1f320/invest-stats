import Foundation
import Testing
@testable import TossBar

@Suite("Title format")
struct TitleFormatTests {
    private let stock: [StockTitleToken: String] = [
        .name: "삼성전자", .symbol: "005930", .price: "72,000", .changeRate: "+1.23%", .changeAmount: "+900",
    ]
    private let asset: [AssetTitleToken: String] = [
        .label: "💰", .profit: "+1,019,000₩", .rate: "+11.79%", .marketValue: "9,662,000₩", .purchase: "8,643,000₩",
    ]

    private func render(_ format: String) -> String {
        TitleFormat<StockTitleToken>(format).string { stock[$0]! }
    }

    @Test func replacesTokens() {
        #expect(render("%n %p %r") == "삼성전자 72,000 +1.23%")
        #expect(render("[%c] %p (%a, %r)") == "[005930] 72,000 (+900, +1.23%)")
    }

    @Test func percentEscapesAndUnknownLetters() {
        #expect(render("100%%") == "100%")
        #expect(render("%x %p") == "%x 72,000")
        #expect(render("%p 50%") == "72,000 50%")
        #expect(render("%r%)") == "+1.23%%)")
    }

    @Test func plainTextHasNoTokens() {
        let format = TitleFormat<StockTitleToken>("주식")
        #expect(format.segments == [.text("주식")])
        #expect(!format.uses(.name))
    }

    @Test func trimsEmptyValuesAtTheEnds() {
        let format = TitleFormat<AssetTitleToken>("%l %p (%r)")
        #expect(format.string { $0 == .label ? "" : asset[$0]! } == "+1,019,000₩ (+11.79%)")
        #expect(format.string { asset[$0]! } == "💰 +1,019,000₩ (+11.79%)")
    }

    @Test func marksSignedPieces() {
        let pieces = TitleFormat<AssetTitleToken>("%l %p").render {
            TitlePiece(asset[$0]!, isSigned: $0.isSigned)
        }
        #expect(pieces == [TitlePiece("💰"), TitlePiece(" ", isText: true), TitlePiece("+1,019,000₩", isSigned: true)])
    }

    /// The signed runs of the pieces, after widening.
    private func signedText(_ format: String, label: String = "💰") -> [String] {
        TitleFormat<AssetTitleToken>(format)
            .render { TitlePiece($0 == .label ? label : asset[$0]!, isSigned: $0.isSigned) }
            .widenedSigned()
            .filter(\.isSigned)
            .map(\.text)
    }

    @Test func colorsTheDefaultTitleAsAWhole() {
        #expect(signedText("%l %p (%r)").joined() == "+1,019,000₩ (+11.79%)")
        #expect(signedText("수익 %p") == ["+1,019,000₩"])
        #expect(signedText("[%r] 합계").joined() == "[+11.79%]")
        // A value between signed ones keeps its own color.
        #expect(signedText("%p %l %r") == ["+1,019,000₩", " ", " ", "+11.79%"])
        #expect(signedText("%l %v") == [])
    }

    @Test func stockDefaultFollowsToggles() {
        var config = StockItemConfig(symbol: "005930")
        #expect(config.defaultFormat == "%n %p %r")
        config.showName = false
        config.showChange = false
        #expect(config.defaultFormat == "%p")
        config.format = "  "
        #expect(config.titleFormat == TitleFormat("%p"))
        config.format = "%c %p"
        #expect(config.titleFormat == TitleFormat("%c %p"))
    }

    @Test func stockDefaultLeavesTheHoldingOut() {
        let config = StockItemConfig(symbol: "005930", showHolding: true)
        #expect(config.defaultFormat == "%n %p %r")
    }

    @Test func stockNeedsHoldingsOnlyWhenItShowsThem() {
        var config = StockItemConfig(symbol: "005930")
        #expect(!config.needsHoldings)
        config.format = "%n %q주"
        #expect(config.needsHoldings)
        config.format = "%n %p"
        config.showHolding = true
        #expect(config.needsHoldings)
    }

    @Test func assetDefaultIsTheDesignFormat() {
        var config = AssetItemConfig()
        #expect(config.titleFormat.string { asset[$0]! } == "+1,019,000₩ (+11.79%)")
        config.label = "주식"
        #expect(config.defaultFormat == "%l %p (%r)")
    }

    @Test func tokenLettersAreUnique() {
        #expect(Set(StockTitleToken.allCases.map(\.letter)).count == StockTitleToken.allCases.count)
        #expect(Set(AssetTitleToken.allCases.map(\.letter)).count == AssetTitleToken.allCases.count)
    }

    @Test func decodesConfigsSavedBeforeFormats() throws {
        let json = #"""
        [{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"stock": {"_0": {"symbol": "AAPL"}}}},
         {"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E11", "kind": {"asset": {"_0": {"label": "💰"}}}}]
        """#
        let items = try JSONDecoder().decode([MenuItemConfig].self, from: Data(json.utf8))
        guard case .stock(let stock) = items[0].kind, case .asset(let asset) = items[1].kind else {
            Issue.record("expected a stock and an asset item")
            return
        }
        #expect(stock.format == nil)
        #expect(asset.format == nil)
    }

    @Test func roundTripsFormat() throws {
        let item = MenuItemConfig(kind: .asset(AssetItemConfig(label: "💰", format: "%l %r")))
        let decoded = try JSONDecoder().decode(MenuItemConfig.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}
