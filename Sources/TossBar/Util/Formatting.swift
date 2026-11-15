import AppKit
import SwiftUI

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Number formatting for prices, amounts and rates.
/// Grouping is always `,` and rounding is half-up, regardless of the system locale.
enum Fmt {
    private static func formatter(min: Int, max: Int, signed: Bool) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        f.roundingMode = .halfUp
        if signed { f.positivePrefix = "+" }
        return f
    }

    /// `signed` adds `+` to positive values. Zero never gets a sign.
    static func number(_ value: Decimal, fraction: Int = 0, maxFraction: Int? = nil, signed: Bool = false) -> String {
        let isZero = value == 0
        let f = formatter(min: fraction, max: maxFraction ?? fraction, signed: signed && !isZero)
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// Short price for the menu bar: `72,000` / `$185.70`
    static func price(_ value: Decimal, _ currency: Currency) -> String {
        switch currency {
        case .usd: return "$" + number(value, fraction: 2)
        default: return number(value)
        }
    }

    /// Price with its unit: `72,000원` / `$185.70`
    static func priceWithUnit(_ value: Decimal, _ currency: Currency) -> String {
        switch currency {
        case .usd: return "$" + number(value, fraction: 2)
        default: return number(value) + "원"
        }
    }

    /// Signed amount: `+700,000원` / `-$12.30`
    static func signedAmount(_ value: Decimal, _ currency: Currency) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let magnitude = abs(value)
        switch currency {
        case .usd: return sign + "$" + number(magnitude, fraction: 2)
        default: return sign + number(magnitude) + "원"
        }
    }

    /// KRW profit in the menu bar format: `+1,234,567₩`
    static func krwProfit(_ value: Decimal) -> String {
        number(value, signed: true) + "₩"
    }

    /// A ratio as a percentage: `0.1234` → `+12.34%`
    static func percent(ratio: Decimal, signed: Bool = true) -> String {
        number(ratio * 100, fraction: 2, signed: signed) + "%"
    }

    static func quantity(_ value: Decimal) -> String {
        number(value, fraction: 0, maxFraction: 6)
    }

    /// Large numbers in Korean units: `1.23억`, `45.6만`
    static func compact(_ value: Decimal) -> String {
        let d = value.double
        switch abs(d) {
        case 1_000_000_000_000...: return String(format: "%.2f조", d / 1_000_000_000_000)
        case 100_000_000...: return String(format: "%.2f억", d / 100_000_000)
        case 10_000...: return String(format: "%.1f만", d / 10_000)
        default: return number(value)
        }
    }

    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// Direction of a change, with its arrow and color.
enum Trend {
    case up, down, flat

    init(_ value: Decimal) {
        if value > 0 { self = .up } else if value < 0 { self = .down } else { self = .flat }
    }

    var arrow: String {
        switch self {
        case .up: return "▲"
        case .down: return "▼"
        case .flat: return "–"
        }
    }

    /// Color for popover text and charts.
    var color: Color { Color(nsColor: nsColor) }

    /// Popover color. In dark mode it switches to a soft tint close to white, because the
    /// saturated system colors are hard to read on the dark popover background.
    var nsColor: NSColor {
        guard self != .flat else { return .secondaryLabelColor }
        let system = systemColor
        let soft = softColor
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? soft : system
        }
    }

    /// Color for menu bar text. Zero stays white like the rest of the text.
    var menuBarColor: NSColor {
        self == .flat ? .white : systemColor
    }

    private var tone: Palette.Tone? {
        switch self {
        case .up: return Palette.koreanConvention ? .red : .green
        case .down: return Palette.koreanConvention ? .blue : .red
        case .flat: return nil
        }
    }

    private var systemColor: NSColor {
        switch tone {
        case .red: return .systemRed
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case nil: return .secondaryLabelColor
        }
    }

    private var softColor: NSColor {
        switch tone {
        case .red: return NSColor(srgbRed: 1.00, green: 0.64, blue: 0.64, alpha: 1)
        case .green: return NSColor(srgbRed: 0.58, green: 0.89, blue: 0.66, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.62, green: 0.78, blue: 1.00, alpha: 1)
        case nil: return .secondaryLabelColor
        }
    }
}

/// Global color convention, mirrored from `AppSettings` so plain views and the menu bar
/// renderer can read it.
enum Palette {
    /// true: up is red and down is blue (Korean convention). false: up green, down red.
    nonisolated(unsafe) static var koreanConvention = true

    enum Tone { case red, green, blue }
}
