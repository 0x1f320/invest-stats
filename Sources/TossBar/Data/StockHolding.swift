import Foundation

extension HoldingsOverview {
    /// The account's holding of a stock, or nil when it doesn't hold it.
    func holding(of symbol: String) -> HoldingItem? {
        items.first { $0.symbol == symbol }
    }
}

/// Whether a stock item's account holds the item's stock.
enum StockHoldingState {
    /// The account's holdings haven't loaded yet.
    case unknown
    case notHeld
    case held(StockHolding)

    var holding: StockHolding? {
        if case .held(let holding) = self { return holding }
        return nil
    }
}

/// A holding as a stock item shows it: in the item's display currency and profit basis.
///
/// Every figure is the API's. A US holding shown in KRW is converted at the USD/KRW base rate,
/// as the item's price is; until the rate is known it stays in dollars. Rates are never
/// converted.
struct StockHolding {
    let item: HoldingItem
    /// Profit after fees and taxes rather than raw profit.
    let afterCost: Bool
    let conversion: PriceConversion

    init(item: HoldingItem, config: StockItemConfig, usdKrw: Decimal?) {
        self.item = item
        afterCost = config.afterCost
        conversion = PriceConversion.make(native: item.currency, display: config.displayCurrency, usdKrw: usdKrw)
    }

    /// The currency the amounts are in.
    var currency: Currency { conversion.currency }

    var quantity: Decimal { item.quantity.value }
    var averagePrice: Decimal { conversion.apply(item.averagePurchasePrice.value) }
    var purchaseAmount: Decimal { conversion.apply(item.marketValue.purchaseAmount.value) }

    var marketValue: Decimal {
        conversion.apply(afterCost ? item.marketValue.amountAfterCost.value : item.marketValue.amount.value)
    }

    var profit: Decimal { conversion.apply(item.profit(afterCost: afterCost).amount) }
    var rate: Decimal { item.profit(afterCost: afterCost).rate }

    var dailyProfit: Decimal { conversion.apply(item.dailyProfitLoss.amount.value) }
    var dailyRate: Decimal { item.dailyProfitLoss.rate.value }

    // MARK: Menu bar text

    /// `+700,000₩` in KRW, as an asset item shows profit, or `+$232.00`.
    var profitText: String {
        currency == .usd ? Fmt.signedAmount(profit, .usd) : Fmt.krwProfit(profit)
    }

    var rateText: String { Fmt.percent(ratio: rate) }

    var quantityText: String { Fmt.quantity(quantity) }

    /// `5,700,000₩` or `$1,232.00`.
    var marketValueText: String {
        currency == .usd ? Fmt.price(marketValue, .usd) : Fmt.number(marketValue) + "₩"
    }

    /// Written like the item's price: `50,000`, `$125.00`, or `171,875원` once converted, so a
    /// converted price can't be mistaken for a domestic one.
    var averagePriceText: String {
        conversion.isConverted ? Fmt.priceWithUnit(averagePrice, .krw) : Fmt.price(averagePrice, currency)
    }
}
