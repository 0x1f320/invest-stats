import Combine
import Foundation
import Testing
@testable import TossBar

@MainActor
@Suite("Item store updates")
struct ItemStoreTests {
    private func makeStore() -> ItemStore {
        let defaults = UserDefaults(suiteName: "ItemStoreTests.\(UUID().uuidString)")!
        return ItemStore(defaults: defaults)
    }

    @Test func updatesOnlyTheStockItem() {
        let store = makeStore()
        let stock = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")))
        let asset = MenuItemConfig(kind: .asset(AssetItemConfig(label: "💰")))
        store.upsert(stock)
        store.upsert(asset)

        store.updateStock(stock.id) { $0.showName = false }

        #expect(store.stockConfig(stock.id)?.showName == false)
        #expect(store.item(asset.id) == asset)
        #expect(store.items.map(\.id) == [stock.id, asset.id])
    }

    @Test func ignoresAMismatchedKindOrMissingItem() {
        let store = makeStore()
        let asset = MenuItemConfig(kind: .asset(AssetItemConfig()))
        store.upsert(asset)

        store.updateStock(asset.id) { $0.symbol = "TSLA" }
        store.updateAsset(UUID()) { $0.label = "x" }

        #expect(store.items == [asset])
    }

    @Test func keepsTheItemsWhenNothingChanges() {
        let store = makeStore()
        let asset = MenuItemConfig(kind: .asset(AssetItemConfig(colorByTrend: true)))
        store.upsert(asset)
        var changes = 0
        let observer = store.$items.dropFirst().sink { _ in changes += 1 }

        store.updateAsset(asset.id) { $0.colorByTrend = true }
        store.updateAsset(asset.id) { $0.colorByTrend = false }

        #expect(changes == 1)
        #expect(store.assetConfig(asset.id)?.colorByTrend == false)
        observer.cancel()
    }

    @Test func changingTheConnectionResetsTheAccount() {
        let store = makeStore()
        let first = UUID()
        let second = UUID()
        let asset = MenuItemConfig(kind: .asset(AssetItemConfig(accountSeq: 7, colorByTrend: true)), connectionID: first)
        let stock = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")), connectionID: first)
        store.upsert(asset)
        store.upsert(stock)

        store.updateConnection(asset.id, to: second)
        store.updateConnection(stock.id, to: second)

        #expect(store.item(asset.id)?.connectionID == second)
        #expect(store.assetConfig(asset.id)?.accountSeq == nil)
        #expect(store.assetConfig(asset.id)?.colorByTrend == true)
        #expect(store.item(stock.id)?.connectionID == second)
        #expect(store.stockConfig(stock.id)?.symbol == "AAPL")
    }

    @Test func keepsTheAccountWhenTheConnectionStaysTheSame() {
        let store = makeStore()
        let connection = UUID()
        let asset = MenuItemConfig(kind: .asset(AssetItemConfig(accountSeq: 7)), connectionID: connection)
        store.upsert(asset)

        store.updateConnection(asset.id, to: connection)

        #expect(store.assetConfig(asset.id)?.accountSeq == 7)
    }

    @Test func updatesKeepTheConnection() {
        let store = makeStore()
        let connection = UUID()
        let stock = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "AAPL")), connectionID: connection)
        store.upsert(stock)

        store.updateStock(stock.id) { $0.showChange = false }

        #expect(store.item(stock.id)?.connectionID == connection)
    }

    @Test func persistsUpdates() {
        let defaults = UserDefaults(suiteName: "ItemStoreTests.\(UUID().uuidString)")!
        let store = ItemStore(defaults: defaults)
        let stock = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930")))
        store.upsert(stock)

        store.updateStock(stock.id) { $0.displayName = "삼성" }

        #expect(ItemStore(defaults: defaults).stockConfig(stock.id)?.displayName == "삼성")
    }
}
