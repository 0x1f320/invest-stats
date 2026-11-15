import Combine
import Foundation

/// The value an alert compares, read from data the app already loaded.
struct AlertObservation: Equatable {
    /// The API's value: a price in the trading currency, or a ratio.
    let value: Decimal
    /// What the value belongs to, such as `stock:005930`. See `AlertEvaluator.signature`.
    let subject: String
    /// The stock's trading currency; KRW for asset items.
    let currency: Currency
    /// Sets the day boundary of "once per day": the exchange's time zone.
    let timeZone: TimeZone
}

/// Watches every item's alerts. Whenever the data changes, it reads each enabled alert's
/// value, steps it through `AlertEvaluator`, and posts a notification when it fires.
@MainActor
final class AlertMonitor: ObservableObject {
    nonisolated static let statesKey = "alertStates.v1"

    /// Each alert's state, by alert id. Disabled alerts have none, so turning one back on
    /// starts from a fresh baseline instead of firing for a crossing it didn't watch.
    @Published private(set) var states: [UUID: AlertState]

    private let store: ItemStore
    private let data: MarketDataHub
    private let notifier: AlertNotifier
    private let defaults: UserDefaults
    private var cancellable: AnyCancellable?

    init(store: ItemStore, data: MarketDataHub, notifier: AlertNotifier, defaults: UserDefaults = .standard) {
        self.store = store
        self.data = data
        self.notifier = notifier
        self.defaults = defaults
        states = Self.loadStates(from: defaults)

        // Evaluate after each batch of data or settings changes, like the menu bar redraw.
        cancellable = Publishers.Merge(data.objectWillChange, store.objectWillChange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
    }

    // MARK: Evaluation

    func evaluate(now: Date = Date()) {
        var next: [UUID: AlertState] = [:]
        var finished: [(alert: UUID, item: UUID)] = []

        for item in store.items {
            for alert in item.alerts where alert.isEnabled && alert.threshold != nil {
                let previous = states[alert.id]
                guard let observation = observation(for: alert, of: item) else {
                    // No value yet (loading, or the connection is gone): keep waiting.
                    next[alert.id] = previous
                    continue
                }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = observation.timeZone
                let step = AlertEvaluator.step(
                    alert,
                    signature: AlertEvaluator.signature(for: alert, subject: observation.subject),
                    value: observation.value,
                    previous: previous,
                    now: now,
                    calendar: calendar
                )
                next[alert.id] = step.state
                guard step.fires else { continue }
                notify(alert, item: item, observation: observation)
                if alert.repeatMode == .once { finished.append((alert.id, item.id)) }
            }
        }

        if next != states {
            states = next
            saveStates()
        }
        // "Once" alerts turn themselves off after firing.
        for (alertID, itemID) in finished {
            store.updateAlert(alertID, of: itemID) { $0.isEnabled = false }
        }
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
        default:
            // A metric that doesn't apply to the item's kind.
            return nil
        }
    }

    // MARK: Notification

    private func notify(_ alert: PriceAlert, item: MenuItemConfig, observation: AlertObservation) {
        guard let service = data.service(for: item) else { return }
        let message: AlertMessage
        switch item.kind {
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
        notifier.post(title: message.title, body: message.body, thread: item.id.uuidString)
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
