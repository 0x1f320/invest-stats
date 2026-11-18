import Combine
import Foundation

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1D"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "1일"
        case .month: return "1개월"
        case .threeMonths: return "3개월"
        case .sixMonths: return "6개월"
        case .year: return "1년"
        }
    }

    var interval: CandleInterval { self == .day ? .minute : .day }

    /// Number of candles to fetch (trading days for daily ranges).
    var candleCount: Int {
        switch self {
        case .day: return 1000 // Pages back until the session day ends.
        case .month: return 22
        case .threeMonths: return 66
        case .sixMonths: return 130
        case .year: return 250
        }
    }

    var cacheTTL: TimeInterval { self == .day ? 20 : 300 }
}

struct ChartPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// How to show a price: the factor to multiply by and the resulting currency.
struct PriceConversion {
    let factor: Decimal
    /// Currency to display.
    let currency: Currency
    /// The USD/KRW rate applied when converting to KRW, otherwise nil.
    let rate: Decimal?

    var isConverted: Bool { rate != nil }
    func apply(_ value: Decimal) -> Decimal { value * factor }
    func apply(_ value: Double) -> Double { value * factor.double }

    /// A US stock shown in KRW is converted once the rate is known. Until then, and for
    /// everything else, the price stays in its trading currency.
    static func make(native: Currency, display: PriceDisplayCurrency, usdKrw: Decimal?) -> PriceConversion {
        if display == .krw, native == .usd, let rate = usdKrw {
            return PriceConversion(factor: rate, currency: .krw, rate: rate)
        }
        return PriceConversion(factor: 1, currency: native, rate: nil)
    }
}

extension Currency {
    /// Time zone of the exchange, used to find the session day for intraday charts.
    var marketTimeZone: TimeZone {
        switch self {
        case .usd: return TimeZone(identifier: "America/New_York")!
        default: return TimeZone(identifier: "Asia/Seoul")!
        }
    }
}

/// The two latest daily candles. Used for the change against the previous close.
struct DailySnapshot {
    let latest: Candle
    let previous: Candle?
    let fetchedAt: Date
}

/// Data for the menu bar items of one connection. When several items show the same stock,
/// the API is still called once per refresh. `MarketDataHub` runs the polling loop.
@MainActor
final class MarketDataService: ObservableObject {
    @Published private(set) var quotes: [String: PriceQuote] = [:]
    @Published private(set) var daily: [String: DailySnapshot] = [:]
    @Published private(set) var stockInfo: [String: StockInfo] = [:]
    @Published private(set) var holdings: [Int64: HoldingsOverview] = [:]
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var usdKrw: ExchangeRate?
    /// Trading hours of the markets the items use. See `MarketCalendar.needsRefresh`.
    @Published private(set) var calendars: [MarketRegion: MarketCalendar] = [:]
    /// Market indicator values and their latest daily candles (newest first), by symbol.
    @Published private(set) var indicatorQuotes: [String: MarketIndicatorQuote] = [:]
    @Published private(set) var indicatorDaily: [String: (fetchedAt: Date, candles: [MarketIndicatorCandle])] = [:]
    @Published private(set) var indicatorErrors: [String: String] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var symbolErrors: [String: String] = [:]
    @Published private(set) var isRefreshing = false

    let connectionID: UUID
    let client: TossAPIClient
    /// The items that use this connection.
    private let items: @MainActor () -> [MenuItemConfig]

    private var lastFxFetch: Date?
    private var lastAccountsFetch: Date?
    private var lastStockInfoAttempt: [String: Date] = [:]
    private var lastCalendarAttempt: [MarketRegion: Date] = [:]
    private var chartCache: [String: (fetchedAt: Date, points: [Candle])] = [:]
    private var indicatorChartCache: [String: (fetchedAt: Date, candles: [MarketIndicatorCandle])] = [:]
    private var sparkCache: [String: (fetchedAt: Date, values: [Double])] = [:]
    private var sparkInFlight: [String: Task<[Double]?, Never>] = [:]

