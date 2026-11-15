import SwiftUI

// Add dialogs and item settings panes for stock and asset items.
//
// Adding asks only for what an item can't exist without (a stock, an account) and then opens
// the item's settings window. That window follows the macOS settings window style: toolbar
// tabs, and every change is saved as it is made, with no save button.

extension View {
    /// Lays out a dialog or settings pane: a fixed content width, so long text wraps instead
    /// of widening the window, inside standard padding.
    func editorPane(width: CGFloat = 412) -> some View {
        frame(width: width, alignment: .topLeading)
            .padding(24)
    }
}

/// A red error message, shown in full and selectable.
private struct ErrorText: View {
    let message: String

    var body: some View {
        Text(message).font(.callout).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct CaptionText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Stock lookup

@MainActor
private enum StockLookup {
    static func name(of symbol: String, universe: StockUniverse, service: MarketDataService?) -> String? {
        universe.entries.first { $0.symbol == symbol }?.name ?? service?.stockInfo[symbol]?.name
    }

    /// Whether a stock is a US stock, from the search list or the stock info already loaded.
    /// Otherwise a non-numeric code is taken as a US ticker (Korean codes are six characters
    /// starting with a digit).
    static func isUS(_ symbol: String, universe: StockUniverse, service: MarketDataService?) -> Bool {
        if let entry = universe.entries.first(where: { $0.symbol == symbol }) { return entry.isUS }
        if let info = service?.stockInfo[symbol] { return info.currency == .usd }
        return symbol.range(of: "^[0-9][0-9A-Z]{5}$", options: .regularExpression) == nil
    }

    /// Stocks in the search list are known to exist; others are checked through the
    /// connection's API.
    static func exists(_ symbol: String, universe: StockUniverse, service: MarketDataService) async throws -> Bool {
        if universe.entries.contains(where: { $0.symbol == symbol }) { return true }
        return try await !service.client.stocks([symbol]).isEmpty
    }
}

/// A search field over the stock list. A query that looks like a code is also offered as a
/// manual pick, for stocks missing from the list.
private struct StockPicker: View {
    @ObservedObject var universe: StockUniverse
    /// The connection whose client loads the stock list, if it isn't loaded yet.
    let service: MarketDataService?
    let prompt: String
    var onPick: (String) -> Void

    @State private var query = ""
    @State private var listSelection: String?

    private var results: [StockUniverse.Entry] { universe.search(query) }

    private var manualSymbol: String? {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty, q.range(of: "^[A-Z0-9.\\-]+$", options: .regularExpression) != nil else { return nil }
        return q
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(prompt, text: $query)
                .textFieldStyle(.roundedBorder)

            Group {
                if universe.isLoading && universe.entries.isEmpty {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("종목 목록 불러오는 중… (\(universe.loadedMarkets)/\(StockUniverse.markets.count))")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $listSelection) {
                        if let manual = manualSymbol, !results.contains(where: { $0.symbol == manual }) {
                            HStack {
                                Image(systemName: "keyboard")
                                Text("코드로 직접 지정: \(manual)")
                            }
                            .tag(manual)
                        }
                        ForEach(results) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text("\(entry.symbol) · \(entry.market)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .tag(entry.symbol)
                        }
                    }
                    .listStyle(.bordered)
                }
            }
            .frame(height: 220)

            if let message = universe.errorMessage, universe.entries.isEmpty {
                Text("종목 목록을 불러오지 못했습니다: \(message)\n코드를 직접 입력해도 지정할 수 있습니다.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: service?.connectionID) {
            if let client = service?.client { universe.ensureLoaded(using: client) }
        }
        .onChange(of: listSelection) { _, symbol in
            // Clicking empty space clears the list selection; keep the picked stock.
            if let symbol { onPick(symbol) }
        }
    }
}

// MARK: - Account picker

/// The account picker for a connection, loading its accounts when they haven't been loaded.
private struct AccountPicker: View {
    /// Republishes every connection's data, so the picker sees the accounts arrive.
    @ObservedObject var data: MarketDataHub
    let connectionID: UUID?
    @Binding var selection: Int64?

    @State private var isLoading = false
    @State private var error: String?

    private var service: MarketDataService? { data.service(forConnection: connectionID) }

    var body: some View {
        HStack {
            Picker("계좌", selection: $selection) {
                Text("기본 계좌 (첫 번째)").tag(Int64?.none)
                ForEach(service?.accounts ?? []) { account in
                    Text("\(account.maskedNumber) · \(account.accountType == "BROKERAGE" ? "종합매매" : account.accountType)")
                        .tag(Int64?.some(account.accountSeq))
                }
            }
            if isLoading { ProgressView().controlSize(.small) }
        }
        .task(id: connectionID) {
            error = nil
            guard let service, service.accounts.isEmpty else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                _ = try await service.loadAccounts()
            } catch {
                self.error = "계좌 목록을 불러오지 못했습니다: \(error.localizedDescription)"
            }
        }
        if let error {
            ErrorText(message: error)
        }
    }
}

// MARK: - Add dialogs

struct StockAddDialog: View {
    let env: AppEnvironment
    var cancel: () -> Void
    var added: (UUID) -> Void

