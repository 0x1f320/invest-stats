import Foundation

/// The value an alert watches. Every one of them is a value the app already shows, as the
/// API reports it; an alert only compares it with the threshold the user typed.
enum AlertMetric: String, Codable, CaseIterable, Identifiable {
    /// A stock's last price, in its trading currency (USD for US stocks, even when the item
    /// shows prices in KRW), so a move in the exchange rate alone never fires it.
    case price
    /// A stock's change against the previous close, as a ratio: the rate the menu bar shows.
    case changeRate
    /// An asset item's profit rate, as a ratio: the API's rate for the item's mode and basis.
    case profitRate
    /// A stock item's profit on its holding in the item's account, on the item's profit
    /// basis: the API's amount, in the currency the alert chooses (`PriceAlert.currency`).
    case holdingProfit
    /// A stock item's profit rate on its holding, as a ratio: the API's rate.
    case holdingRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .price: return "가격"
        case .changeRate: return "전일 대비"
        case .profitRate: return "수익률"
        case .holdingProfit: return "보유 수익금"
        case .holdingRate: return "보유 수익률"
        }
    }

    var isRate: Bool {
        switch self {
        case .price, .holdingProfit: return false
        case .changeRate, .profitRate, .holdingRate: return true
        }
    }

    /// Whether the metric reads the holding of a stock item's account.
    var isHolding: Bool { self == .holdingProfit || self == .holdingRate }

    /// Whether the metric's value can be negative. Only a price can't.
    var isSigned: Bool { self != .price }

    /// The directions that make sense for the metric. A price has no sign to swing across.
    var directions: [AlertDirection] {
        isSigned ? AlertDirection.allCases : [.atOrAbove, .atOrBelow]
    }

    /// The metrics an item of a kind can watch.
    static func available(for kind: ItemKind) -> [AlertMetric] {
        switch kind {
        case .stock: return [.price, .changeRate, .holdingProfit, .holdingRate]
        case .asset: return [.profitRate]
        // Indicator items have no alerts yet.
        case .indicator: return []
        }
    }
}

enum AlertDirection: String, Codable, CaseIterable, Identifiable {
    /// value ≥ threshold
    case atOrAbove
    /// value ≤ threshold
    case atOrBelow
    /// |value| ≥ |threshold|: a move of that size either way. Rates only.
    case beyond

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atOrAbove: return "이상"
        case .atOrBelow: return "이하"
        case .beyond: return "± 이상 변동"
        }
    }
}

/// How often an alert may fire. Every mode fires only when the value crosses into the
/// condition; this limits how many of those crossings notify.
enum AlertRepeat: String, Codable, CaseIterable, Identifiable {
    /// Every time the value crosses in again after leaving the condition.
    case everyCross
    /// At most once per trading day, in the market's time zone.
    case oncePerDay
    /// Once, then the alert turns itself off.
    case once

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyCross: return "넘을 때마다"
        case .oncePerDay: return "하루 한 번"
        case .once: return "한 번만"
        }
    }
}

/// One alert on a menu bar item.
struct PriceAlert: Hashable, Identifiable {
    var id = UUID()
    var metric: AlertMetric
    var direction: AlertDirection = .atOrAbove
    /// A price in the stock's trading currency, or a ratio for rates (0.05 = 5%).
    /// nil until the user enters one; such an alert is never evaluated.
    var threshold: Decimal?
    var repeatMode: AlertRepeat = .everyCross
    var isEnabled = true
    /// The currency a holding profit alert compares in. For a US stock, `.krw` converts the
    /// API's dollar amount at the USD/KRW base rate, as the item does when it shows KRW, so
    /// a move in the exchange rate alone can fire it. Domestic stocks are in KRW either way,
    /// and other metrics ignore it.
    var currency: PriceDisplayCurrency = .native

    /// Whether the alert's notification carries the sell actions (market, or a limit at the
    /// current price): always for a holding alert, since its account holds the stock.
    /// Choosing one only opens the sell dialog; nothing is ordered until the user confirms
    /// there.
    var sellsFromNotification: Bool { metric.isHolding }

    /// Whether the value meets the condition. False while the threshold isn't set.
    func isMet(by value: Decimal) -> Bool {
        guard let threshold else { return false }
        switch direction {
        case .atOrAbove: return value >= threshold
        case .atOrBelow: return value <= threshold
        case .beyond: return abs(value) >= abs(threshold)
        }
    }

    /// How far the value has to move back past the threshold before the alert re-arms, so a
    /// value hovering at the threshold doesn't fire on every refresh.
    /// Prices: 0.5% of the threshold. Rates: 0.5 percentage points. Holding profit: 0.5% of
    /// the purchase amount (`scale`), the same move as 0.5 points of the holding's rate, so
    /// a threshold of 0 (break-even) still has a margin.
    func rearmMargin(scale: Decimal? = nil) -> Decimal {
        guard let threshold else { return 0 }
        let margin: Decimal
        if metric.isRate {
            margin = Self.rateMargin
        } else if metric == .holdingProfit, let scale, scale != 0 {
            margin = abs(scale) * Self.priceMarginRatio
        } else {
            margin = abs(threshold) * Self.priceMarginRatio
        }
        // A small ±N% alert re-arms halfway back to zero instead of never.
        return direction == .beyond ? min(margin, abs(threshold) / 2) : margin
    }

