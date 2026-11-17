import AppKit
import SwiftUI

/// One menu bar item: one `NSStatusItem` and its popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    let id: UUID
    private(set) var config: MenuItemConfig
    private let env: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    /// Padding added to the text width for the fixed item length. macOS adds 16pt to a
    /// fixed-length item's window, so text + 4pt matches a variable-length item
    /// (text + 20pt). Measured on macOS 26.
    private static let horizontalPadding: CGFloat = 4
    /// Current item width. It only grows, so the item doesn't jitter as digits change.
    private var reservedWidth: CGFloat = 0

    init(config: MenuItemConfig, env: AppEnvironment) {
        self.id = config.id
        self.config = config
        self.env = env
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // A stable autosaveName lets macOS and menu bar managers (Thaw, Ice, …) recognize
        // the same item across launches and remember where it was placed.
        statusItem.autosaveName = Self.autosaveName(for: config.id)
        // Don't let ⌘-drag remove the item. Menu bar managers move icons by simulating ⌘-drag.
        statusItem.behavior = []
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        render()
    }

    static func autosaveName(for id: UUID) -> String {
        "TossBar.\(id.uuidString)"
    }

    func update(_ config: MenuItemConfig) {
        guard config != self.config else { return }
        let formatChanged = config.kind != self.config.kind || config.connectionID != self.config.connectionID
        self.config = config
        // A different format (name shown, currency, …) needs a fresh width.
        if formatChanged { reservedWidth = 0 }
        render()
    }

    func tearDown() {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Forgets the saved menu bar position once an item is deleted for good.
    static func forgetPosition(of id: UUID) {
        let name = autosaveName(for: id)
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(name)")
    }

    /// Whether macOS left the item out of the menu bar. When "Allow in Menu Bar" is off
    /// (macOS 26), the item's window sits off screen at (0, -22). Items hidden by a menu
    /// bar manager such as Thaw stay at menu bar height, so they don't count.
    var isNotPlacedBySystem: Bool {
        guard let window = statusItem.button?.window else { return true }
        return window.frame.maxY <= 0
    }

    /// The item's actual state, for `TOSSBAR_DIAG=1`.
    var diagnostics: String {
        let button = statusItem.button
        let window = button?.window
        return [
            "name=\(statusItem.autosaveName ?? "-")",
            "isVisible=\(statusItem.isVisible)",
            "length=\(statusItem.length)",
            "title=\(button?.attributedTitle.string ?? "-")",
            "buttonFrame=\(button.map { NSStringFromRect($0.frame) } ?? "-")",
            "window=\(window.map { NSStringFromRect($0.frame) } ?? "nil")",
            "windowVisible=\(window?.isVisible ?? false)",
            "occlusionVisible=\(window?.occlusionState.contains(.visible) ?? false)",
            "screen=\(window?.screen.map { NSStringFromRect($0.frame) } ?? "nil")",
        ].joined(separator: " ")
    }

    func render() {
        guard let button = statusItem.button else { return }
        let title = TitleRenderer.title(for: config, env: env)
        let tooltip = TitleRenderer.tooltip(for: config, env: env)
        if button.toolTip != tooltip { button.toolTip = tooltip }
        // Leave an unchanged title alone. Setting it again re-lays out the menu bar,
        // which throws off menu bar managers.
        guard !button.attributedTitle.isEqual(to: title) else { return }
        button.attributedTitle = title

        // The width only grows, except when the text shrinks a lot (a loading
        // placeholder replaced by the value). `fittingSize` is meaningless for a
        // fixed-length item, so measure the text instead.
        let needed = ceil(title.size().width) + Self.horizontalPadding
        if needed > reservedWidth || needed < reservedWidth * 0.75 {
            reservedWidth = needed
            statusItem.length = needed
        }
    }

    // MARK: Click handling

    /// Left click opens the popover; right click or control-click opens the menu.
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        let root: AnyView
        switch (config.kind, env.data.service(for: config)) {
        case (_, nil):
            root = AnyView(MissingConnectionPopoverView(itemID: id, env: env))
        case (.stock, let data?):
            root = AnyView(StockPopoverView(itemID: id, env: env, data: data))
        case (.asset, let data?):
            root = AnyView(AssetPopoverView(itemID: id, env: env, data: data))
        case (.indicator, let data?):
            root = AnyView(IndicatorPopoverView(itemID: id, env: env, data: data))
        }
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
        env.data.refreshSoon()
    }

    /// Closes the popover when one of the app's windows (settings, an item editor, the update
    /// window) comes forward, such as one opened from the popover's own menu. A transient
    /// popover closes only on clicks outside it, so it would otherwise stay over that window.
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard popover.isShown, let window = notification.object as? NSWindow,
              window !== popover.contentViewController?.view.window,
              // Only titled windows: menus and other popovers don't count.
              window.styleMask.contains(.titled)
        else { return }
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        // Drop the content so the SwiftUI tasks (chart refresh) stop.
        popover.contentViewController = nil
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "이 항목 편집…", action: #selector(editItem), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "이 항목 삭제", action: #selector(deleteItem), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Invest Stats 종료", action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func refreshNow() { env.data.refreshSoon() }
    @objc private func openSettings() { env.openSettings() }
    @objc private func editItem() { env.editItem(id) }
    @objc private func quit() { env.quit() }

    @objc private func deleteItem() {
        let alert = NSAlert()
        alert.messageText = "이 메뉴바 항목을 삭제할까요?"
        alert.informativeText = TitleRenderer.tooltip(for: config, env: env)
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            env.store.remove(id)
        }
    }
}

