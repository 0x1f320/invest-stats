import Foundation

/// Currency for a US stock's price. Domestic stocks are always in KRW.
enum PriceDisplayCurrency: String, Codable, CaseIterable, Identifiable {
    /// The trading currency (USD for US stocks).
    case native
    /// Converted to KRW at the USD/KRW base rate.
    case krw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: return "달러 ($)"
        case .krw: return "원화 (₩)"
        }
    }
}

struct StockItemConfig: Codable, Hashable {
    var symbol: String
    /// Name shown in the menu bar. nil uses the stock's name.
    var displayName: String?
    var showName: Bool = true
    var showChange: Bool = true
    /// Price currency for US stocks, set per item.
    var displayCurrency: PriceDisplayCurrency = .native
    /// Custom menu bar format, such as `%n %p (%r)`. nil uses `defaultFormat`, which follows
    /// `showName` and `showChange`. See `TitleFormat`.
    var format: String?
    /// Shows the holding of the stock in `accountSeq`'s account in the popover. The menu bar
    /// shows it only through the holding tokens of a custom format.
    var showHolding: Bool = false
    /// The account whose holding is shown. nil means the first account.
    var accountSeq: Int64?
    /// Holding profit basis. false: raw profit. true: after fees and taxes.
    var afterCost: Bool = false
}

extension StockItemConfig {
    private enum CodingKeys: String, CodingKey {
        case symbol, displayName, showName, showChange, displayCurrency, format, showHolding, accountSeq, afterCost
    }

    /// Fills defaults for keys that older saved configs don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        showName = try c.decodeIfPresent(Bool.self, forKey: .showName) ?? true
        showChange = try c.decodeIfPresent(Bool.self, forKey: .showChange) ?? true
        displayCurrency = try c.decodeIfPresent(PriceDisplayCurrency.self, forKey: .displayCurrency) ?? .native
        format = try c.decodeIfPresent(String.self, forKey: .format)
        showHolding = try c.decodeIfPresent(Bool.self, forKey: .showHolding) ?? false
        accountSeq = try c.decodeIfPresent(Int64.self, forKey: .accountSeq)
        afterCost = try c.decodeIfPresent(Bool.self, forKey: .afterCost) ?? false
    }
}

enum AssetMode: String, Codable, CaseIterable, Identifiable {
    /// Profit on the holdings since purchase.
    case total
    /// Profit since the previous close.
    case daily

    var id: String { rawValue }
    var title: String {
        switch self {
        case .total: return "전체 손익"
        case .daily: return "일간 손익"
        }
    }
}

struct AssetItemConfig: Codable, Hashable {
    /// Prefix in the menu bar. Empty means none.
    var label: String = ""
    /// nil means the first account.
    var accountSeq: Int64?
    var mode: AssetMode = .total
    /// Profit basis. false: raw profit. true: after fees and taxes. Applies to the total
    /// mode only; the API reports daily profit before costs only.
    var afterCost: Bool = false
    /// Colors the menu bar profit and rate by their sign, following the app's color
    /// convention. Off keeps the text white.
    var colorByTrend: Bool = false
    /// Custom menu bar format, such as `%l %p`. nil uses `defaultFormat`, the design's
    /// `{profit}₩ ({rate}%)`. See `TitleFormat`.
    var format: String?

    /// True when the after-cost basis is actually in effect.
    var usesAfterCost: Bool { mode == .total && afterCost }
}

extension AssetItemConfig {
    private enum CodingKeys: String, CodingKey {
        case label, accountSeq, mode, afterCost, colorByTrend, format
    }

    /// Fills defaults for keys that older saved configs don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        accountSeq = try c.decodeIfPresent(Int64.self, forKey: .accountSeq)
        mode = try c.decodeIfPresent(AssetMode.self, forKey: .mode) ?? .total
        afterCost = try c.decodeIfPresent(Bool.self, forKey: .afterCost) ?? false
        colorByTrend = try c.decodeIfPresent(Bool.self, forKey: .colorByTrend) ?? false
        format = try c.decodeIfPresent(String.self, forKey: .format)
    }
}

struct IndicatorItemConfig: Codable, Hashable {
    /// A `MarketIndicator.catalog` symbol, such as `KOSPI` or `USD_KRW`.
    var symbol: String
    /// Name shown in the menu bar. nil uses the indicator's name.
    var displayName: String?
    var showName: Bool = true
    /// Shows the change since the previous close. The exchange rate has none to show.
    var showChange: Bool = true
    /// Custom menu bar format, such as `%n %p (%a)`. nil uses `defaultFormat`, which follows
    /// `showName` and `showChange`. See `TitleFormat`.
    var format: String?

    /// nil for a symbol this build doesn't know.
    var indicator: MarketIndicator? { MarketIndicator.find(symbol) }
}

extension IndicatorItemConfig {
    private enum CodingKeys: String, CodingKey {
        case symbol, displayName, showName, showChange, format
    }

    /// Fills defaults for keys that older saved configs don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        showName = try c.decodeIfPresent(Bool.self, forKey: .showName) ?? true
        showChange = try c.decodeIfPresent(Bool.self, forKey: .showChange) ?? true
        format = try c.decodeIfPresent(String.self, forKey: .format)
    }
}

/// An item's kind and settings. Saved as `{"<case>": {"_0": {...}}}`, so a new case leaves
/// the items saved before it as they are.
enum ItemKind: Codable, Hashable {
    case stock(StockItemConfig)
    case asset(AssetItemConfig)
    /// A market index, bond yield or the USD/KRW base rate.
    case indicator(IndicatorItemConfig)
}