    static let priceMarginRatio = Decimal(string: "0.005")!
    static let rateMargin = Decimal(string: "0.005")!

    /// Whether the value has left the condition by the re-arm margin.
    func hasCleared(_ value: Decimal, scale: Decimal? = nil) -> Bool {
        guard let threshold else { return true }
        let margin = rearmMargin(scale: scale)
        switch direction {
        case .atOrAbove: return value < threshold - margin
        case .atOrBelow: return value > threshold + margin
        case .beyond: return abs(value) < abs(threshold) - margin
        }
    }
}

extension PriceAlert: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, metric, direction, threshold, repeatMode, isEnabled, currency
    }

    /// Fills defaults for keys that older saved alerts don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        metric = try c.decode(AlertMetric.self, forKey: .metric)
        direction = try c.decodeIfPresent(AlertDirection.self, forKey: .direction) ?? .atOrAbove
        threshold = try c.decodeIfPresent(String.self, forKey: .threshold).flatMap(AlertThreshold.decimal)
        repeatMode = try c.decodeIfPresent(AlertRepeat.self, forKey: .repeatMode) ?? .everyCross
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        currency = try c.decodeIfPresent(PriceDisplayCurrency.self, forKey: .currency) ?? .native
        // `offersSell`, saved by earlier builds, is ignored: holding alerts always offer selling.
    }

    /// The threshold is saved as a decimal string, so it reads back exactly.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(metric, forKey: .metric)
        try c.encode(direction, forKey: .direction)
        try c.encodeIfPresent(threshold.map { "\($0)" }, forKey: .threshold)
        try c.encode(repeatMode, forKey: .repeatMode)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(currency, forKey: .currency)
    }
}

/// Decodes an element, or nil when it can't be. A list of alerts uses it so that an alert
/// saved by a newer build, with a metric this build doesn't know, is skipped instead of
/// failing the whole item list.
struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Text

/// Reading and writing thresholds as the user types them.
enum AlertThreshold {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func decimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: posix)
    }

    /// Parses a typed threshold: a price in the trading currency, an amount, or a percentage
    /// for rates. Grouping separators, units and a leading `+` are ignored. Prices must be
    /// positive; a profit may be zero or negative.
    static func parse(_ text: String, metric: AlertMetric) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        for junk in [",", " ", "%", "$", "₩", "원"] {
            cleaned = cleaned.replacingOccurrences(of: junk, with: "")
        }
        if cleaned.hasPrefix("+") { cleaned.removeFirst() }
        // Decimal(string:) accepts a valid prefix ("12abc" → 12); insist on a whole number.
        guard !cleaned.isEmpty,
              cleaned.range(of: #"^-?(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil,
              let value = decimal(cleaned)
        else { return nil }
        if metric.isRate { return value / 100 }
        return metric.isSigned || value > 0 ? value : nil
    }

    /// The threshold as the text field shows it: `72000`, `185.5`, or `5` for 5%.
    static func text(_ threshold: Decimal?, metric: AlertMetric) -> String {
        guard let threshold else { return "" }
        let shown = metric.isRate ? threshold * 100 : threshold
        return Fmt.number(shown, fraction: 0, maxFraction: 4).replacingOccurrences(of: ",", with: "")
    }

    /// The unit next to the text field.
    static func unit(metric: AlertMetric, currency: Currency) -> String {
        if metric.isRate { return "%" }
        return currency == .usd ? "$" : "원"
    }

    /// A value of the metric for display: `72,000원`, `$185.70`, `+5.12%`, `-1,000,000원`.
    static func format(_ value: Decimal, metric: AlertMetric, currency: Currency) -> String {
        if metric.isRate { return Fmt.percent(ratio: value) }
        return metric.isSigned ? Fmt.signedAmount(value, currency) : Fmt.priceWithUnit(value, currency)
    }
}

extension PriceAlert {
    /// The condition in a sentence, such as `가격 72,000원 이상` or `전일 대비 ±5.00% 이상 변동`.
    /// `currency` is the currency the threshold is in (see `thresholdCurrency`); rates
    /// ignore it.
    func conditionText(currency: Currency) -> String {
        guard let threshold else { return "\(metric.title) 기준값 미설정" }
        switch direction {
        case .beyond:
            let size = metric.isRate
                ? Fmt.percent(ratio: abs(threshold), signed: false)
                : Fmt.priceWithUnit(abs(threshold), currency)
            return "\(metric.title) ±\(size) 이상 변동"
        case .atOrAbove, .atOrBelow:
            return "\(metric.title) \(AlertThreshold.format(threshold, metric: metric, currency: currency)) \(direction.title)"
        }
    }
}

extension PriceAlert {
    /// The currency the threshold is in, for a stock trading in `trading`. A holding profit
    /// alert on a US stock follows `currency`; everything else is in the trading currency.
    func thresholdCurrency(trading: Currency) -> Currency {
        metric == .holdingProfit && trading == .usd && currency == .krw ? .krw : trading
    }
}
