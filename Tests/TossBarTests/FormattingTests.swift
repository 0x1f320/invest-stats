import AppKit
import Foundation
import Testing
@testable import TossBar

@Suite("Formatting")
struct FormattingTests {
    @Test func prices() {
        #expect(Fmt.price(72000, .krw) == "72,000")
        #expect(Fmt.price(Decimal(string: "185.7")!, .usd) == "$185.70")
        #expect(Fmt.priceWithUnit(1_234_567, .krw) == "1,234,567원")
        #expect(Fmt.priceWithUnit(Decimal(string: "0.5")!, .usd) == "$0.50")
    }

    @Test func signedAmounts() {
        #expect(Fmt.signedAmount(700_000, .krw) == "+700,000원")
        #expect(Fmt.signedAmount(Decimal(string: "-12.3")!, .usd) == "-$12.30")
        #expect(Fmt.signedAmount(0, .krw) == "0원")
    }

    @Test func percents() {
        #expect(Fmt.percent(ratio: Decimal(string: "0.1179")!) == "+11.79%")
        #expect(Fmt.percent(ratio: Decimal(string: "-0.0041")!) == "-0.41%")
        #expect(Fmt.percent(ratio: 0) == "0.00%")
        #expect(Fmt.percent(ratio: Decimal(string: "0.05")!, signed: false) == "5.00%")
    }

    @Test func roundsHalfUp() {
        #expect(Fmt.number(Decimal(string: "2.5")!) == "3")
        #expect(Fmt.number(Decimal(string: "0.125")!, fraction: 2) == "0.13")
    }

    @Test func compactKoreanUnits() {
        #expect(Fmt.compact(12_345) == "1.2만")
        #expect(Fmt.compact(123_456_789) == "1.23억")
        #expect(Fmt.compact(999) == "999")
    }

    @Test func quantityKeepsFractionalShares() {
        #expect(Fmt.quantity(Decimal(string: "1.5")!) == "1.5")
        #expect(Fmt.quantity(10) == "10")
    }
}

@Suite("Trend")
struct TrendTests {
    @Test func direction() {
        #expect(Trend(1).arrow == "▲")
        #expect(Trend(-1).arrow == "▼")
        #expect(Trend(0).arrow == "–")
    }

    @Test func menuBarColorKeepsZeroPlain() {
        #expect(Trend(0).menuBarColor == .menuBarText)
        #expect(Trend(1).menuBarColor != .menuBarText)
        #expect(Trend(-1).menuBarColor != .menuBarText)
    }

    /// Plain menu bar text must stay a semantic color, so the menu bar can dim it on
    /// displays whose menu bar isn't active.
    @Test func menuBarTextIsSemantic() {
        #expect(NSColor.menuBarText.type == .catalog)
        #expect(NSColor.menuBarDimmedText.type == .catalog)
    }

    @Test func popoverColorSoftensInDarkMode() {
        func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> NSColor {
            var result = color
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                result = NSColor(cgColor: color.cgColor)!.usingColorSpace(.sRGB)!
            }
            return result
        }
        for trend in [Trend.up, .down] {
            let light = resolved(trend.nsColor, .aqua)
            let dark = resolved(trend.nsColor, .darkAqua)
            #expect(light == resolved(trend.menuBarColor, .aqua))
            #expect(dark.saturationComponent < 0.5)
            #expect(dark.brightnessComponent == 1)
        }
    }
}

@Suite("Dimmed menu bar title")
@MainActor
struct DimmedTitleTests {
    /// Plain text dims to another semantic color: a semantic color given an alpha resolves
    /// to a fixed one and would no longer dim on an inactive display's menu bar.
    @Test func plainTextStaysSemantic() {
        let title = NSAttributedString(string: "삼성전자", attributes: [.foregroundColor: NSColor.menuBarText])
        let color = TitleRenderer.dimmed(title).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .menuBarDimmedText)
    }

    @Test func trendColorsHalveTheirAlpha() {
        let title = NSMutableAttributedString(string: "A ", attributes: [.foregroundColor: NSColor.menuBarText])
        title.append(NSAttributedString(string: "+1%", attributes: [.foregroundColor: NSColor.systemRed]))
        let dimmed = TitleRenderer.dimmed(title)
        let color = dimmed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(color?.alphaComponent == 0.5)
        #expect(dimmed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .menuBarDimmedText)
    }
}
