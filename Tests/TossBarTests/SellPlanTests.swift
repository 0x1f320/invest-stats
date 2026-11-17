import Foundation
import Testing
@testable import TossBar

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Sell from an alert")
struct SellPlanTests {
    @Test func presetsCutToWholeShares() {
        #expect(SellPlan.quantity(sellable: 10, percent: 100, orderType: .market, currency: .krw) == 10)
        #expect(SellPlan.quantity(sellable: 10, percent: 75, orderType: .market, currency: .krw) == 7)
        #expect(SellPlan.quantity(sellable: 10, percent: 25, orderType: .limit, currency: .krw) == 2)
        #expect(SellPlan.quantity(sellable: 3, percent: 25, orderType: .limit, currency: .krw) == 0)
    }

    @Test func onlyAUSMarketSellKeepsFractions() {
        #expect(SellPlan.quantity(sellable: dec("5.5"), percent: 100, orderType: .market, currency: .usd) == dec("5.5"))
        #expect(SellPlan.quantity(sellable: dec("5.5"), percent: 50, orderType: .market, currency: .usd) == dec("2.75"))
        #expect(SellPlan.quantity(sellable: dec("5.5"), percent: 100, orderType: .limit, currency: .usd) == 5)
        #expect(SellPlan.quantity(sellable: dec("0.3333333"), percent: 100, orderType: .market, currency: .usd) == dec("0.333333"))
    }

    @Test func percentageIsClamped() {
        #expect(SellPlan.quantity(sellable: 10, percent: 150, orderType: .market, currency: .krw) == 10)
        #expect(SellPlan.quantity(sellable: 10, percent: -5, orderType: .market, currency: .krw) == 0)
    }

    @Test func parsesTypedPercentages() {
        #expect(SellPlan.percent("30") == 30)
        #expect(SellPlan.percent(" 30% ") == 30)
        #expect(SellPlan.percent("0") == nil)
        #expect(SellPlan.percent("101") == nil)
        #expect(SellPlan.percent("12.5") == nil)
    }

    @Test func highValueLine() {
        #expect(SellPlan.isHighValue(amount: 100_000_000, currency: .krw, usdKrw: nil))
        #expect(!SellPlan.isHighValue(amount: 99_999_999, currency: .krw, usdKrw: nil))
        #expect(SellPlan.isHighValue(amount: 80_000, currency: .usd, usdKrw: 1375))
        #expect(!SellPlan.isHighValue(amount: 70_000, currency: .usd, usdKrw: 1375))
        #expect(!SellPlan.isHighValue(amount: 1_000_000, currency: .usd, usdKrw: nil))
    }

    @Test func notificationActionsRoundTrip() {
        let item = UUID()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let info: [AnyHashable: Any] = SellAction.userInfo(itemID: item)
        for type in OrderType.allCases {
            let action = SellAction(actionIdentifier: SellAction.actionIdentifier(for: type), userInfo: info, deliveredAt: date)
            #expect(action == SellAction(itemID: item, orderType: type, alertedAt: date))
        }
    }

    @Test func otherResponsesAreNotSellActions() {
        let info: [AnyHashable: Any] = SellAction.userInfo(itemID: UUID())
        #expect(SellAction(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: info, deliveredAt: Date()) == nil)
        #expect(SellAction(actionIdentifier: "sell.market", userInfo: [:], deliveredAt: Date()) == nil)
    }

    @Test func onlyHoldingAlertsOfferSelling() {
        #expect(PriceAlert(metric: .holdingProfit, offersSell: true).sellsFromNotification)
        #expect(PriceAlert(metric: .holdingRate, offersSell: true).sellsFromNotification)
        #expect(!PriceAlert(metric: .holdingRate).sellsFromNotification)
        #expect(!PriceAlert(metric: .price, offersSell: true).sellsFromNotification)
    }

    @Test func sellOptionIsSavedAndOffByDefault() throws {
        let alert = PriceAlert(metric: .holdingRate, threshold: dec("0.2"), offersSell: true)
        #expect(try JSONDecoder().decode(PriceAlert.self, from: JSONEncoder().encode(alert)) == alert)

        let old = #"{"id":"6B0F1C9E-8E0B-4E39-9A57-1D1B0B7C1F00","metric":"holdingRate","threshold":"0.1"}"#
        #expect(try JSONDecoder().decode(PriceAlert.self, from: Data(old.utf8)).offersSell == false)
    }
}
