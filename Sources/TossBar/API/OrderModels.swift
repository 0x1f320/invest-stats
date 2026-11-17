import Foundation

// MARK: - Orders

enum OrderSide: String, Encodable, Hashable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

enum OrderType: String, Encodable, Hashable, Sendable, CaseIterable, Identifiable {
    /// 시장가: fills at the market; sent without a price.
    case market = "MARKET"
    /// 지정가: fills at the price or better.
    case limit = "LIMIT"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .market: return "시장가"
        case .limit: return "지정가"
        }
    }
}

/// A quantity-based order, `OrderCreateQuantityBased` in the API. Numbers are sent as
/// decimal strings, as the API expects. The account goes in the `X-Tossinvest-Account`
/// header, not the body.
struct OrderRequest: Encodable, Hashable, Sendable {
    /// Idempotency key: the API accepts one order per key for 10 minutes. Up to 36
    /// characters of letters, digits, `-` and `_`.
    var clientOrderId: String?
    var symbol: String
    var side: OrderSide
    var orderType: OrderType
    /// Whole shares, except a US market sell, which may be fractional (6 decimals).
    var quantity: Decimal
    /// Required for a limit order, and must be left out for a market order.
    var price: Decimal?
    /// Must be true for orders of 100 million won or more.
    var confirmHighValueOrder = false

    private enum CodingKeys: String, CodingKey {
        case clientOrderId, symbol, side, orderType, quantity, price, confirmHighValueOrder
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(clientOrderId, forKey: .clientOrderId)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(side, forKey: .side)
        try c.encode(orderType, forKey: .orderType)
        try c.encode(OrderNumber.string(quantity), forKey: .quantity)
        if orderType == .limit {
            try c.encodeIfPresent(price.map(OrderNumber.string), forKey: .price)
        }
        if confirmHighValueOrder {
            try c.encode(true, forKey: .confirmHighValueOrder)
        }
    }
}

/// What the API returns for an accepted order. Its status comes from the order detail.
struct OrderReceipt: Decodable, Hashable, Sendable {
    let orderId: String
    let clientOrderId: String?
}

struct SellableQuantityResponse: Decodable, Hashable, Sendable {
    /// Whole shares for KR stocks; US stocks may hold a fraction.
    let sellableQuantity: Dec
}

/// Numbers as the order API takes them.
enum OrderNumber {
    /// A plain decimal string, such as `10`, `0.5` or `185.5`: no grouping and no exponent.
    static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    /// A limit price the API accepts: whole won for KR, and for US two decimals from $1 up
    /// and four below it, cut off rather than rounded as the API does.
    /// KR prices must also match the tick size; a traded price already does.
    static func limitPrice(_ price: Decimal, currency: Currency) -> Decimal {
        switch currency {
        case .usd: return truncate(price, scale: price >= 1 ? 2 : 4)
        default: return truncate(price, scale: 0)
        }
    }

    /// The largest quantity the API accepts that is no more than `quantity`: whole shares,
    /// or six decimals when fractions are allowed (a US market sell).
    static func quantity(_ quantity: Decimal, allowsFraction: Bool) -> Decimal {
        truncate(quantity, scale: allowsFraction ? 6 : 0)
    }

    static func truncate(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, value < 0 ? .up : .down)
        return result
    }
}