    init(connectionID: UUID, client: TossAPIClient, items: @escaping @MainActor () -> [MenuItemConfig]) {
        self.connectionID = connectionID
        self.client = client
        self.items = items
    }

    // MARK: Lifecycle

    /// Drops everything cached and refreshes. Called when the connection's keys change.
    func reset() {
        quotes = [:]
        daily = [:]
        holdings = [:]
        accounts = []
        usdKrw = nil
        calendars = [:]
        lastCalendarAttempt = [:]
        indicatorQuotes = [:]
        indicatorDaily = [:]
        indicatorErrors = [:]
        lastFxFetch = nil
        lastAccountsFetch = nil
        errorMessage = nil
        symbolErrors = [:]
        chartCache = [:]
        indicatorChartCache = [:]
        sparkCache = [:]
        refreshSoon()
    }

    func refreshSoon() {
        Task { await refresh() }
    }

    // MARK: Accessors

    func accountSeq(for config: AssetItemConfig) -> Int64? {
        config.accountSeq ?? accounts.first?.accountSeq
    }

    func accountSeq(for config: StockItemConfig) -> Int64? {
        config.accountSeq ?? accounts.first?.accountSeq
    }

    /// Whether the stock item's account holds its stock, and the holding if it does.
    func holdingState(for config: StockItemConfig) -> StockHoldingState {
        guard let seq = accountSeq(for: config), let overview = holdings[seq] else { return .unknown }
        guard let item = overview.holding(of: config.symbol) else { return .notHeld }
        return .held(StockHolding(item: item, config: config, usdKrw: usdKrwRate))
    }

    func currency(for symbol: String) -> Currency {
        quotes[symbol]?.currency ?? stockInfo[symbol]?.currency ?? daily[symbol]?.latest.currency ?? .krw
    }

    /// Change against the previous close, as (amount, ratio).
    func change(for symbol: String) -> (amount: Decimal, rate: Decimal)? {
        guard let quote = quotes[symbol], let previous = daily[symbol]?.previous else { return nil }
        let base = previous.closePrice.value
        guard base != 0 else { return nil }
        let amount = quote.lastPrice.value - base
        return (amount, amount / base)
    }

    /// USD/KRW base rate (매매기준율).
    var usdKrwRate: Decimal? { usdKrw?.midRate.value }

    func priceConversion(symbol: String, display: PriceDisplayCurrency) -> PriceConversion {
        PriceConversion.make(native: currency(for: symbol), display: display, usdKrw: usdKrwRate)
    }

    /// The market a stock trades on, or nil until its currency is known.
    func region(forSymbol symbol: String) -> MarketRegion? {
        let currency = quotes[symbol]?.currency ?? stockInfo[symbol]?.currency ?? daily[symbol]?.latest.currency
        return currency.flatMap(MarketRegion.init(currency:))
    }

    /// Whether every market this connection's items follow is closed. See `PollingPolicy`.
    func isIdle(at date: Date) -> Bool {
        PollingPolicy.isIdle(itemRegions: items().map(regions(for:))) { region in
            calendars[region]?.status(at: date)
        }
    }

    /// Whether every market one item follows is closed, by the same rules: anything
    /// unknown counts as open.
    func isClosed(_ item: MenuItemConfig, at date: Date = Date()) -> Bool {
        PollingPolicy.isIdle(itemRegions: [regions(for: item)]) { region in
            calendars[region]?.status(at: date)
        }
    }

