import SwiftUI

/// The "알림" tab of an item's settings window: the item's alerts, each saved as it is edited.
struct ItemAlertsPane: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject private var store: ItemStore
    @ObservedObject private var data: MarketDataHub
    @ObservedObject private var notifier: AlertNotifier
    @ObservedObject private var monitor: AlertMonitor

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
        self.data = env.data
        self.notifier = env.alertNotifier
        self.monitor = env.alertMonitor
    }

    private var item: MenuItemConfig? { store.item(id) }
    private var alerts: [PriceAlert] { item?.alerts ?? [] }

    /// The stock's trading currency, which price thresholds are in. KRW for asset items.
    /// A holding profit alert on a US stock may compare in KRW instead.
    private var currency: Currency {
        guard case .stock(let config)? = item?.kind else { return .krw }
        let service = item.flatMap(data.service(for:))
        return StockLookup.isUS(config.symbol, universe: env.universe, service: service) ? .usd : .krw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionNotice(notifier: notifier, hasAlerts: !alerts.isEmpty)

            CaptionText(intro)

            if alerts.isEmpty {
                Text("아직 알림이 없습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if let item {
                ForEach(alerts) { alert in
                    AlertRow(
                        alert: alert,
                        metrics: AlertMetric.available(for: item.kind),
                        tradingCurrency: currency,
                        status: status(of: alert, item: item),
                        update: { change in store.updateAlert(alert.id, of: id, change) },
                        remove: { store.removeAlert(alert.id, of: id) }
                    )
                }
            }

            HStack {
                addButton
                Spacer()
            }

            CaptionText("조건을 넘는 순간 한 번 알리고, 값이 기준에서 다시 벗어나야(가격은 기준가의 0.5%, 보유 수익금은 매입금액의 0.5%, 비율은 0.5%p 이상) 다음에 넘을 때 또 알립니다. 알림을 켤 때 이미 조건을 만족하고 있으면 한 번 벗어났다가 다시 넘을 때 알립니다.")
        }
        .editorPane()
        .onAppear { notifier.refreshAuthorization() }
    }

    private var intro: String {
        switch item?.kind {
        case .stock:
            var text = "가격, 전일 대비 등락률, 보유 수익금·수익률이 기준을 넘으면 macOS 알림으로 알려 줍니다. 값은 메뉴바와 같은 토스증권 API 값을 씁니다. 보유 알림은 보유 탭의 계좌와 수익 기준을 따르며, 보유하지 않은 동안에는 알리지 않습니다. 종목을 바꾸면 가격·보유 수익금 알림은 삭제됩니다."
            if currency == .usd {
                text += " 미국 주식의 가격 기준은 달러입니다. 원화로 표시해도 달러 가격으로 비교하므로 환율 변동만으로는 알리지 않습니다. 보유 수익금은 알림마다 달러와 원화(매매기준율 환산) 중 기준 통화를 고를 수 있습니다."
            }
            return text
        case .asset:
            return "이 항목의 수익률(표시 기준과 수익 기준을 따름)이 기준을 넘으면 macOS 알림으로 알려 줍니다. 수익률은 토스증권 API 값을 그대로 씁니다."
        case .indicator, nil:
            return ""
        }
    }

    @ViewBuilder
    private var addButton: some View {
        let metrics = item.map { AlertMetric.available(for: $0.kind) } ?? []
        if metrics.count == 1, let metric = metrics.first {
            Button { add(metric) } label: { Label("\(metric.title) 알림 추가", systemImage: "plus") }
        } else {
            Menu {
                ForEach(metrics) { metric in
                    Button("\(metric.title) 알림") { add(metric) }
                }
            } label: {
                Label("알림 추가", systemImage: "plus")
            }
            .fixedSize()
        }
    }

    private func add(_ metric: AlertMetric) {
        store.addAlert(PriceAlert(metric: metric), to: id)
        // Asked when the first alert is set up, not at launch.
        notifier.requestAuthorizationIfNeeded()
    }

    private func status(of alert: PriceAlert, item: MenuItemConfig) -> String {
        guard alert.threshold != nil else { return "기준값을 입력하면 확인을 시작합니다." }
        let observation = monitor.observation(for: alert, of: item)
        let current = observation.map {
            "현재 " + AlertThreshold.format($0.value, metric: alert.metric, currency: $0.currency)
        }
        let state: String
        if !alert.isEnabled {
            state = "꺼짐"
        } else if observation == nil {
            state = alert.metric.isHolding ? "보유 내역을 기다리는 중 · 보유하지 않은 동안에는 알리지 않음" : "시세를 기다리는 중"
        } else if let saved = monitor.states[alert.id],
                  saved.signature == AlertEvaluator.signature(for: alert, subject: observation!.subject) {
            switch saved.phase {
            case .armed: state = "대기 중"
            case .triggered: state = "조건 충족 중 · 벗어난 뒤 다시 넘으면 알림"
            }
        } else {
            state = "확인 중"
        }
        return [current, state].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One alert: its condition, threshold and repeat mode.
private struct AlertRow: View {
    let alert: PriceAlert
    let metrics: [AlertMetric]
    /// The stock's trading currency; KRW for asset items.
    let tradingCurrency: Currency
    let status: String
    let update: ((inout PriceAlert) -> Void) -> Void
    let remove: () -> Void

    /// Kept as typed; the alert gets the parsed value, or nil when blank.
    @State private var text: String
    @State private var isInvalid = false

    init(alert: PriceAlert, metrics: [AlertMetric], tradingCurrency: Currency, status: String,
         update: @escaping ((inout PriceAlert) -> Void) -> Void, remove: @escaping () -> Void) {
        self.alert = alert
        self.metrics = metrics
        self.tradingCurrency = tradingCurrency
        self.status = status
        self.update = update
        self.remove = remove
        _text = State(initialValue: AlertThreshold.text(alert.threshold, metric: alert.metric))
    }

    /// The currency the threshold is in.
    private var currency: Currency { alert.thresholdCurrency(trading: tradingCurrency) }

    private var prompt: String {
        switch alert.metric {
        case .price: return "목표가"
        case .holdingProfit: return currency == .usd ? "예: 500, -200" : "예: 1000000"
        case .changeRate, .profitRate, .holdingRate: return "예: 5"
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(isOn: Binding(get: { alert.isEnabled }, set: { on in update { $0.isEnabled = on } })) {
                        Text(alert.conditionText(currency: currency)).fontWeight(.medium)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Button(action: remove) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("이 알림 삭제")
                }

                HStack(spacing: 6) {
                    if metrics.count > 1 {
                        Picker("지표", selection: Binding(get: { alert.metric }, set: changeMetric)) {
                            ForEach(metrics) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    TextField("기준값", text: $text, prompt: Text(prompt))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    Text(AlertThreshold.unit(metric: alert.metric, currency: currency))
                        .foregroundStyle(.secondary)
                    Picker("방향", selection: Binding(get: { alert.direction }, set: { d in update { $0.direction = d } })) {
                        ForEach(alert.metric.directions) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if alert.metric == .holdingProfit && tradingCurrency == .usd {
                    Picker("기준 통화", selection: Binding(get: { alert.currency }, set: changeCurrency)) {
                        Text("달러 ($)").tag(PriceDisplayCurrency.native)
                        Text("원화 (₩, 매매기준율 환산)").tag(PriceDisplayCurrency.krw)
                    }
                    .fixedSize()
                    .help("원화로 고르면 토스증권의 달러 수익금을 매매기준율로 환산해 비교하므로, 환율 변동만으로도 알릴 수 있습니다.")
                }

                HStack {
                    Picker("반복", selection: Binding(get: { alert.repeatMode }, set: { r in update { $0.repeatMode = r } })) {
                        ForEach(AlertRepeat.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    .help("넘을 때마다: 벗어났다가 다시 넘을 때마다 · 하루 한 번: 거래소 기준 하루에 한 번까지 · 한 번만: 알린 뒤 자동으로 꺼짐")
                    Spacer()
                }

                if isInvalid {
                    Text(alert.metric.isSigned ? "숫자로 입력하세요 (예: 5, -3.5)." : "0보다 큰 숫자로 입력하세요.")
                        .font(.caption).foregroundStyle(.red)
                } else {
                    CaptionText(status)
                }
            }
            .padding(4)
        }
        .onChange(of: text) { _, text in save(text) }
    }

    private func save(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            isInvalid = false
            update { $0.threshold = nil }
        } else if let value = AlertThreshold.parse(text, metric: alert.metric) {
            isInvalid = false
            update { $0.threshold = value }
        } else {
            // Partway through typing ("-", "1."): keep the last valid threshold.
            isInvalid = text != "-" && !text.hasSuffix(".")
        }
    }

    /// A threshold in one currency means something else in the other, so switching clears it.
    private func changeCurrency(_ currency: PriceDisplayCurrency) {
        guard currency != alert.currency else { return }
        update {
            $0.currency = currency
            $0.threshold = nil
        }
        text = ""
        isInvalid = false
    }

    /// A threshold means something else in another metric, so switching clears it.
    private func changeMetric(_ metric: AlertMetric) {
        guard metric != alert.metric else { return }
        update {
            $0.metric = metric
            $0.threshold = nil
            if !metric.directions.contains($0.direction) { $0.direction = .atOrAbove }
        }
        text = ""
        isInvalid = false
    }
}

/// Explains when macOS won't show alerts, and offers the way to fix it.
private struct PermissionNotice: View {
    @ObservedObject var notifier: AlertNotifier
    let hasAlerts: Bool

    var body: some View {
        switch notifier.authorization {
        case .allowed:
            EmptyView()
        case .notDetermined:
            if hasAlerts {
                notice("알림 표시 권한을 아직 묻지 않았습니다.", button: "권한 요청") {
                    notifier.requestAuthorizationIfNeeded()
                }
            }
        case .denied:
            notice("macOS 설정에서 Invest Stats 의 알림이 꺼져 있어 알림을 표시할 수 없습니다. 시스템 설정 > 알림에서 허용해 주세요.",
                   button: "시스템 설정 열기") {
                notifier.openSystemSettings()
            }
        case .unavailable:
            notice("앱 번들(.app)로 실행하지 않아 macOS 알림을 쓸 수 없습니다. 조건 확인은 계속하며, 알림 내용은 표준 출력에만 기록됩니다.")
        }
    }

    private func notice(_ message: String, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let button {
                    Button(button, action: action)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }
}
