import Foundation

/// A token a menu bar format can use, such as `%p` for the price.
protocol TitleToken: CaseIterable, Hashable {
    /// The letter after `%`.
    var letter: Character { get }
    /// What the token stands for, shown in the item settings.
    var title: String { get }
    /// A sample value, shown in the token list and in the preview while live data is missing.
    var example: String { get }
}

extension TitleToken {
    init?(letter: Character) {
        guard let token = Self.allCases.first(where: { $0.letter == letter }) else { return nil }
        self = token
    }

    /// The token as written in a format: `%p`.
    var code: String { "%\(letter)" }
}

/// Tokens of a stock item's menu bar format. The holding tokens show the item's holding of
/// the stock (`StockHolding`); they are empty while its account doesn't hold the stock.
enum StockTitleToken: TitleToken {
    case name, symbol, price, changeRate, changeAmount
    case holdingProfit, holdingRate, holdingQuantity, holdingValue, averagePrice

    var letter: Character {
        switch self {
        case .name: return "n"
        case .symbol: return "c"
        case .price: return "p"
        case .changeRate: return "r"
        case .changeAmount: return "a"
        case .holdingProfit: return "g"
        case .holdingRate: return "y"
        case .holdingQuantity: return "q"
        case .holdingValue: return "v"
        case .averagePrice: return "u"
        }
    }

    var title: String {
        switch self {
        case .name: return "이름 (표시 이름 또는 종목명)"
        case .symbol: return "종목 코드"
        case .price: return "현재가"
        case .changeRate: return "전일 대비 등락률"
        case .changeAmount: return "전일 대비 등락액"
        case .holdingProfit: return "보유 손익"
        case .holdingRate: return "보유 수익률"
        case .holdingQuantity: return "보유 수량"
        case .holdingValue: return "보유 평가금액"
        case .averagePrice: return "평균 매입가"
        }
    }

    var example: String {
        switch self {
        case .name: return "삼성전자"
        case .symbol: return "005930"
        case .price: return "72,000"
        case .changeRate: return "+1.23%"
        case .changeAmount: return "+900"
        case .holdingProfit: return "+700,000₩"
        case .holdingRate: return "+14.00%"
        case .holdingQuantity: return "100"
        case .holdingValue: return "5,700,000₩"
        case .averagePrice: return "50,000"
        }
    }

    /// Whether the token shows the holding, which needs the account's holdings.
    var isHolding: Bool {
        switch self {
        case .holdingProfit, .holdingRate, .holdingQuantity, .holdingValue, .averagePrice: return true
        case .name, .symbol, .price, .changeRate, .changeAmount: return false
        }
    }
}

/// Tokens of an asset item's menu bar format.
enum AssetTitleToken: TitleToken {
    case label, profit, rate, marketValue, purchase

    var letter: Character {
        switch self {
        case .label: return "l"
        case .profit: return "p"
        case .rate: return "r"
        case .marketValue: return "v"
        case .purchase: return "b"
        }
    }

    var title: String {
        switch self {
        case .label: return "라벨"
        case .profit: return "손익"
        case .rate: return "수익률"
        case .marketValue: return "평가금액"
        case .purchase: return "매입금액"
        }
    }

    var example: String {
        switch self {
        case .label: return "💰"
        case .profit: return "+1,019,000₩"
        case .rate: return "+11.79%"
        case .marketValue: return "9,662,000₩"
        case .purchase: return "8,643,000₩"
        }
    }

    /// Profit and rate, which an item can color by their sign.
    var isSigned: Bool { self == .profit || self == .rate }

    /// Amounts in KRW, shown as `…₩` while they wait for the USD/KRW rate.
    var isAmount: Bool { self == .profit || self == .marketValue || self == .purchase }
}

/// Tokens of an indicator item's menu bar format. The letters mean what they mean for a
/// stock item, which also has holding tokens.
enum IndicatorTitleToken: TitleToken {
    case name, symbol, value, changeRate, changeAmount

    var letter: Character {
        switch self {
        case .name: return "n"
        case .symbol: return "c"
        case .value: return "p"
        case .changeRate: return "r"
        case .changeAmount: return "a"
        }
    }

    var title: String {
        switch self {
        case .name: return "이름 (표시 이름 또는 지표명)"
        case .symbol: return "지표 코드"
        case .value: return "현재 값 (지수, 금리 또는 환율)"
        case .changeRate: return "전일 대비 등락률 (환율 제외)"
        case .changeAmount: return "전일 대비 등락폭 (금리는 %p, 환율 제외)"
        }
    }

    var example: String {
        switch self {
        case .name: return "코스피"
        case .symbol: return "KOSPI"
        case .value: return "2,812.45"
        case .changeRate: return "+0.51%"
        case .changeAmount: return "+14.35"
        }
    }
}

/// A menu bar format written printf style: `%` and a letter stand for one of the item's
/// values, `%%` is a literal `%`, and everything else is shown as written. A `%` that isn't
/// followed by a known letter is also shown as written, so `%r%)` reads as the rate followed
/// by `%)`.
struct TitleFormat<Token: TitleToken>: Equatable {
    enum Segment: Equatable {
        case text(String)
        case token(Token)
    }

    let segments: [Segment]

    init(_ format: String) {
        var segments: [Segment] = []
        var text = ""
        var iterator = format.makeIterator()
        while let character = iterator.next() {
            guard character == "%" else {
                text.append(character)
                continue
            }
            guard let next = iterator.next() else {
                text.append("%")
                break
            }
            if next == "%" {
                text.append("%")
            } else if let token = Token(letter: next) {
                if !text.isEmpty { segments.append(.text(text)) }
                text = ""
                segments.append(.token(token))
            } else {
                text.append("%")
                text.append(next)
            }
        }
        if !text.isEmpty { segments.append(.text(text)) }
        self.segments = segments
    }

