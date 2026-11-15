import Foundation
import Testing
import UserNotifications
@testable import TossBar

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Alert messages")
struct AlertMessageTests {
    @Test func domesticPriceAlert() {
        let alert = PriceAlert(metric: .price, direction: .atOrAbove, threshold: 72000)
        let message = AlertMessage.stock(name: "삼성전자", alert: alert, currency: .krw,
                                         price: 72500, changeRate: dec("0.021"), convertedPrice: nil)
        #expect(message.title == "삼성전자 · 가격 72,000원 이상")
        #expect(message.body == "현재가 72,500원 · 전일 대비 +2.10%")
    }

    @Test func usPriceShownInKRWAddsTheConvertedPrice() {
        let alert = PriceAlert(metric: .price, direction: .atOrBelow, threshold: 180)
        let message = AlertMessage.stock(name: "Apple", alert: alert, currency: .usd,
                                         price: dec("179.5"), changeRate: dec("-0.0123"), convertedPrice: dec("246812.5"))
        #expect(message.title == "Apple · 가격 $180.00 이하")
        #expect(message.body == "현재가 $179.50 (246,813원) · 전일 대비 -1.23%")
    }

    @Test func changeAlertLeadsWithTheChange() {
        let alert = PriceAlert(metric: .changeRate, direction: .beyond, threshold: dec("0.05"))
        let message = AlertMessage.stock(name: "SK하이닉스", alert: alert, currency: .krw,
                                         price: 190000, changeRate: dec("-0.0612"), convertedPrice: nil)
        #expect(message.title == "SK하이닉스 · 전일 대비 ±5.00% 이상 변동")
        #expect(message.body == "전일 대비 -6.12% · 현재가 190,000원")
    }

    @Test func assetAlert() {
        let alert = PriceAlert(metric: .profitRate, direction: .atOrBelow, threshold: dec("-0.1"))
        let message = AlertMessage.asset(label: "💰", alert: alert, mode: .total,
                                         rate: dec("-0.1052"), profit: -1_234_000)
        #expect(message.title == "자산 · 💰 · 수익률 -10.00% 이하")
        #expect(message.body == "전체 손익 수익률 -10.52% · -1,234,000₩")
    }

    @Test func assetAlertWithoutLabelOrAmount() {
        let alert = PriceAlert(metric: .profitRate, direction: .atOrAbove, threshold: dec("0.03"))
        let message = AlertMessage.asset(label: nil, alert: alert, mode: .daily, rate: dec("0.031"), profit: nil)
        #expect(message.title == "자산 · 수익률 +3.00% 이상")
        #expect(message.body == "일간 손익 수익률 +3.10%")
    }
}

@MainActor
@Suite("Alert notifier")
struct AlertNotifierTests {
    private func makeBundle(named name: String, bundleID: String?) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlertNotifierTests-\(UUID().uuidString)")
            .appendingPathComponent(name)
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleExecutable": "TossBar"]
        if let bundleID { plist["CFBundleIdentifier"] = bundleID }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
    }

    @Test func onlyAppBundlesWithAnIDCanUseNotificationCenter() throws {
        #expect(AlertNotifier.canUseNotificationCenter(bundle: try makeBundle(named: "Invest Stats.app", bundleID: "me.example.app")))
        #expect(!AlertNotifier.canUseNotificationCenter(bundle: try makeBundle(named: "Invest Stats.app", bundleID: nil)))
        #expect(!AlertNotifier.canUseNotificationCenter(bundle: try makeBundle(named: "debug", bundleID: "me.example.app")))
    }

    @Test func bareExecutableIsUnavailableAndPostingIsSafe() throws {
        // Like `.build/debug/TossBar`: no app bundle, so Notification Center is never touched.
        let notifier = AlertNotifier(bundle: try makeBundle(named: "debug", bundleID: nil))
        #expect(notifier.authorization == .unavailable)
        notifier.requestAuthorizationIfNeeded()
        notifier.refreshAuthorization()
        notifier.post(title: "삼성전자 · 가격 72,000원 이상", body: "현재가 72,500원", thread: "test")
        #expect(notifier.authorization == .unavailable)
    }

    @Test func mapsAuthorizationStatus() {
        #expect(AlertNotifier.authorization(for: .notDetermined) == .notDetermined)
        #expect(AlertNotifier.authorization(for: .denied) == .denied)
        #expect(AlertNotifier.authorization(for: .authorized) == .allowed)
        #expect(AlertNotifier.authorization(for: .provisional) == .allowed)
    }
}
