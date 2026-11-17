import Foundation

/// A sell action chosen on a holding alert's notification. It names the item and the order
/// type; the sell dialog reads everything else fresh.
struct SellAction: Hashable, Sendable {
    /// The notification category with the sell actions.
    static let category = "holding-sell"

    let itemID: UUID
    let orderType: OrderType
    /// When the notification was delivered, to warn about a stale alert.
    let alertedAt: Date

    private static let itemKey = "itemID"

    /// The action identifier of an order type's notification button.
    static func actionIdentifier(for type: OrderType) -> String {
        switch type {
        case .market: return "sell.market"
        case .limit: return "sell.limit"
        }
    }

    /// The button title on the notification.
    static func actionTitle(for type: OrderType) -> String {
        switch type {
        case .market: return "시장가 매도…"
        case .limit: return "현재가 매도…"
        }
    }

    /// What a holding alert's notification carries so its actions can find the item.
    static func userInfo(itemID: UUID) -> [String: String] {
        [itemKey: itemID.uuidString]
    }

    /// The action from a notification response, or nil for anything else, such as a click
    /// on the notification itself.
    init?(actionIdentifier: String, userInfo: [AnyHashable: Any], deliveredAt: Date) {
        guard let type = OrderType.allCases.first(where: { Self.actionIdentifier(for: $0) == actionIdentifier }),
              let string = userInfo[Self.itemKey] as? String,
              let itemID = UUID(uuidString: string) else { return nil }
        self.init(itemID: itemID, orderType: type, alertedAt: deliveredAt)
    }

    init(itemID: UUID, orderType: OrderType, alertedAt: Date) {
        self.itemID = itemID
        self.orderType = orderType
        self.alertedAt = alertedAt
    }
}

/// The numbers of a sell order, free of UI and network so they can be tested alone.
enum SellPlan {
    /// The share presets the dialog offers, in percent of the sellable quantity.
    static let presets = [100, 75, 50, 25]

    /// An alert older than this gets a warning in the dialog.
    static let staleAfter: TimeInterval = 10 * 60

    /// Orders of this many won or more need `confirmHighValueOrder`.
    static let highValueKRW: Decimal = 100_000_000

    /// Whether the API takes a fractional quantity: only for a US market sell.
    static func allowsFraction(orderType: OrderType, currency: Currency) -> Bool {
        orderType == .market && currency == .usd
    }

    /// The quantity to sell: `percent` of the sellable quantity, cut down to what the API
    /// takes. 100 sells everything that can be sold.
    static func quantity(sellable: Decimal, percent: Int, orderType: OrderType, currency: Currency) -> Decimal {
        let share = min(max(percent, 0), 100)
        let raw = share == 100 ? sellable : sellable * Decimal(share) / 100
        return OrderNumber.quantity(raw, allowsFraction: allowsFraction(orderType: orderType, currency: currency))
    }

    /// The amount the order would bring at `price`, in the trading currency.
    static func amount(quantity: Decimal, price: Decimal) -> Decimal {
        quantity * price
    }

    /// Whether the order reaches the API's high value line. A US amount is converted at the
    /// base rate; without one it can't be told, and the API rejects it if needed.
    static func isHighValue(amount: Decimal, currency: Currency, usdKrw: Decimal?) -> Bool {
        switch currency {
        case .usd:
            guard let usdKrw else { return false }
            return amount * usdKrw >= highValueKRW
        default:
            return amount >= highValueKRW
        }
    }

    /// Parses a typed percentage, 1 to 100.
    static func percent(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Int(cleaned), (1...100).contains(value) else { return nil }
        return value
    }
}