    func uses(_ token: Token) -> Bool {
        segments.contains(.token(token))
    }

    /// The formatted pieces, with each token replaced by `value(token)`. Leading and
    /// trailing whitespace is dropped, so an empty value at either end leaves no gap.
    func render(_ value: (Token) -> TitlePiece) -> [TitlePiece] {
        var pieces = segments.map { segment -> TitlePiece in
            switch segment {
            case .text(let literal): return TitlePiece(literal, isText: true)
            case .token(let token): return value(token)
            }
        }
        while let first = pieces.first, first.text.nilIfBlank == nil { pieces.removeFirst() }
        while let last = pieces.last, last.text.nilIfBlank == nil { pieces.removeLast() }
        if !pieces.isEmpty {
            pieces[0].text = String(pieces[0].text.drop { $0.isWhitespace })
            let lastIndex = pieces.count - 1
            pieces[lastIndex].text = String(pieces[lastIndex].text.reversed().drop { $0.isWhitespace }.reversed())
        }
        return pieces
    }

    /// The formatted text, with each token replaced by `value(token)`.
    func string(_ value: (Token) -> String) -> String {
        render { TitlePiece(value($0)) }.map(\.text).joined()
    }
}

/// One run of a formatted title.
struct TitlePiece: Equatable {
    var text: String
    /// Whether the run is a signed value that an item can color by its trend.
    var isSigned = false
    /// Whether the run is the format's own text rather than a value.
    var isText = false

    init(_ text: String, isSigned: Bool = false, isText: Bool = false) {
        self.text = text
        self.isSigned = isSigned
        self.isText = isText
    }
}

extension Array where Element == TitlePiece {
    /// The pieces with the trend color widened from the signed values to the format's text
    /// between them and the text attached to either end, such as the parentheses of `(%r)`.
    /// The default asset title, `+1,019,000₩ (+11.79%)`, is then colored as a whole. Other
    /// values, such as the label, keep their color.
    func widenedSigned() -> [TitlePiece] {
        guard let first = firstIndex(where: \.isSigned), let last = lastIndex(where: \.isSigned) else { return self }
        var result: [TitlePiece] = []
        func add(_ text: Substring, signed: Bool) {
            if !text.isEmpty { result.append(TitlePiece(String(text), isSigned: signed, isText: true)) }
        }
        for (index, piece) in enumerated() {
            guard piece.isText, index >= first - 1, index <= last + 1 else {
                result.append(piece)
                continue
            }
            if index == first - 1 {
                // Text right before the first value: its last word is attached to it.
                let split = piece.text.lastIndex(where: \.isWhitespace).map { piece.text.index(after: $0) } ?? piece.text.startIndex
                add(piece.text[..<split], signed: false)
                add(piece.text[split...], signed: true)
            } else if index == last + 1 {
                // Text right after the last value: its first word is attached to it.
                let split = piece.text.firstIndex(where: \.isWhitespace) ?? piece.text.endIndex
                add(piece.text[..<split], signed: true)
                add(piece.text[split...], signed: false)
            } else {
                add(piece.text[...], signed: true)
            }
        }
        return result
    }
}

extension StockItemConfig {
    /// The format the toggles describe, used when no custom format is set. The holding is
    /// never part of it; a custom format adds it with the holding tokens.
    var defaultFormat: String {
        [showName ? "%n" : nil, "%p", showChange ? "%r" : nil].compactMap { $0 }.joined(separator: " ")
    }

    /// The format while the account holds the stock, and while its holdings load.
    var titleFormat: TitleFormat<StockTitleToken> {
        TitleFormat(format?.nilIfBlank ?? defaultFormat)
    }

    /// The format while the account doesn't hold the stock, or nil when the item keeps
    /// `titleFormat` and shows its holding tokens empty.
    var notHeldTitleFormat: TitleFormat<StockTitleToken>? {
        notHeldFormat?.nilIfBlank.map { TitleFormat($0) }
    }

    /// The format for a holding state. Only a known `.notHeld` switches to the not-held
    /// format, so the title doesn't flip while the holdings load.
    func titleFormat(for state: StockHoldingState) -> TitleFormat<StockTitleToken> {
        if case .notHeld = state, let notHeld = notHeldTitleFormat { return notHeld }
        return titleFormat
    }

    /// Whether the item shows its holding in the popover or its format, or picks its format
    /// by whether the stock is held, so its account's holdings are fetched.
    var needsHoldings: Bool {
        showHolding || notHeldTitleFormat != nil || titleFormat.segments.contains {
            if case .token(let token) = $0 { return token.isHolding }
            return false
        }
    }
}

extension AssetItemConfig {
    /// The design's format, `{profit}₩ ({rate}%)`, after the label when there is one.
    var defaultFormat: String {
        label.nilIfBlank == nil ? "%p (%r)" : "%l %p (%r)"
    }

    var titleFormat: TitleFormat<AssetTitleToken> {
        TitleFormat(format?.nilIfBlank ?? defaultFormat)
    }
}

extension IndicatorItemConfig {
    /// The format the toggles describe, used when no custom format is set. An index shows its
    /// change rate, a bond yield its change in percentage points, and the exchange rate no
    /// change, since the API reports none.
    var defaultFormat: String {
        let change: String?
        switch indicator?.category {
        case .bond: change = "%a"
        case .exchangeRate: change = nil
        case .index, nil: change = "%r"
        }
        return [showName ? "%n" : nil, "%p", showChange ? change : nil].compactMap { $0 }.joined(separator: " ")
    }

    var titleFormat: TitleFormat<IndicatorTitleToken> {
        TitleFormat(format?.nilIfBlank ?? defaultFormat)
    }
}