    @ObservedObject private var connections: ConnectionStore
    @ObservedObject private var universe: StockUniverse
    @State private var connectionID: UUID?
    @State private var symbol: String?
    @State private var isValidating = false
    @State private var error: String?

    init(env: AppEnvironment, cancel: @escaping () -> Void, added: @escaping (UUID) -> Void) {
        self.env = env
        self.cancel = cancel
        self.added = added
        self.connections = env.connections
        self.universe = env.universe
        _connectionID = State(initialValue: env.connections.connections.first?.id)
    }

    private var service: MarketDataService? { env.data.service(forConnection: connectionID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                ConnectionPicker(connections: connections, selection: $connectionID)
            }
            .formStyle(.columns)

            HStack(spacing: 6) {
                Text("선택한 종목").foregroundStyle(.secondary)
                if let symbol {
                    Text("\(StockLookup.name(of: symbol, universe: universe, service: service) ?? symbol) (\(symbol))")
                        .fontWeight(.medium)
                } else {
                    Text("아래에서 검색해 선택하세요").foregroundStyle(.tertiary)
                }
            }

            StockPicker(universe: universe, service: service, prompt: "종목명 또는 코드 검색 (예: 삼성전자, 005930, AAPL)") {
                symbol = $0
                error = nil
            }

            CaptionText("표시 이름, 등락률, 가격 통화, 메뉴바 형식은 추가한 뒤 열리는 항목 설정 창에서 바꿀 수 있습니다.")

            if let error {
                ErrorText(message: error)
            }

            HStack {
                if isValidating { ProgressView().controlSize(.small) }
                Spacer()
                Button("취소", action: cancel).keyboardShortcut(.cancelAction)
                Button("추가", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(symbol == nil || service == nil || isValidating)
            }
        }
        .editorPane()
    }

