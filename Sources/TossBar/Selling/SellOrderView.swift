import SwiftUI

/// The sell dialog opened from a holding alert's notification: the order type, the share
/// of the sellable quantity to sell, and the order button, which asks once more before
/// anything is sent.
struct SellOrderView: View {
    @StateObject private var model: SellOrderModel
    @ObservedObject private var data: MarketDataHub
    let close: () -> Void

    /// A preset share, or nil while a typed percentage is used.
    @State private var preset: Int? = 100
    @State private var customText = ""

    init(env: AppEnvironment, action: SellAction, close: @escaping () -> Void) {
        _model = StateObject(wrappedValue: SellOrderModel(env: env, action: action))
        data = env.data
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).font(.title3.weight(.semibold))
                Text(model.accountText).font(.callout).foregroundStyle(.secondary)
            }

            if model.isStale {
                notice("알림을 받은 지 \(Int(Date().timeIntervalSince(model.action.alertedAt) / 60))분이 지났습니다. 아래 현재 시세를 확인하세요.")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    row("현재가", model.quote.map { Fmt.priceWithUnit($0.lastPrice.value, $0.currency) })
                    row("보유", model.holding.map {
                        "\($0.quantityText)주 · \(Fmt.signedAmount($0.profit, $0.currency)) (\($0.rateText))"
                    })
                    row("매도 가능", model.sellable.map { "\(Fmt.quantity($0))주" })
                }
                .padding(4)
            }

            Form {
                Picker("주문 유형", selection: $model.orderType) {
                    Text("시장가").tag(OrderType.market)
                    Text("현재가 (지정가)").tag(OrderType.limit)
                }
                .pickerStyle(.segmented)

                Picker("수량", selection: $preset) {
                    ForEach(SellPlan.presets, id: \.self) { value in
                        Text(value == 100 ? "전량" : "\(value)%").tag(Int?.some(value))
                    }
                    Text("직접 입력").tag(Int?.none)
                }
                .pickerStyle(.segmented)

                if preset == nil {
                    HStack(spacing: 4) {
                        TextField("비율", text: $customText, prompt: Text("1–100"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.columns)

            orderSummary

            outcome

            HStack {
                if model.isLoading || model.isSubmitting {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("닫기", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("매도 주문…") { Task { await model.submit() } }
                    .disabled(!model.canSubmit || (preset == nil && SellPlan.percent(customText) == nil))
            }
        }
        .editorPane()
        .task { await model.load() }
        .onChange(of: preset) { _, value in
            if let value { model.percent = value } else if let typed = SellPlan.percent(customText) { model.percent = typed }
        }
        .onChange(of: customText) { _, text in
            if preset == nil, let typed = SellPlan.percent(text) { model.percent = typed }
        }
    }

    @ViewBuilder
    private var orderSummary: some View {
        if let quantity = model.quantity {
            VStack(alignment: .leading, spacing: 4) {
                if quantity > 0 {
                    let amount = model.amount.map { Fmt.priceWithUnit($0, model.currency) } ?? "-"
                    let label = model.orderType == .market ? "예상 금액" : "금액"
                    Text("\(Fmt.quantity(quantity))주 매도 · \(label) \(amount)")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                } else {
                    Text("매도할 수 있는 수량이 없습니다.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                CaptionText(caption)
            }
        }
    }

    private var caption: String {
        var text = model.orderType == .market
            ? "시장가는 체결 가격이 현재가와 다를 수 있습니다."
            : "주문 직전에 현재가를 다시 읽어 그 가격으로 지정가 주문을 냅니다."
        if model.currency == .usd {
            text += model.orderType == .market
                ? " 미국 주식 시장가는 소수점 수량도 팔 수 있지만, 정규장 마감 1시간 전까지만 됩니다."
                : " 미국 주식 지정가는 1주 단위로만 주문할 수 있어 소수점 이하는 남습니다."
        }
        return text
    }

    @ViewBuilder
    private var outcome: some View {
        if let error = model.loadError {
            message(error, color: .red)
        }
        switch model.outcome {
        case .placed(let orderID, let summary)?:
            VStack(alignment: .leading, spacing: 4) {
                Label("주문을 접수했습니다: \(summary)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                CaptionText("주문번호 \(orderID). 체결 여부와 취소는 토스증권 앱에서 확인하세요.")
                    .textSelection(.enabled)
            }
            .font(.callout)
        case .failed(let error)?:
            message("주문하지 못했습니다: \(error)", color: .red)
        case nil:
            EmptyView()
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "–").monospacedDigit()
        }
        .font(.callout)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text).font(.callout).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }
}
