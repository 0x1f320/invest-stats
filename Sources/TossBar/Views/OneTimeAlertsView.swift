import SwiftUI

extension AppEnvironment {
    /// The currency an item's price thresholds are in: the stock's trading currency, or KRW
    /// for asset items.
    func tradingCurrency(of item: MenuItemConfig) -> Currency {
        guard case .stock(let config) = item.kind else { return .krw }
        return StockLookup.isUS(config.symbol, universe: universe, service: data.service(for: item)) ? .usd : .krw
    }
}

/// The window opened from an item's context menu: the item's pending one-time alerts, and a
/// form that adds another. One-time alerts are kept apart from the alerts in the item's
/// settings; each fires once and is then deleted.
struct OneTimeAlertsView: View {
    let env: AppEnvironment
    let itemID: UUID
    let close: () -> Void
    @ObservedObject private var store: ItemStore
    @ObservedObject private var oneTime: OneTimeAlertStore
    @ObservedObject private var data: MarketDataHub
    @ObservedObject private var notifier: AlertNotifier
    @ObservedObject private var monitor: AlertMonitor

    @State private var draft: PriceAlert

    init(env: AppEnvironment, itemID: UUID, close: @escaping () -> Void) {
        self.env = env
        self.itemID = itemID
        self.close = close
        store = env.store
        oneTime = env.oneTimeAlerts
        data = env.data
        notifier = env.alertNotifier
        monitor = env.alertMonitor
        let kind = env.store.item(itemID)?.kind
        let metric = kind.flatMap { AlertMetric.available(for: $0).first } ?? .price
        _draft = State(initialValue: PriceAlert(metric: metric))
    }

    private var item: MenuItemConfig? { store.item(itemID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item {
                content(item)
            } else {
                Text("항목을 찾을 수 없습니다.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { notifier.refreshAuthorization() }
    }

    @ViewBuilder
    private func content(_ item: MenuItemConfig) -> some View {
        let currency = env.tradingCurrency(of: item)
        let pending = oneTime.alerts(of: itemID)

        PermissionNotice(notifier: notifier, hasAlerts: true)

        CaptionText("조건을 넘으면 macOS 알림으로 한 번 알리고 삭제됩니다. 이 항목 설정의 알림 탭과는 따로 관리됩니다.")

        if !pending.isEmpty {
            Text("대기 중인 일회성 알림").font(.headline)
            ForEach(pending) { alert in
                PendingAlertRow(
                    condition: alert.conditionText(currency: alert.thresholdCurrency(trading: currency)),
                    status: monitor.statusText(of: alert, item: item),
                    sells: alert.sellsFromNotification,
                    remove: { oneTime.remove(alert.id) }
                )
            }
        }

        Text("새 일회성 알림").font(.headline)
        AlertRow(
            alert: draft,
            metrics: AlertMetric.available(for: item.kind),
            tradingCurrency: currency,
            status: draftStatus(item),
            update: { change in change(&draft) }
        )
        // A fresh draft after each add starts with an empty text field.
        .id(draft.id)

        if isAlreadyMet(item) {
            Label("지금 이미 조건을 만족하고 있습니다. 값이 기준에서 벗어났다가 다시 넘을 때 알립니다.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack {
            Spacer()
            Button("닫기", action: close)
                .keyboardShortcut(.cancelAction)
            Button("추가", action: add)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.threshold == nil)
        }
    }

    /// The draft's current value, so the user sees where the threshold stands.
    private func draftStatus(_ item: MenuItemConfig) -> String {
        guard draft.threshold != nil else { return "기준값을 입력하세요." }
        guard let observation = monitor.observation(for: draft, of: item) else {
            return draft.metric.isHolding ? "보유 내역을 기다리는 중 · 보유하지 않은 동안에는 알리지 않음" : "시세를 기다리는 중"
        }
        return "현재 " + AlertThreshold.format(observation.value, metric: draft.metric, currency: observation.currency)
    }

    /// Whether the draft's condition already holds. Like any alert, it then fires only after
    /// the value leaves the condition and crosses back in.
    private func isAlreadyMet(_ item: MenuItemConfig) -> Bool {
        guard draft.threshold != nil, let observation = monitor.observation(for: draft, of: item) else { return false }
        return draft.isMet(by: observation.value)
    }

    private func add() {
        guard draft.threshold != nil else { return }
        oneTime.add(draft, to: itemID)
        // Asked when the first alert is set up, not at launch.
        notifier.requestAuthorizationIfNeeded()
        // A holding alert may need holdings or the rate that nothing fetched yet.
        if draft.metric.isHolding { data.refreshSoon() }
        // Keep the metric and direction for the next one; the threshold starts empty.
        draft = PriceAlert(metric: draft.metric, direction: draft.direction, currency: draft.currency)
    }
}

/// A pending one-time alert: its condition, where it stands, and a delete button.
private struct PendingAlertRow: View {
    let condition: String
    let status: String
    let sells: Bool
    let remove: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(condition).fontWeight(.medium)
                    CaptionText(sells ? "\(status) · 알림에 매도 버튼" : status)
                }
                Spacer()
                Button(action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("이 일회성 알림 삭제")
            }
            .padding(4)
        }
    }
}
