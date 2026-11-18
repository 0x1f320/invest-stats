import Combine
import Foundation

/// The value an alert compares, read from data the app already loaded.
struct AlertObservation: Equatable {
    /// The API's value: a price in the trading currency, or a ratio.
    let value: Decimal
    /// What the value belongs to, such as `stock:005930`. See `AlertEvaluator.signature`.
    let subject: String
    /// The currency of `value`: the stock's trading currency, the currency a holding profit
    /// alert compares in, or KRW for asset items.
    let currency: Currency
    /// Sets the day boundary of "once per day": the exchange's time zone.
    let timeZone: TimeZone
    /// The holding's purchase amount for a holding profit alert, in `currency`. See
    /// `PriceAlert.rearmMargin(scale:)`.
    var scale: Decimal? = nil
}

/// Watches every item's alerts and the pending one-time alerts. Whenever the data changes,
/// it reads each enabled alert's value, steps it through `AlertEvaluator`, and posts a
/// notification when it fires.
@MainActor
final class AlertMonitor: ObservableObject {
    nonisolated static let statesKey = "alertStates.v1"

    /// Each alert's state, by alert id. Disabled alerts have none, so turning one back on
    /// starts from a fresh baseline instead of firing for a crossing it didn't watch.
    @Published private(set) var states: [UUID: AlertState]

    private let store: ItemStore
    private let oneTimeAlerts: OneTimeAlertStore
    private let data: MarketDataHub
    private let notifier: AlertNotifier
    private let defaults: UserDefaults
    private var cancellable: AnyCancellable?