    private func add() {
        guard let symbol, let service else { return }
        isValidating = true
        Task {
            defer { isValidating = false }
            do {
                guard try await StockLookup.exists(symbol, universe: universe, service: service) else {
                    error = "종목을 찾을 수 없습니다: \(symbol)"
                    return
                }
                let item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: symbol)), connectionID: connectionID)
                env.store.upsert(item)
                added(item.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AssetAddDialog: View {
    let env: AppEnvironment
    var cancel: () -> Void
    var added: (UUID) -> Void

    @ObservedObject private var connections: ConnectionStore
    @State private var connectionID: UUID?
    @State private var accountSeq: Int64?

    init(env: AppEnvironment, cancel: @escaping () -> Void, added: @escaping (UUID) -> Void) {
        self.env = env
        self.cancel = cancel
        self.added = added
        self.connections = env.connections
        _connectionID = State(initialValue: env.connections.connections.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaptionText("보유 종목 기준 손익을 메뉴바에 '{수익}₩ ({수익률}%)' 형식으로 표시합니다. 손익을 계산할 연결과 계좌를 고르세요.")

            Form {
                ConnectionPicker(connections: connections, selection: $connectionID)
                AccountPicker(data: env.data, connectionID: connectionID, selection: $accountSeq)
            }
            .formStyle(.columns)

            CaptionText("라벨, 손익 기준, 색상, 메뉴바 형식은 추가한 뒤 열리는 항목 설정 창에서 바꿀 수 있습니다.")

            HStack {
                Spacer()
                Button("취소", action: cancel).keyboardShortcut(.cancelAction)
                Button("추가") {
                    let item = MenuItemConfig(kind: .asset(AssetItemConfig(accountSeq: accountSeq)), connectionID: connectionID)
                    env.store.upsert(item)
                    added(item.id)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(env.data.service(forConnection: connectionID) == nil)
            }
        }
        .editorPane()
        .onChange(of: connectionID) { _, _ in
            // Accounts belong to a connection, so another connection starts from its first.
            accountSeq = nil
        }
    }
}

// MARK: - Item settings: bindings

extension ItemStore {
    /// A binding to one field of a stock item that saves every change.
    func stockBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<StockItemConfig, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.stockConfig(id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.updateStock(id) { $0[keyPath: keyPath] = value } }
        )
    }

    /// A binding to one field of an asset item that saves every change.
    func assetBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<AssetItemConfig, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.assetConfig(id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.updateAsset(id) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The connection picker of an item settings pane. It shows the connection the item resolves
/// to, so an item saved before connections shows the first one, and an item whose connection
/// is gone asks for one.
private struct ItemConnectionPicker: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject var store: ItemStore
    @ObservedObject var connections: ConnectionStore

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
        self.connections = env.connections
    }

    private var resolvedID: UUID? {
        store.item(id).flatMap { connections.resolve($0.connectionID)?.id }
    }

    var body: some View {
        ConnectionPicker(connections: connections, selection: Binding(
            get: { resolvedID },
            set: { newID in
                // Picking the connection the item already uses changes nothing.
                guard newID != resolvedID else { return }
                store.updateConnection(id, to: newID)
            }
        ))
        if resolvedID == nil {
            Text("이 항목이 쓰던 연결이 삭제되었거나 아직 이 Mac 에 동기화되지 않았습니다. 다른 연결을 지정하세요.")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Stock item settings

struct StockSymbolPane: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject private var store: ItemStore
    @ObservedObject private var data: MarketDataHub
    @ObservedObject private var universe: StockUniverse

    @State private var isValidating = false
    @State private var error: String?

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
        self.data = env.data
        self.universe = env.universe
    }

    private var symbol: String { store.stockConfig(id)?.symbol ?? "" }
    private var service: MarketDataService? { store.item(id).flatMap(data.service(for:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                ItemConnectionPicker(env: env, id: id)
            }
            .formStyle(.columns)

            HStack(spacing: 6) {
                Text("종목").foregroundStyle(.secondary)
                Text("\(StockLookup.name(of: symbol, universe: universe, service: service) ?? symbol) (\(symbol))")
                    .fontWeight(.medium)
                if isValidating { ProgressView().controlSize(.small) }
            }

            StockPicker(universe: universe, service: service,
                        prompt: "다른 종목으로 바꾸려면 검색 (예: 삼성전자, 005930, AAPL)", onPick: change)

            CaptionText("목록에서 고르면 이 항목의 종목이 바로 바뀝니다.")

            if let error {
                ErrorText(message: error)
            }
        }
        .editorPane()
    }

    private func change(to newSymbol: String) {
        guard newSymbol != symbol else { return }
        guard let service else {
            error = "연결을 먼저 지정하세요."
            return
        }
        error = nil
        isValidating = true
        Task {
            defer { isValidating = false }
            do {
                guard try await StockLookup.exists(newSymbol, universe: universe, service: service) else {
                    error = "종목을 찾을 수 없습니다: \(newSymbol)"
                    return
                }
                let isUS = StockLookup.isUS(newSymbol, universe: universe, service: service)
                store.updateStock(id) {
                    $0.symbol = newSymbol
                    // Only US stocks have a price currency to choose.
                    if !isUS { $0.displayCurrency = .native }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct StockDisplayPane: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject private var store: ItemStore
    @ObservedObject private var data: MarketDataHub
    /// Kept as typed; the store gets it trimmed, and nil when blank.
    @State private var displayName: String
    /// Kept as typed; the store gets nil when blank.
    @State private var format: String

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
        self.data = env.data
        _displayName = State(initialValue: env.store.stockConfig(id)?.displayName ?? "")
        _format = State(initialValue: env.store.stockConfig(id)?.format ?? "")
    }

    private var isUS: Bool {
        guard let item = store.item(id), let symbol = store.stockConfig(id)?.symbol else { return false }
        return StockLookup.isUS(symbol, universe: env.universe, service: data.service(for: item))
    }

    private var hasCustomFormat: Bool { format.nilIfBlank != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("메뉴바 표시 이름", text: $displayName, prompt: Text("비우면 종목명 사용"))
                    .onChange(of: displayName) { _, name in
                        store.updateStock(id) { $0.displayName = name.nilIfBlank }
                    }
                Toggle("메뉴바에 이름 표시", isOn: store.stockBinding(id, \.showName, default: true))
                    .disabled(hasCustomFormat)
                Toggle("메뉴바에 전일 대비 등락률 표시", isOn: store.stockBinding(id, \.showChange, default: true))
                    .disabled(hasCustomFormat)
                if hasCustomFormat {
                    CaptionText("사용자 지정 형식을 쓰는 동안에는 형식에 넣은 값만 표시합니다.")
                }
                if isUS {
                    Picker("가격 표시 통화", selection: store.stockBinding(id, \.displayCurrency, default: .native)) {
                        ForEach(PriceDisplayCurrency.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    CaptionText("원화는 USD/KRW 매매기준율로 환산합니다. 등락률은 달러 기준입니다.")
                }
            }
            .formStyle(.columns)

            Divider()

            if let item = store.item(id), let config = store.stockConfig(id) {
                TitleFormatEditor<StockTitleToken>(
                    format: $format,
                    defaultFormat: config.defaultFormat,
                    preview: TitleRenderer.preview(for: item, env: env)
                )
            }
        }
        .editorPane()
        .onChange(of: format) { _, format in
            store.updateStock(id) { $0.format = format.nilIfBlank == nil ? nil : format }
        }
    }
}

// MARK: - Asset item settings

struct AssetAccountPane: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject private var store: ItemStore
    @ObservedObject private var connections: ConnectionStore

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
        self.connections = env.connections
    }

    private var connectionID: UUID? {
        store.item(id).flatMap { connections.resolve($0.connectionID)?.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaptionText("이 연결과 계좌의 보유 종목으로 손익을 계산합니다. 연결을 바꾸면 계좌는 그 연결의 첫 번째 계좌로 돌아갑니다.")
            Form {
                ItemConnectionPicker(env: env, id: id)
                AccountPicker(data: env.data, connectionID: connectionID,
                              selection: store.assetBinding(id, \.accountSeq, default: nil))
            }
            .formStyle(.columns)
        }
        .editorPane()
    }
}

struct AssetProfitPane: View {
    let id: UUID
    @ObservedObject var store: ItemStore

    private var mode: AssetMode { store.assetConfig(id)?.mode ?? .total }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaptionText("보유 종목 기준 손익을 메뉴바에 '{수익}₩ ({수익률}%)' 형식으로 표시합니다. 형식은 표시 탭에서 바꿀 수 있습니다. 해외 주식 손익은 매매기준율로 원화 환산합니다.")
            Form {
                Picker("표시 기준", selection: store.assetBinding(id, \.mode, default: .total)) {
                    ForEach(AssetMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Picker("수익 기준", selection: store.assetBinding(id, \.afterCost, default: false)) {
                    Text("원본 수익").tag(false)
                    Text("수수료·세금 제외").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(mode != .total)
                CaptionText(mode == .total
                            ? "수수료·세금 제외는 토스증권이 계산한 세후 손익을 씁니다. 보유 종목 목록의 종목별 손익에도 같은 기준이 적용됩니다."
                            : "일간 손익은 원본 기준만 제공됩니다.")
            }
            .formStyle(.columns)
        }
        .editorPane()
    }
}

struct AssetDisplayPane: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject private var store: ItemStore
    @ObservedObject private var data: MarketDataHub
    @State private var label: String
    /// Kept as typed; the store gets nil when blank.
    @State private var format: String

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
        self.data = env.data
        _label = State(initialValue: env.store.assetConfig(id)?.label ?? "")
        _format = State(initialValue: env.store.assetConfig(id)?.format ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("라벨", text: $label, prompt: Text("선택 (예: 💰, 주식)"))
                    .onChange(of: label) { _, label in
                        store.updateAsset(id) { $0.label = label }
                    }
                Toggle("메뉴바에 손익 색상 표시", isOn: store.assetBinding(id, \.colorByTrend, default: false))
                CaptionText("수익은 빨강, 손실은 파랑처럼 손익 부호에 따라 손익과 수익률에 색을 입힙니다. 색상 규칙은 일반 설정을 따릅니다.")
            }
            .formStyle(.columns)

            Divider()

            if let item = store.item(id), let config = store.assetConfig(id) {
                TitleFormatEditor<AssetTitleToken>(
                    format: $format,
                    defaultFormat: config.defaultFormat,
                    preview: TitleRenderer.preview(for: item, env: env)
                )
            }
        }
        .editorPane()
        .onChange(of: format) { _, format in
            store.updateAsset(id) { $0.format = format.nilIfBlank == nil ? nil : format }
        }
    }
}

// MARK: - Menu bar format

/// The menu bar format of an item's display pane: the format field, the tokens it can use,
/// and a preview of the result.
private struct TitleFormatEditor<Token: TitleToken>: View {
    @Binding var format: String
    let defaultFormat: String
    let preview: NSAttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메뉴바 형식").font(.headline)
            HStack {
                TextField("메뉴바 형식", text: $format, prompt: Text(defaultFormat))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button("기본값", action: { format = "" })
                    .disabled(format.isEmpty)
            }
            CaptionText("비워 두면 기본 형식(\(defaultFormat))을 씁니다. 코드를 누르면 형식 끝에 추가되고, %% 는 % 문자 그대로 표시됩니다.")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(Array(Token.allCases), id: \.self) { token in
                    GridRow {
                        Button(token.code, action: { append(token) })
                            .buttonStyle(.link)
                            .font(.body.monospaced())
                            .help("형식 끝에 \(token.code) 추가")
                        Text(token.title)
                        Text(token.example)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.leading, 4)

            HStack(spacing: 10) {
                Text("미리보기").foregroundStyle(.secondary)
                MenuBarTextPreview(text: preview)
            }
            .padding(.top, 4)
        }
    }

    /// Adds a token at the end, after the default format when no custom format is set yet,
    /// so adding one value keeps the others.
    private func append(_ token: Token) {
        let base = format.isEmpty ? defaultFormat : format
        let separator = base.isEmpty || base.last?.isWhitespace == true ? "" : " "
        format = base + separator + token.code
    }
}

/// Menu bar text as it appears in the menu bar: the same font and colors on a dark strip.
private struct MenuBarTextPreview: View {
    let text: NSAttributedString

    var body: some View {
        AttributedLabel(text: text)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))
    }
}

private struct AttributedLabel: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: text)
        field.lineBreakMode = .byClipping
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if !field.attributedStringValue.isEqual(to: text) {
            field.attributedStringValue = text
            field.invalidateIntrinsicContentSize()
        }
    }
}
