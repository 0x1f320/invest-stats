import AppKit
import Foundation

/// The sell dialog's state: the holding, the sellable quantity and the current price, read
/// fresh from the API, and the order once it is placed.
///
/// Nothing is ordered without the user's confirmation. `submit()` reads the price and the
/// sellable quantity again, shows what will be sent, and orders only if the user confirms.
@MainActor
final class SellOrderModel: ObservableObject {
    enum Outcome: Equatable {
        case placed(orderID: String, summary: String)
        case failed(String)
    }

    let action: SellAction
    private let env: AppEnvironment

    @Published var orderType: OrderType
    /// Percent of the sellable quantity, 1 to 100.
    @Published var percent = 100
    @Published private(set) var sellable: Decimal?
    @Published private(set) var quote: PriceQuote?
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var outcome: Outcome?

    /// The idempotency key of the next order. Kept after a network error, so retrying an
    /// order that may have arrived can't place it twice; renewed once the API answers.
    private var clientOrderID = UUID().uuidString

    init(env: AppEnvironment, action: SellAction) {
        self.env = env
        self.action = action
        orderType = action.orderType
    }

    // MARK: What the dialog shows

    private var item: MenuItemConfig? { env.store.item(action.itemID) }

    var config: StockItemConfig? {
        guard case .stock(let config)? = item?.kind else { return nil }
        return config
    }

    var service: MarketDataService? { item.flatMap(env.data.service(for:)) }

    var accountSeq: Int64? {
        guard let config, let service else { return nil }
        return service.accountSeq(for: config)
    }

    var name: String {
        guard let config else { return "" }
        return config.displayName?.nilIfBlank ?? service?.stockInfo[config.symbol]?.name ?? config.symbol
    }

    var accountText: String {
        guard let seq = accountSeq else { return "계좌 없음" }
        let account = service?.accounts.first { $0.accountSeq == seq }
        return account.map { "계좌 \($0.maskedNumber)" } ?? "계좌 \(seq)"
    }

    var holding: StockHolding? {
        guard let config else { return nil }
        return service?.holdingState(for: config).holding
    }

    var currency: Currency {
        quote?.currency ?? config.flatMap { service?.currency(for: $0.symbol) } ?? .krw
    }

    /// The quantity the order would sell, or nil until the sellable quantity is known.
    var quantity: Decimal? {
        sellable.map { SellPlan.quantity(sellable: $0, percent: percent, orderType: orderType, currency: currency) }
    }

    /// The limit price: the current price, cut to what the API takes.
    var limitPrice: Decimal? {
        quote.map { OrderNumber.limitPrice($0.lastPrice.value, currency: $0.currency) }
    }

    /// The amount at the current price; a market order's is an estimate.
    var amount: Decimal? {
        guard let quantity, let price = orderType == .limit ? limitPrice : quote?.lastPrice.value else { return nil }
        return SellPlan.amount(quantity: quantity, price: price)
    }

    var isStale: Bool { Date().timeIntervalSince(action.alertedAt) > SellPlan.staleAfter }

    var canSubmit: Bool {
        guard outcome == nil || outcome.map(isFailure) == true else { return false }
        return !isLoading && !isSubmitting && (quantity ?? 0) > 0 && quote != nil && accountSeq != nil
    }

    private func isFailure(_ outcome: Outcome) -> Bool {
        if case .failed = outcome { return true }
        return false
    }

    // MARK: Loading

    /// Reads the sellable quantity and the current price.
    func load() async {
        guard let config, let service, let seq = accountSeq else {
            loadError = "이 항목의 연결이나 계좌를 찾을 수 없습니다."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let sellable = service.client.sellableQuantity(symbol: config.symbol, account: seq)
            async let quotes = service.client.prices([config.symbol])
            let (quantity, prices) = try await (sellable, quotes)
            self.sellable = quantity
            guard let quote = prices.first(where: { $0.symbol == config.symbol }) else {
                throw TossAPIError.http(status: 404, code: "stock-not-found", message: nil)
            }
            self.quote = quote
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Ordering

    /// Reads the numbers again, asks for confirmation, and places the order.
    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        await load()
        guard loadError == nil, let config, let service, let seq = accountSeq,
              let quantity, quantity > 0, let quote else {
            if loadError == nil { outcome = .failed("매도할 수 있는 수량이 없습니다.") }
            return
        }
        let price = orderType == .limit ? limitPrice : nil
        let amount = SellPlan.amount(quantity: quantity, price: price ?? quote.lastPrice.value)
        let highValue = SellPlan.isHighValue(amount: amount, currency: quote.currency, usdKrw: service.usdKrwRate)

        guard confirm(quantity: quantity, price: price, amount: amount, highValue: highValue) else { return }

        let order = OrderRequest(
            clientOrderId: clientOrderID,
            symbol: config.symbol,
            side: .sell,
            orderType: orderType,
            quantity: quantity,
            price: price,
            confirmHighValueOrder: highValue
        )
        do {
            let receipt = try await service.client.placeOrder(order, account: seq)
            clientOrderID = UUID().uuidString
            let summary = summary(quantity: quantity, price: price)
            outcome = .placed(orderID: receipt.orderId, summary: summary)
            env.alertNotifier.post(title: "매도 주문 접수 · \(name)", body: summary, thread: action.itemID.uuidString)
            service.refreshSoon()
        } catch let error as TossAPIError {
            // The API answered, so the next attempt is a new order.
            if case .http = error { clientOrderID = UUID().uuidString }
            outcome = .failed(error.localizedDescription)
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    /// `10주 · 시장가` or `3주 · 지정가 $185.50`.
    private func summary(quantity: Decimal, price: Decimal?) -> String {
        let type = price.map { "지정가 \(Fmt.priceWithUnit($0, currency))" } ?? "시장가"
        return "\(Fmt.quantity(quantity))주 · \(type) · \(accountText)"
    }

    /// The last step before an order goes out: what will be sent, and that it can't be
    /// taken back from here.
    private func confirm(quantity: Decimal, price: Decimal?, amount: Decimal, highValue: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(name) \(Fmt.quantity(quantity))주를 \(price == nil ? "시장가" : "지정가")로 매도할까요?"
        var lines = [accountText]
        if let price {
            lines.append("가격 \(Fmt.priceWithUnit(price, currency)) · 금액 \(Fmt.priceWithUnit(amount, currency))")
        } else {
            lines.append("예상 금액 \(Fmt.priceWithUnit(amount, currency)) (현재가 기준, 체결가는 달라질 수 있음)")
        }
        if highValue {
            lines.append("1억 원 이상의 주문입니다.")
        }
        lines.append("확인하면 바로 토스증권에 주문이 전송됩니다. 체결 전 취소는 토스증권 앱에서 할 수 있습니다.")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "매도")
        alert.addButton(withTitle: "취소")
        // Return confirms the default button, so make cancel the safe default.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
