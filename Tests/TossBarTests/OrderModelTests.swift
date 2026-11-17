import Foundation
import Testing
@testable import TossBar

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Order requests")
struct OrderModelTests {
    private func json(_ order: OrderRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(order), as: UTF8.self)
    }

    @Test func marketSellLeavesOutThePrice() throws {
        let order = OrderRequest(clientOrderId: "abc-1", symbol: "005930", side: .sell, orderType: .market,
                                 quantity: 10, price: 72000)
        #expect(try json(order) == #"{"clientOrderId":"abc-1","orderType":"MARKET","quantity":"10","side":"SELL","symbol":"005930"}"#)
    }

    @Test func limitSellSendsNumbersAsStrings() throws {
        let order = OrderRequest(symbol: "AAPL", side: .sell, orderType: .limit, quantity: 3, price: dec("185.5"))
        #expect(try json(order) == #"{"orderType":"LIMIT","price":"185.5","quantity":"3","side":"SELL","symbol":"AAPL"}"#)
    }

    @Test func highValueConfirmationOnlyWhenSet() throws {
        let order = OrderRequest(symbol: "005930", side: .sell, orderType: .market, quantity: 2000,
                                 confirmHighValueOrder: true)
        #expect(try json(order).contains(#""confirmHighValueOrder":true"#))
    }

    @Test func fractionalQuantity() throws {
        let order = OrderRequest(symbol: "AAPL", side: .sell, orderType: .market, quantity: dec("0.123456"))
        #expect(try json(order).contains(#""quantity":"0.123456""#))
    }

    @Test func limitPricesAreCutToWhatTheAPITakes() {
        #expect(OrderNumber.limitPrice(dec("185.709"), currency: .usd) == dec("185.70"))
        #expect(OrderNumber.limitPrice(dec("0.123456"), currency: .usd) == dec("0.1234"))
        #expect(OrderNumber.limitPrice(dec("72000.0"), currency: .krw) == 72000)
    }

    @Test func quantitiesAreCutDown() {
        #expect(OrderNumber.quantity(dec("7.9"), allowsFraction: false) == 7)
        #expect(OrderNumber.quantity(dec("5.1234567"), allowsFraction: true) == dec("5.123456"))
        #expect(OrderNumber.quantity(dec("0.4"), allowsFraction: false) == 0)
    }

    @Test func decodesResponses() throws {
        let decoder = TossAPIClient.makeDecoder()
        let receipt = try decoder.decode(ApiEnvelope<OrderReceipt>.self, from: Data(
            #"{"result":{"orderId":"0d5QIHjm","clientOrderId":null}}"#.utf8)).result
        #expect(receipt == OrderReceipt(orderId: "0d5QIHjm", clientOrderId: nil))

        let sellable = try decoder.decode(ApiEnvelope<SellableQuantityResponse>.self, from: Data(
            #"{"result":{"sellableQuantity":"5.5"}}"#.utf8)).result
        #expect(sellable.sellableQuantity.value == dec("5.5"))
    }

    @Test func orderErrorsReadInKorean() {
        let error = TossAPIError.http(status: 422, code: "order-hours-closed", message: "closed")
        #expect(error.errorDescription == "지금은 주문을 받지 않는 시간입니다.")
        // Codes without a message of our own show the API's.
        let tick = TossAPIError.http(status: 400, code: "invalid-request", message: "주문 가격이 호가 단위에 맞지 않습니다.")
        #expect(tick.errorDescription == "주문 가격이 호가 단위에 맞지 않습니다.")
    }
}