    /// The markets an item's numbers move with, or nil until that is known.
    func regions(for item: MenuItemConfig) -> Set<MarketRegion>? {
        switch item.kind {
        case .stock(let config):
            return region(forSymbol: config.symbol).map { [$0] }
        case .asset(let config):
            guard let seq = accountSeq(for: config), let overview = holdings[seq] else { return nil }
            return overview.regions
        case .indicator(let config):
            switch config.indicator?.category {
            case .index, .bond:
                // KOSPI, KOSDAQ and the government bond yields are quoted in KRX hours.
                return [.kr]
            case .exchangeRate:
                // The rate updates every minute and follows no market's hours. nil counts
                // as open, so the connection is never idle (`PollingPolicy`).
                return nil
            case nil:
                // An unsupported symbol has nothing to refresh.
                return []
            }
        }
    }

    // MARK: Polling

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard await client.hasCredentials() else {
            errorMessage = TossAPIError.missingCredentials.errorDescription
            return
        }

        var errors: [String] = []
        let items = items()
        let symbols = items.stockSymbols
        let assetConfigs = items.assetConfigs
        let holdingStocks = items.holdingStockConfigs

        // 0) Accounts. ACCOUNT allows 1 request per second, so cache for 10 minutes.
        if !assetConfigs.isEmpty || !holdingStocks.isEmpty,
           accounts.isEmpty || (lastAccountsFetch.map { Date().timeIntervalSince($0) > 600 } ?? true) {
            do {
                accounts = try await client.accounts()
                lastAccountsFetch = Date()
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 1) Stock info (name, market, currency). Fetched once, retried at most every 5 minutes.
        let missingInfo = symbols.filter { symbol in
            stockInfo[symbol] == nil &&
                (lastStockInfoAttempt[symbol].map { Date().timeIntervalSince($0) > 300 } ?? true)
        }
        if !missingInfo.isEmpty {
            missingInfo.forEach { lastStockInfoAttempt[$0] = Date() }
            do {
                for info in try await client.stocks(missingInfo) {
                    stockInfo[info.symbol] = info
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 2) Current prices, up to 200 symbols per request.
        if !symbols.isEmpty {
            do {
                for quote in try await client.prices(symbols) {
                    quotes[quote.symbol] = quote
                }
                symbols.forEach { symbolErrors[$0] = nil }
            } catch {
                // A failed batch doesn't say which symbol is bad, so retry one by one.
                for symbol in symbols {
                    do {
                        if let quote = try await client.prices([symbol]).first {
                            quotes[symbol] = quote
                            symbolErrors[symbol] = nil
                        }
                    } catch {
                        symbolErrors[symbol] = error.localizedDescription
                    }
                }
                errors.append(error.localizedDescription)
            }
        }

        // 3) The two latest daily candles (previous close), cached for 2 minutes.
        for symbol in symbols {
            if let snapshot = daily[symbol], Date().timeIntervalSince(snapshot.fetchedAt) < 120 { continue }
            do {
                let page = try await client.candles(symbol: symbol, interval: .day, count: 2)
                if let latest = page.candles.first {
                    daily[symbol] = DailySnapshot(latest: latest, previous: page.candles.dropFirst().first, fetchedAt: Date())
                }
            } catch {
                symbolErrors[symbol] = symbolErrors[symbol] ?? error.localizedDescription
            }
        }

        // 4) USD/KRW rate for US holdings, stock items shown in KRW and the exchange rate
        //    indicator, cached for a minute (the API updates it every minute).
        if !assetConfigs.isEmpty || items.needsUsdKrwForStocks || items.needsUsdKrwForIndicators,
           lastFxFetch.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            do {
                usdKrw = try await client.usdKrwRate()
                lastFxFetch = Date()
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 5) Holdings, once per account even if several asset and stock items show it.
        let seqs = Set(assetConfigs.compactMap { accountSeq(for: $0) })
            .union(holdingStocks.compactMap { accountSeq(for: $0) })
        for seq in seqs.sorted() {
            do {
                holdings[seq] = try await client.holdings(account: seq)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 6) Trading hours of the markets the items use. They rarely change, so they are
        // fetched again only when stale, and a failure is retried after 5 minutes.
        let needed = items.reduce(into: Set<MarketRegion>()) { $0.formUnion(self.regions(for: $1) ?? []) }
        for region in MarketRegion.allCases where needed.contains(region) {
            let now = Date()
            guard calendars[region]?.needsRefresh(at: now) ?? true,
                  lastCalendarAttempt[region].map({ now.timeIntervalSince($0) > 300 }) ?? true
            else { continue }
            lastCalendarAttempt[region] = now
            do {
                switch region {
                case .kr: calendars[region] = MarketCalendar(kr: try await client.krMarketCalendar(), fetchedAt: now)
                case .us: calendars[region] = MarketCalendar(us: try await client.usMarketCalendar(), fetchedAt: now)
                }
            } catch {
                // The calendar only adds the market status, so a failure isn't shown as
                // an error of the item.
                continue
            }
        }
        // 7) Market indicators: one request for all of them, then their previous close.
        errors += await refreshIndicators(items.indicatorSymbols)

        errorMessage = errors.first
        if errors.isEmpty || !quotes.isEmpty || !holdings.isEmpty || !indicatorQuotes.isEmpty {
            lastUpdated = Date()
        }
    }

    /// Refreshes the market indicator values and, every 2 minutes, the two latest daily
    /// candles for the previous close. Returns the errors to show.
    private func refreshIndicators(_ symbols: [String]) async -> [String] {
        guard !symbols.isEmpty else { return [] }
        var errors: [String] = []
        do {
            for quote in try await client.indicatorPrices(symbols) {
                indicatorQuotes[quote.symbol] = quote
            }
            symbols.forEach { indicatorErrors[$0] = nil }
        } catch {
            // A failed batch doesn't say which symbol is bad, so retry one by one.
            for symbol in symbols {
                do {
                    if let quote = try await client.indicatorPrices([symbol]).first {
                        indicatorQuotes[symbol] = quote
                        indicatorErrors[symbol] = nil
                    }
                } catch {
                    indicatorErrors[symbol] = error.localizedDescription
                }
            }
            errors.append(error.localizedDescription)
        }

        for symbol in symbols {
            if let daily = indicatorDaily[symbol], Date().timeIntervalSince(daily.fetchedAt) < 120 { continue }
            do {
                let page = try await client.indicatorCandles(symbol: symbol, interval: .day, count: 2)
                indicatorDaily[symbol] = (Date(), page.candles)
            } catch {
                indicatorErrors[symbol] = indicatorErrors[symbol] ?? error.localizedDescription
            }
        }
        return errors
    }

    /// What an indicator item shows, or nil until its value loads.
    func indicatorReading(_ indicator: MarketIndicator) -> IndicatorReading? {
        if indicator.category == .exchangeRate {
            return usdKrw.map(IndicatorReading.init(exchangeRate:))
        }
        guard let quote = indicatorQuotes[indicator.symbol] else { return nil }
        return IndicatorReading(indicator: indicator, quote: quote, dailyCandles: indicatorDaily[indicator.symbol]?.candles ?? [])
    }

    /// For the account picker in the asset item editor.
    func loadAccounts() async throws -> [Account] {
        let result = try await client.accounts()
        accounts = result
        lastAccountsFetch = Date()
        return result
    }

    // MARK: Charts

    /// Candles for the chart, oldest first.
    func chartCandles(symbol: String, range: ChartRange) async throws -> [Candle] {
        let key = "\(symbol)|\(range.rawValue)"
        if let cached = chartCache[key], Date().timeIntervalSince(cached.fetchedAt) < range.cacheTTL {
            return cached.points
        }

        var collected: [Candle] = []
        var seen = Set<Date>()
        var before: String?
        var remaining = range.candleCount
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = currency(for: symbol).marketTimeZone

        while remaining > 0 {
            let page = try await client.candles(
                symbol: symbol,
                interval: range.interval,
                count: min(remaining, 200),
                before: before
            )
            for candle in page.candles where seen.insert(candle.timestamp).inserted {
                collected.append(candle)
            }
            remaining = range.candleCount - collected.count
            guard let next = page.nextBefore, !page.candles.isEmpty else { break }
            before = next

            // 1D: stop once the pages reach the session before the latest one.
            if range == .day, let first = collected.first, let last = collected.last,
               !calendar.isDate(Self.sessionTime(first), inSameDayAs: Self.sessionTime(last)) {
                break
            }
        }

        if range == .day, let newest = collected.first {
            let sessionDay = Self.sessionTime(newest)
            collected = collected.filter { calendar.isDate(Self.sessionTime($0), inSameDayAs: sessionDay) }
        }

        let ascending = Array(collected.reversed())
        chartCache[key] = (Date(), ascending)
        return ascending
    }

    /// An indicator's candles for the chart, oldest first. 1D pages through minute candles
    /// until it reaches the session before the latest one; it is for indices only, since
    /// bonds have daily candles only.
    func indicatorChartCandles(_ indicator: MarketIndicator, range: ChartRange) async throws -> [MarketIndicatorCandle] {
        let key = "\(indicator.symbol)|\(range.rawValue)"
        if let cached = indicatorChartCache[key], Date().timeIntervalSince(cached.fetchedAt) < range.cacheTTL {
            return cached.candles
        }

        var collected: [MarketIndicatorCandle] = []
        var seen = Set<Date>()
        var before: String?
        var remaining = range.candleCount
        while remaining > 0 {
            let page = try await client.indicatorCandles(
                symbol: indicator.symbol,
                interval: range.interval,
                count: min(remaining, 200),
                before: before
            )
            for candle in page.candles where seen.insert(candle.timestamp).inserted {
                collected.append(candle)
            }
            remaining = range.candleCount - collected.count
            guard let next = page.nextBefore, !page.candles.isEmpty else { break }
            before = next
            if range == .day, IndicatorChart.sessionCandles(collected).count < collected.count { break }
        }

        let candles = range == .day ? IndicatorChart.sessionCandles(collected) : collected
        let ascending = Array(candles.reversed())
        indicatorChartCache[key] = (Date(), ascending)
        return ascending
    }

    /// Closing prices of the last 30 trading days, for the mini charts in the holdings list.
    /// Cached for 10 minutes; concurrent callers share one request.
    func sparkline(symbol: String) async -> [Double]? {
        if let cached = sparkCache[symbol], Date().timeIntervalSince(cached.fetchedAt) < 600 {
            return cached.values
        }
        if let task = sparkInFlight[symbol] { return await task.value }
        let task = Task<[Double]?, Never> { [client] in
            guard let page = try? await client.candles(symbol: symbol, interval: .day, count: 30) else { return nil }
            return page.candles.reversed().map { $0.closePrice.double }
        }
        sparkInFlight[symbol] = task
        let values = await task.value
        sparkInFlight[symbol] = nil
        if let values { sparkCache[symbol] = (Date(), values) }
        return values
    }

    func cachedSparkline(symbol: String) -> [Double]? {
        sparkCache[symbol]?.values
    }

    /// A minute candle's timestamp is the end of the bar, so step back a minute to get
    /// the session day it belongs to.
    private static func sessionTime(_ candle: Candle) -> Date {
        candle.timestamp.addingTimeInterval(-60)
    }
}

/// One `MarketDataService` per connection, kept in step with the connection list, and the
/// polling loop that refreshes them all. Changes in any service are republished here, so
/// the menu bar redraws from one place.
@MainActor
final class MarketDataHub: ObservableObject {
    private(set) var services: [UUID: MarketDataService] = [:]

    private let connections: ConnectionStore
    private let store: ItemStore
    private let oneTimeAlerts: OneTimeAlertStore
    private let settings: AppSettings
    private var known: [UUID: StoredConnection] = [:]
    private var forwarders: [UUID: AnyCancellable] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var loopTask: Task<Void, Never>?
    /// When each connection's last refresh started.
    private var lastRefresh: [UUID: Date] = [:]
    /// Whether each connection's markets were all closed at the last tick.
    private var lastIdle: [UUID: Bool] = [:]

    init(connections: ConnectionStore, store: ItemStore, oneTimeAlerts: OneTimeAlertStore, settings: AppSettings) {
        self.connections = connections
        self.store = store
        self.oneTimeAlerts = oneTimeAlerts
        self.settings = settings
        connections.$connections
            .sink { [weak self] list in self?.sync(list) }
            .store(in: &cancellables)
    }

    /// The service for an item's connection, or nil when the connection is gone.
    func service(for item: MenuItemConfig) -> MarketDataService? {
        connections.resolve(item.connectionID).flatMap { services[$0.id] }
    }

    func service(forConnection id: UUID?) -> MarketDataService? {
        id.flatMap { services[$0] }
    }

    /// The items that read from a connection. Each counts its one-time alerts among its
    /// alerts, so the holdings and the rate they read are fetched.
    func items(for connectionID: UUID) -> [MenuItemConfig] {
        store.items.filter { connections.resolve($0.connectionID)?.id == connectionID }
            .includingOneTimeAlerts(oneTimeAlerts.alerts)
    }

    // MARK: Polling

    /// Ticks every refresh interval. A connection whose markets are all closed is
    /// refreshed less often (`PollingPolicy`), and at full speed again on the first tick
    /// after a market opens.
    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDue()
                let interval = self?.interval ?? 10
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private var interval: TimeInterval { max(settings.refreshInterval, 3) }

    /// Refreshes every connection now, whatever its markets. For a manual refresh, an
    /// opened popover or changed items.
    func refreshSoon() {
        Task { await refreshAll() }
    }

    /// Refreshes every connection that has items, side by side.
    func refreshAll() async {
        await refresh(services.values.filter { !items(for: $0.connectionID).isEmpty })
    }

    /// Refreshes the connections that are due, as the polling loop does.
    private func refreshDue() async {
        let now = Date()
        var marketsChanged = false
        let due = services.values.filter { service in
            let id = service.connectionID
            guard !items(for: id).isEmpty else { return false }
            let idle = service.isIdle(at: now)
            if lastIdle.updateValue(idle, forKey: id) != idle { marketsChanged = true }
            return PollingPolicy.isDue(lastRefresh: lastRefresh[id], now: now, interval: interval, idle: idle)
        }
        // A market that just closed doesn't call for a refresh, so redraw the menu bar,
        // which dims closed markets when asked to, without one.
        if marketsChanged { objectWillChange.send() }
        await refresh(due)
    }

    private func refresh(_ services: [MarketDataService]) async {
        let now = Date()
        for service in services { lastRefresh[service.connectionID] = now }
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { @MainActor in await service.refresh() }
            }
        }
    }

    // MARK: Connections

    private func sync(_ list: [StoredConnection]) {
        let ids = Set(list.map(\.id))
        for id in services.keys where !ids.contains(id) {
            services[id] = nil
            forwarders[id] = nil
            lastRefresh[id] = nil
            lastIdle[id] = nil
        }
        for stored in list {
            if let service = services[stored.id] {
                // Edited keys or a move to or from iCloud: drop what the old keys loaded.
                if known[stored.id]?.connection.values != stored.connection.values {
                    service.reset()
                }
            } else {
                let client = connections.client(for: stored)
                let id = stored.id
                let service = MarketDataService(connectionID: id, client: client) { [weak self] in
                    self?.items(for: id) ?? []
                }
                services[id] = service
                forwarders[id] = service.objectWillChange.sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                if loopTask != nil { service.refreshSoon() }
            }
        }
        known = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        objectWillChange.send()
    }
}