/// Builds the menu bar text.
@MainActor
enum TitleRenderer {
    static var font: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular) }

    static func title(for config: MenuItemConfig, env: AppEnvironment) -> NSAttributedString {
        guard let data = env.data.service(for: config) else { return missingConnectionTitle(config) }
        let title: NSAttributedString
        switch config.kind {
        case .stock(let stock): title = stockTitle(stock, data: data)
        case .asset(let asset): title = assetTitle(asset, data: data)
        case .indicator(let indicator): title = indicatorTitle(indicator, data: data)
        }
        return dimmedIfClosed(title, config: config, data: data, env: env)
    }

    /// Fades the whole title, trend colors included, while every market the item follows
    /// is closed and the general setting asks for it.
    private static func dimmedIfClosed(_ title: NSAttributedString, config: MenuItemConfig,
                                       data: MarketDataService?, env: AppEnvironment) -> NSAttributedString {
        guard env.settings.dimClosedMarkets, let data, data.isClosed(config) else { return title }
        return dimmed(title)
    }

    /// The title at about half its brightness. The plain text takes `secondaryLabelColor`
    /// rather than `menuBarText` at half alpha, because a semantic color with an alpha
    /// resolves to a fixed color and would lose the menu bar's vibrancy.
    static func dimmed(_ title: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: title)
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let faded = color == .menuBarText
                ? .menuBarDimmedText
                : color.withAlphaComponent(color.alphaComponent * 0.5)
            result.addAttribute(.foregroundColor, value: faded, range: range)
        }
        return result
    }

    static func tooltip(for config: MenuItemConfig, env: AppEnvironment) -> String {
        guard let connection = env.connections.resolve(config.connectionID),
              let data = env.data.service(for: config)
        else { return "\(config.typeTitle) · 연결을 찾을 수 없습니다. 설정에서 이 항목의 연결을 지정하세요." }
        switch config.kind {
        case .stock(let stock):
            let name = data.stockInfo[stock.symbol]?.name ?? stock.symbol
            var tooltip = "주가 · \(name) (\(stock.symbol)) · \(connection.connection.displayName)"
            if stock.showHolding {
                tooltip += " · 보유 \(accountName(data.accountSeq(for: stock), data: data))"
            }
            return tooltip
        case .asset(let asset):
            let account = accountName(data.accountSeq(for: asset), data: data)
            return "자산 · \(connection.connection.displayName) · \(account) · \(asset.mode.title) · \(asset.usesAfterCost ? "수수료·세금 제외" : "원본 수익")"
        case .indicator(let config):
            guard let indicator = config.indicator else { return "지표 · \(config.symbol) · 지원하지 않는 지표" }
            let name = indicator.category == .exchangeRate ? "\(indicator.name) 매매기준율" : indicator.name
            return "지표 · \(name) (\(indicator.displaySymbol)) · \(connection.connection.displayName)"
        }
    }

    private static func accountName(_ seq: Int64?, data: MarketDataService) -> String {
        data.accounts.first { $0.accountSeq == seq }?.maskedNumber ?? "기본 계좌"
    }

    /// An item whose connection was deleted, or hasn't synced to this Mac yet.
    private static func missingConnectionTitle(_ config: MenuItemConfig) -> NSAttributedString {
        let prefix: String?
        switch config.kind {
        case .stock(let stock): prefix = stock.showName ? (stock.displayName?.nilIfBlank ?? stock.symbol) : stock.symbol
        case .asset(let asset): prefix = asset.label.nilIfBlank ?? "자산"
        case .indicator(let indicator): prefix = indicatorName(indicator)
        }
        return attributed([prefix, "⚠︎"].compactMap { $0 }.joined(separator: " "))
    }

    /// Menu bar text takes `menuBarText` unless an asset item opts into trend colors.
    private static func attributed(_ text: String, color: NSColor = .menuBarText) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private static func attributed(_ pieces: [TitlePiece], signedColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for piece in pieces.widenedSigned() {
            result.append(attributed(piece.text, color: piece.isSigned ? signedColor : .menuBarText))
        }
        return result
    }

    /// The text of the item settings preview: the live title when its data is loaded, with
    /// sample values standing in for whatever isn't known yet.
    static func preview(for config: MenuItemConfig, env: AppEnvironment) -> NSAttributedString {
        let data = env.data.service(for: config)
        switch config.kind {
        case .stock(let stock):
            let notHeld: Bool
            if case .notHeld? = data?.holdingState(for: stock) { notHeld = true } else { notHeld = false }
            return stockPreview(for: config, notHeld: notHeld, env: env)
        case .asset(let asset):
            let summary = data.flatMap { assetSummary(asset, data: $0) }
            let pieces = asset.titleFormat.render { token in
                let live = summary.flatMap { assetValue(token, config: asset, summary: $0) }
                return live ?? TitlePiece(token.example, isSigned: token.isSigned)
            }
            let trend = summary.map { headlineTrend(asset, summary: $0) } ?? .up
            let title = attributed(pieces, signedColor: asset.colorByTrend ? trend.menuBarColor : .menuBarText)
            return dimmedIfClosed(title, config: config, data: data, env: env)
        case .indicator(let indicator):
            let reading = indicator.indicator.flatMap { data?.indicatorReading($0) }
            let pieces = indicator.titleFormat.render { token in
                TitlePiece(reading.flatMap { indicatorValue(token, config: indicator, reading: $0) } ?? token.example)
            }
            return dimmedIfClosed(attributed(pieces, signedColor: .menuBarText), config: config, data: data, env: env)
        }
    }

    /// The preview of a stock item's format for one holding state. The held format shows
    /// sample holding values while the account doesn't hold the stock, and the not-held format
    /// shows them empty, as the menu bar does.
    static func stockPreview(for config: MenuItemConfig, notHeld: Bool, env: AppEnvironment) -> NSAttributedString {
        guard case .stock(let stock) = config.kind else { return preview(for: config, env: env) }
        let data = env.data.service(for: config)
        let holding = data?.holdingState(for: stock).holding
        let format = notHeld ? stock.titleFormat(for: .notHeld) : stock.titleFormat
        let pieces = format.render { token in
            guard token.isHolding else {
                return TitlePiece(data.flatMap { stockValue(token, config: stock, data: $0) } ?? token.example)
            }
            if notHeld { return TitlePiece("") }
            return TitlePiece(holding.flatMap { holdingValue(token, holding: $0) } ?? token.example)
        }
        return dimmedIfClosed(attributed(pieces, signedColor: .menuBarText), config: config, data: data, env: env)
    }

    // MARK: Stock items

    /// The name shown for a stock: the item's display name, else the stock's name, shortened.
    private static func stockName(_ config: StockItemConfig, data: MarketDataService) -> String {
        var name = config.displayName?.nilIfBlank ?? data.stockInfo[config.symbol]?.name ?? config.symbol
        if name.count > 12 { name = String(name.prefix(11)) + "…" }
        return name
    }

    /// A stock item's value for a format token, or nil while it isn't known.
    private static func stockValue(_ token: StockTitleToken, config: StockItemConfig, data: MarketDataService) -> String? {
        switch token {
        case .name:
            return stockName(config, data: data)
        case .symbol:
            return config.symbol
        case .price:
            guard let quote = data.quotes[config.symbol] else { return nil }
            return stockPrice(quote.lastPrice.value, quote: quote, config: config, data: data)
        case .changeRate:
            return data.change(for: config.symbol).map { Fmt.percent(ratio: $0.rate) }
        case .changeAmount:
            guard let quote = data.quotes[config.symbol], let change = data.change(for: config.symbol) else { return nil }
            let sign = change.amount > 0 ? "+" : (change.amount < 0 ? "-" : "")
            return sign + stockPrice(abs(change.amount), quote: quote, config: config, data: data)
        case .holdingProfit, .holdingRate, .holdingQuantity, .holdingValue, .averagePrice:
            switch data.holdingState(for: config) {
            case .unknown: return nil
            // Empty, so a custom format shows only the price while the stock isn't held.
            case .notHeld: return ""
            case .held(let holding): return holdingValue(token, holding: holding)
            }
        }
    }

    private static func holdingValue(_ token: StockTitleToken, holding: StockHolding) -> String? {
        switch token {
        case .holdingProfit: return holding.profitText
        case .holdingRate: return holding.rateText
        case .holdingQuantity: return holding.quantityText
        case .holdingValue: return holding.marketValueText
        case .averagePrice: return holding.averagePriceText
        case .name, .symbol, .price, .changeRate, .changeAmount: return nil
        }
    }

    /// A price in the item's display currency. A converted price gets 원, so it can't be
    /// mistaken for a domestic one.
    private static func stockPrice(_ value: Decimal, quote: PriceQuote, config: StockItemConfig, data: MarketDataService) -> String {
        let conversion = data.priceConversion(symbol: config.symbol, display: config.displayCurrency)
        return conversion.isConverted
            ? Fmt.priceWithUnit(conversion.apply(value), .krw)
            : Fmt.price(value, quote.currency)
    }

    private static func stockTitle(_ config: StockItemConfig, data: MarketDataService) -> NSAttributedString {
        let format = config.titleFormat(for: data.holdingState(for: config))
        guard data.quotes[config.symbol] != nil else {
            let failed = data.symbolErrors[config.symbol] != nil || (data.errorMessage != nil && !data.isRefreshing)
            let prefix = format.uses(.name) ? stockName(config, data: data) : config.symbol
            return attributed("\(prefix) \(failed ? "⚠︎" : "…")")
        }
        let pieces = format.render { TitlePiece(stockValue($0, config: config, data: data) ?? "…") }
        return attributed(pieces, signedColor: .menuBarText)
    }

    // MARK: Indicator items

    /// The item's display name, else the indicator's name, else its saved symbol.
    private static func indicatorName(_ config: IndicatorItemConfig) -> String {
        var name = config.displayName?.nilIfBlank ?? config.indicator?.name ?? config.symbol
        if name.count > 12 { name = String(name.prefix(11)) + "…" }
        return name
    }

    /// An indicator item's value for a format token, or nil while it isn't known. The
    /// exchange rate has no change, so its change tokens are empty rather than pending.
    private static func indicatorValue(_ token: IndicatorTitleToken, config: IndicatorItemConfig, reading: IndicatorReading) -> String? {
        switch token {
        case .name: return indicatorName(config)
        case .symbol: return reading.indicator.displaySymbol
        case .value: return reading.formattedValue
        case .changeRate: return reading.hasChange ? reading.formattedChangeRate : ""
        case .changeAmount: return reading.hasChange ? reading.formattedChange : ""
        }
    }

    private static func indicatorTitle(_ config: IndicatorItemConfig, data: MarketDataService) -> NSAttributedString {
        let format = config.titleFormat
        let prefix = format.uses(.name) ? indicatorName(config) : (config.indicator?.displaySymbol ?? config.symbol)
        guard let indicator = config.indicator else { return attributed("\(prefix) ⚠︎") }
        guard let reading = data.indicatorReading(indicator) else {
            let failed = data.indicatorErrors[indicator.symbol] != nil || (data.errorMessage != nil && !data.isRefreshing)
            return attributed("\(prefix) \(failed ? "⚠︎" : "…")")
        }
        let pieces = format.render { TitlePiece(indicatorValue($0, config: config, reading: reading) ?? "…") }
        return attributed(pieces, signedColor: .menuBarText)
    }

    // MARK: Asset items

    private static func assetSummary(_ config: AssetItemConfig, data: MarketDataService) -> AssetSummary? {
        guard let seq = data.accountSeq(for: config), let overview = data.holdings[seq] else { return nil }
        return AssetSummary(overview: overview, usdKrw: data.usdKrwRate)
    }

    /// The trend of the headline profit. The rate decides while the KRW amount waits for the
    /// USD/KRW rate.
    private static func headlineTrend(_ config: AssetItemConfig, summary: AssetSummary) -> Trend {
        let headline = summary.headline(for: config)
        return Trend(headline.amount ?? headline.rate)
    }

    /// An asset item's value for a format token, or nil while it isn't known. Amounts wait
    /// for the USD/KRW rate when the account holds US stocks.
    private static func assetValue(_ token: AssetTitleToken, config: AssetItemConfig, summary: AssetSummary) -> TitlePiece? {
        let headline = summary.headline(for: config)
        switch token {
        case .label:
            return TitlePiece(config.label.nilIfBlank ?? "")
        case .profit:
            return headline.amount.map { TitlePiece(Fmt.krwProfit($0), isSigned: true) }
        case .rate:
            return TitlePiece(Fmt.percent(ratio: headline.rate), isSigned: true)
        case .marketValue:
            let value = config.usesAfterCost ? summary.marketValueAfterCost : summary.marketValue
            return value.map { TitlePiece(Fmt.number($0) + "₩") }
        case .purchase:
            return summary.purchase.map { TitlePiece(Fmt.number($0) + "₩") }
        }
    }

    /// The item's format, `{profit}₩ ({rate}%)` by default, e.g. `+1,019,000₩ (+11.79%)`.
    private static func assetTitle(_ config: AssetItemConfig, data: MarketDataService) -> NSAttributedString {
        let format = config.titleFormat
        guard let summary = assetSummary(config, data: data) else {
            let label = format.uses(.label) ? config.label.nilIfBlank : nil
            let placeholder = data.errorMessage != nil && !data.isRefreshing ? "⚠︎" : "…"
            return attributed("\(label ?? "자산") \(placeholder)")
        }
        let pieces = format.render { token in
            assetValue(token, config: config, summary: summary)
                ?? TitlePiece(token.isAmount ? "…₩" : "…", isSigned: token.isSigned)
        }
        // Labels and other text keep the plain color; the profit and rate take the trend color when enabled.
        let color = config.colorByTrend ? headlineTrend(config, summary: summary).menuBarColor : .menuBarText
        return attributed(pieces, signedColor: color)
    }
}