    init(store: ItemStore, oneTimeAlerts: OneTimeAlertStore, data: MarketDataHub, notifier: AlertNotifier,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.oneTimeAlerts = oneTimeAlerts
        self.data = data
        self.notifier = notifier
        self.defaults = defaults
        states = Self.loadStates(from: defaults)

        // Evaluate after each batch of data or settings changes, like the menu bar redraw.
        cancellable = Publishers.Merge3(data.objectWillChange, store.objectWillChange, oneTimeAlerts.objectWillChange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
    }

    // MARK: Evaluation

    func evaluate(now: Date = Date()) {
        var next: [UUID: AlertState] = [:]
        var finished: [(alert: UUID, item: UUID)] = []
        var firedOneTime: Set<UUID> = []

        for item in store.items {
            for alert in item.alerts where alert.isEnabled && alert.threshold != nil {
                let (state, observation) = step(alert, of: item, now: now)
                next[alert.id] = state
                guard let observation else { continue }
                notify(alert, item: item, observation: observation, oneTime: false)
                if alert.repeatMode == .once { finished.append((alert.id, item.id)) }
            }
        }

        let items = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
        for pending in oneTimeAlerts.alerts {
            // An alert whose item is gone is pruned with the item; skip it meanwhile.
            guard let item = items[pending.itemID] else { continue }
            let (state, observation) = step(pending.alert, of: item, now: now)
            guard let observation else {
                next[pending.id] = state
                continue
            }
            // Fired: notify once and forget it, state included.
            notify(pending.alert, item: item, observation: observation, oneTime: true)
            firedOneTime.insert(pending.id)
        }

        if next != states {
            states = next
            saveStates()
        }
        // "Once" alerts turn themselves off after firing; one-time alerts are deleted.
        for (alertID, itemID) in finished {
            store.updateAlert(alertID, of: itemID) { $0.isEnabled = false }
        }
        oneTimeAlerts.remove(firedOneTime)
    }

    /// Advances one alert by the item's current value. Returns its next state, and the
    /// observation that made it fire, or nil when it doesn't.
    private func step(_ alert: PriceAlert, of item: MenuItemConfig, now: Date) -> (AlertState?, AlertObservation?) {
        let previous = states[alert.id]
        guard let observation = observation(for: alert, of: item) else {
            // No value yet (loading, or the connection is gone): keep waiting.
            return (previous, nil)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = observation.timeZone
        let step = AlertEvaluator.step(
            alert,
            signature: AlertEvaluator.signature(for: alert, subject: observation.subject),
            value: observation.value,
            scale: observation.scale,
            previous: previous,
            now: now,
            calendar: calendar
        )
        return (step.state, step.fires ? observation : nil)
    }

    /// Where an alert stands, for its row in the settings or the one-time alerts window:
    /// the current value and whether it is waiting, met or off.
    func statusText(of alert: PriceAlert, item: MenuItemConfig) -> String {
        guard alert.threshold != nil else { return "기준값을 입력하면 확인을 시작합니다." }
        let observation = observation(for: alert, of: item)
        let current = observation.map {
            "현재 " + AlertThreshold.format($0.value, metric: alert.metric, currency: $0.currency)
        }
        let state: String
        if !alert.isEnabled {
            state = "꺼짐"
        } else if let observation {
            if let saved = states[alert.id],
               saved.signature == AlertEvaluator.signature(for: alert, subject: observation.subject) {
                switch saved.phase {
                case .armed: state = "대기 중"
                case .triggered: state = "조건 충족 중 · 벗어난 뒤 다시 넘으면 알림"
                }
            } else {
                state = "확인 중"
            }
        } else {
            state = alert.metric.isHolding ? "보유 내역을 기다리는 중 · 보유하지 않은 동안에는 알리지 않음" : "시세를 기다리는 중"
        }
        return [current, state].compactMap { $0 }.joined(separator: " · ")
    }

    /// The alert's current value, or nil while it isn't loaded.
    func observation(for alert: PriceAlert, of item: MenuItemConfig) -> AlertObservation? {
        guard let service = data.service(for: item) else { return nil }
        switch (item.kind, alert.metric) {
        case (.stock(let config), .price):
            guard let quote = service.quotes[config.symbol] else { return nil }
            return AlertObservation(value: quote.lastPrice.value, subject: "stock:\(config.symbol)",
                                    currency: quote.currency, timeZone: quote.currency.marketTimeZone)
        case (.stock(let config), .changeRate):
            guard let change = service.change(for: config.symbol) else { return nil }
            let currency = service.currency(for: config.symbol)
            return AlertObservation(value: change.rate, subject: "stock:\(config.symbol)",
                                    currency: currency, timeZone: currency.marketTimeZone)
        case (.asset(let config), .profitRate):
            guard let seq = service.accountSeq(for: config), let overview = service.holdings[seq] else { return nil }
            let rate = AssetSummary(overview: overview, usdKrw: service.usdKrwRate).headline(for: config).rate
            let subject = "asset:\(service.connectionID.uuidString):\(seq):\(config.mode.rawValue):\(config.usesAfterCost)"
            return AlertObservation(value: rate, subject: subject, currency: .krw, timeZone: Currency.krw.marketTimeZone)
        case (.stock(let config), .holdingProfit), (.stock(let config), .holdingRate):
            // Nil until the holdings load, and while the account doesn't hold the stock.
            guard let seq = service.accountSeq(for: config), let overview = service.holdings[seq],
                  let item = overview.holding(of: config.symbol) else { return nil }
            let holding = Self.holding(item, config: config, alert: alert, usdKrw: service.usdKrwRate)
            let subject = "holding:\(service.connectionID.uuidString):\(seq):\(config.symbol):\(config.afterCost)"
            let timeZone = item.currency.marketTimeZone
            if alert.metric == .holdingRate {
                return AlertObservation(value: holding.rate, subject: subject, currency: item.currency, timeZone: timeZone)
            }
            // KRW for a US holding waits for the USD/KRW rate rather than compare dollars.
            let currency = alert.thresholdCurrency(trading: item.currency)
            guard holding.currency == currency else { return nil }
            return AlertObservation(value: holding.profit, subject: "\(subject):\(currency.rawValue)",
                                    currency: currency, timeZone: timeZone, scale: holding.purchaseAmount)
        default:
            // A metric that doesn't apply to the item's kind.
            return nil
        }
    }

    /// The holding as an alert reads it: on the item's account and profit basis, with
    /// amounts in the currency a holding profit alert chooses, or the item's otherwise.
    nonisolated static func holding(_ item: HoldingItem, config: StockItemConfig, alert: PriceAlert, usdKrw: Decimal?) -> StockHolding {
        var basis = config
        if alert.metric == .holdingProfit { basis.displayCurrency = alert.currency }
        return StockHolding(item: item, config: basis, usdKrw: usdKrw)
    }

    // MARK: Notification

    private func notify(_ alert: PriceAlert, item: MenuItemConfig, observation: AlertObservation, oneTime: Bool) {
        guard let service = data.service(for: item) else { return }
        let message: AlertMessage
        switch item.kind {
        case .stock(let config) where alert.metric.isHolding:
            guard let seq = service.accountSeq(for: config),
                  let held = service.holdings[seq]?.holding(of: config.symbol) else { return }
            let holding = Self.holding(held, config: config, alert: alert, usdKrw: service.usdKrwRate)
            let quote = service.quotes[config.symbol]
            message = AlertMessage.holding(
                name: config.displayName?.nilIfBlank ?? service.stockInfo[config.symbol]?.name ?? held.name,
                alert: alert,
                thresholdCurrency: observation.currency,
                holding: holding,
                price: quote.map { ($0.lastPrice.value, $0.currency) }
            )
        case .stock(let config):
            let quote = service.quotes[config.symbol]
            let conversion = service.priceConversion(symbol: config.symbol, display: config.displayCurrency)
            message = AlertMessage.stock(
                name: config.displayName?.nilIfBlank ?? service.stockInfo[config.symbol]?.name ?? config.symbol,
                alert: alert,
                currency: observation.currency,
                price: quote?.lastPrice.value,
                changeRate: service.change(for: config.symbol)?.rate,
                convertedPrice: conversion.isConverted ? quote.map { conversion.apply($0.lastPrice.value) } : nil
            )
        case .asset(let config):
            let summary = service.accountSeq(for: config)
                .flatMap { service.holdings[$0] }
                .map { AssetSummary(overview: $0, usdKrw: service.usdKrwRate) }
            message = AlertMessage.asset(
                label: config.label.nilIfBlank,
                alert: alert,
                mode: config.mode,
                rate: observation.value,
                profit: summary?.headline(for: config).amount
            )
        case .indicator:
            // Indicator items have no alert metrics, so nothing of theirs fires.
            return
        }
        notifier.post(title: message.title, subtitle: oneTime ? AlertMessage.oneTimeSubtitle : nil,
                      body: message.body, thread: item.id.uuidString,
                      sellItem: alert.sellsFromNotification ? item.id : nil)
    }

    // MARK: Storage

    private static func loadStates(from defaults: UserDefaults) -> [UUID: AlertState] {
        guard let data = defaults.data(forKey: statesKey),
              let decoded = try? JSONDecoder().decode([String: AlertState].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, state in
            UUID(uuidString: key).map { ($0, state) }
        })
    }

    private func saveStates() {
        let encoded = Dictionary(uniqueKeysWithValues: states.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Self.statesKey)
        }
    }
}