/// One menu bar item. Each config becomes its own `NSStatusItem`.
struct MenuItemConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: ItemKind
    /// The connection the item reads from. nil, in items saved before connections
    /// existed, means the first connection.
    var connectionID: UUID?
    /// Notifications when the item's price or rate crosses a threshold. See `PriceAlert`.
    var alerts: [PriceAlert] = []

    var typeTitle: String {
        switch kind {
        case .stock: return "주가"
        case .asset: return "자산"
        case .indicator: return "지표"
        }
    }
}

extension MenuItemConfig {
    private enum CodingKeys: String, CodingKey {
        case id, kind, connectionID, alerts
    }

    /// Fills defaults for keys that older saved configs don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        connectionID = try c.decodeIfPresent(UUID.self, forKey: .connectionID)
        alerts = try c.decodeIfPresent([LossyDecodable<PriceAlert>].self, forKey: .alerts)?
            .compactMap(\.value) ?? []
    }
}

extension Array where Element == MenuItemConfig {
    /// Symbols used by stock items, without duplicates.
    var stockSymbols: [String] {
        var seen = Set<String>()
        return compactMap {
            if case .stock(let config) = $0.kind, seen.insert(config.symbol).inserted { return config.symbol }
            return nil
        }
    }

    /// Whether any stock item shows prices in KRW, which needs the USD/KRW rate.
    var needsUsdKrwForStocks: Bool {
        contains {
            if case .stock(let config) = $0.kind { return config.displayCurrency == .krw }
            return false
        }
    }

    /// Symbols of indicator items that the market indicator API serves, without duplicates.
    /// The exchange rate is left out; it comes with the USD/KRW rate.
    var indicatorSymbols: [String] {
        var seen = Set<String>()
        return compactMap {
            guard case .indicator(let config) = $0.kind, config.indicator?.isMarketIndicator == true,
                  seen.insert(config.symbol).inserted else { return nil }
            return config.symbol
        }
    }

    /// Whether any indicator item shows the USD/KRW base rate.
    var needsUsdKrwForIndicators: Bool {
        contains {
            if case .indicator(let config) = $0.kind { return config.indicator?.category == .exchangeRate }
            return false
        }
    }

    /// Stock items that show the holding of their stock, so their account's holdings are
    /// fetched. See `StockItemConfig.needsHoldings`.
    var holdingStockConfigs: [StockItemConfig] {
        compactMap {
            if case .stock(let config) = $0.kind, config.needsHoldings { return config }
            return nil
        }
    }

    var assetConfigs: [AssetItemConfig] {
        compactMap {
            if case .asset(let config) = $0.kind { return config }
            return nil
        }
    }
}

/// The list of menu bar items, persisted in UserDefaults.
/// Their order in the menu bar is managed by macOS (⌘-drag) or a menu bar manager, not here.
@MainActor
final class ItemStore: ObservableObject {
    nonisolated static let defaultsKey = "menuItems.v1"

    @Published var items: [MenuItemConfig] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([MenuItemConfig].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func item(_ id: UUID) -> MenuItemConfig? {
        items.first { $0.id == id }
    }

    func upsert(_ item: MenuItemConfig) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    /// Changes an item's settings from its popover, keeping its connection.
    func updateKind(_ id: UUID, _ kind: ItemKind) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].kind = kind
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func stockConfig(_ id: UUID) -> StockItemConfig? {
        if case .stock(let config)? = item(id)?.kind { return config }
        return nil
    }

    func assetConfig(_ id: UUID) -> AssetItemConfig? {
        if case .asset(let config)? = item(id)?.kind { return config }
        return nil
    }

    func indicatorConfig(_ id: UUID) -> IndicatorItemConfig? {
        if case .indicator(let config)? = item(id)?.kind { return config }
        return nil
    }

    /// Changes a stock item's config in place, as the item settings window does on every
    /// edit. Does nothing for a missing or non-stock item, or when nothing changes.
    func updateStock(_ id: UUID, _ change: (inout StockItemConfig) -> Void) {
        guard var config = stockConfig(id) else { return }
        change(&config)
        replaceKind(of: id, with: .stock(config))
    }

    /// Changes an asset item's config in place. See `updateStock`.
    func updateAsset(_ id: UUID, _ change: (inout AssetItemConfig) -> Void) {
        guard var config = assetConfig(id) else { return }
        change(&config)
        replaceKind(of: id, with: .asset(config))
    }

    /// Changes an indicator item's config in place. See `updateStock`.
    func updateIndicator(_ id: UUID, _ change: (inout IndicatorItemConfig) -> Void) {
        guard var config = indicatorConfig(id) else { return }
        change(&config)
        replaceKind(of: id, with: .indicator(config))
    }

    /// Points an item at another connection. An asset or stock item's account belongs to its
    /// old connection, so the item goes back to the new connection's first account.
    func updateConnection(_ id: UUID, to connectionID: UUID?) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].connectionID != connectionID else { return }
        var item = items[index]
        item.connectionID = connectionID
        switch item.kind {
        case .asset(var config):
            config.accountSeq = nil
            item.kind = .asset(config)
        case .stock(var config):
            config.accountSeq = nil
            item.kind = .stock(config)
        case .indicator:
            break
        }
        items[index] = item
    }

    private func replaceKind(of id: UUID, with kind: ItemKind) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind != kind else { return }
        items[index].kind = kind
    }

    /// Points items that don't name a connection at `connectionID`. Used once, when the
    /// keys saved by an earlier version become a connection.
    func assignConnection(_ connectionID: UUID) {
        guard items.contains(where: { $0.connectionID == nil }) else { return }
        items = items.map { item in
            var item = item
            if item.connectionID == nil { item.connectionID = connectionID }
            return item
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