/// The text of an alert's notification. Every value in it is one the API reported; a US
/// stock shown in KRW adds its price converted at the base rate, as the menu bar shows it.
struct AlertMessage: Equatable {
    let title: String
    let body: String

    /// The subtitle of a one-time alert's notification, which says it won't come again.
    static let oneTimeSubtitle = "일회성 알림 · 알린 뒤 삭제됨"

    /// `삼성전자 · 가격 72,000원 이상` / `현재가 72,500원 · 전일 대비 +2.10%`
    static func stock(
        name: String,
        alert: PriceAlert,
        currency: Currency,
        price: Decimal?,
        changeRate: Decimal?,
        convertedPrice: Decimal?
    ) -> AlertMessage {
        var priceText = price.map { "현재가 \(Fmt.priceWithUnit($0, currency))" }
        if let text = priceText, let convertedPrice {
            priceText = "\(text) (\(Fmt.priceWithUnit(convertedPrice, .krw)))"
        }
        let changeText = changeRate.map { "전일 대비 \(Fmt.percent(ratio: $0))" }
        // The value the alert watched comes first.
        let parts = alert.metric == .changeRate ? [changeText, priceText] : [priceText, changeText]
        return AlertMessage(
            title: "\(name) · \(alert.conditionText(currency: currency))",
            body: parts.compactMap { $0 }.joined(separator: " · ")
        )
    }

    /// `삼성전자 · 보유 수익금 +1,000,000원 이상` /
    /// `수익금 +1,050,000원 · 수익률 +12.30% · 보유 100주 · 현재가 72,500원`
    static func holding(
        name: String,
        alert: PriceAlert,
        thresholdCurrency: Currency,
        holding: StockHolding,
        price: (value: Decimal, currency: Currency)?
    ) -> AlertMessage {
        let basis = holding.afterCost ? "세후 " : ""
        let profitText = "\(basis)수익금 \(Fmt.signedAmount(holding.profit, holding.currency))"
        let rateText = "\(basis)수익률 \(holding.rateText)"
        // The value the alert watched comes first.
        let values = alert.metric == .holdingRate ? [rateText, profitText] : [profitText, rateText]
        let parts = values + ["보유 \(holding.quantityText)주", price.map { "현재가 \(Fmt.priceWithUnit($0.value, $0.currency))" }]
            .compactMap { $0 }
        return AlertMessage(
            title: "\(name) · \(alert.conditionText(currency: thresholdCurrency))",
            body: parts.joined(separator: " · ")
        )
    }

    /// `자산 · 💰 · 수익률 -10.00% 이하` / `전체 손익 수익률 -10.52% · -1,234,000₩`
    static func asset(
        label: String?,
        alert: PriceAlert,
        mode: AssetMode,
        rate: Decimal,
        profit: Decimal?
    ) -> AlertMessage {
        let title = ["자산", label, alert.conditionText(currency: .krw)].compactMap { $0 }.joined(separator: " · ")
        let body = ["\(mode.title) 수익률 \(Fmt.percent(ratio: rate))", profit.map(Fmt.krwProfit)]
            .compactMap { $0 }.joined(separator: " · ")
        return AlertMessage(title: title, body: body)
    }
}
