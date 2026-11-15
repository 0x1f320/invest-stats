import SwiftUI

// The add dialog and item settings panes for indicator items. See ItemEditors.swift for the
// shared pieces and how the dialogs and settings windows behave.

/// Picks an indicator from the catalog, grouped by category.
struct IndicatorPicker: View {
    @Binding var symbol: String

    private static let categories: [MarketIndicator.Category] = [.index, .bond, .exchangeRate]

    var body: some View {
        Picker("지표", selection: $symbol) {
            if MarketIndicator.find(symbol) == nil {
                Text("지원하지 않는 지표 (\(symbol))").tag(symbol)
            }
            ForEach(Self.categories, id: \.self) { category in
                Section(category.title) {
                    ForEach(MarketIndicator.catalog.filter { $0.category == category }) { indicator in
                        Text(Self.title(indicator)).tag(indicator.symbol)
                    }
                }
            }
        }
    }

    static func title(_ indicator: MarketIndicator) -> String {
        indicator.category == .exchangeRate ? "\(indicator.name) 매매기준율" : indicator.name
    }
}

// MARK: - Add dialog

struct IndicatorAddDialog: View {
    let env: AppEnvironment
    var cancel: () -> Void
    var added: (UUID) -> Void

    @ObservedObject private var connections: ConnectionStore
    @State private var connectionID: UUID?
    @State private var symbol = MarketIndicator.catalog[0].symbol

    init(env: AppEnvironment, cancel: @escaping () -> Void, added: @escaping (UUID) -> Void) {
        self.env = env
        self.cancel = cancel
        self.added = added
        self.connections = env.connections
        _connectionID = State(initialValue: env.connections.connections.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaptionText("코스피·코스닥 지수, 국고채 금리 또는 원/달러 매매기준율을 메뉴바에 표시합니다. 값을 불러올 연결과 지표를 고르세요.")

            Form {
                ConnectionPicker(connections: connections, selection: $connectionID)
                IndicatorPicker(symbol: $symbol)
            }
            .formStyle(.columns)

            CaptionText("표시 이름, 등락 표시, 메뉴바 형식은 추가한 뒤 열리는 항목 설정 창에서 바꿀 수 있습니다.")

            HStack {
                Spacer()
                Button("취소", action: cancel).keyboardShortcut(.cancelAction)
                Button("추가") {
                    let item = MenuItemConfig(kind: .indicator(IndicatorItemConfig(symbol: symbol)), connectionID: connectionID)
                    env.store.upsert(item)
                    added(item.id)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(env.data.service(forConnection: connectionID) == nil)
            }
        }
        .editorPane()
    }
}

// MARK: - Item settings

extension ItemStore {
    /// A binding to one field of an indicator item that saves every change.
    func indicatorBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<IndicatorItemConfig, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.indicatorConfig(id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.updateIndicator(id) { $0[keyPath: keyPath] = value } }
        )
    }
}

struct IndicatorSourcePane: View {
    let env: AppEnvironment
    let id: UUID
    @ObservedObject private var store: ItemStore

    init(env: AppEnvironment, id: UUID) {
        self.env = env
        self.id = id
        self.store = env.store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                ItemConnectionPicker(env: env, id: id)
                IndicatorPicker(symbol: store.indicatorBinding(id, \.symbol, default: ""))
            }
            .formStyle(.columns)
            CaptionText("지수와 국고채 금리는 시장 지표 API 의 현재 값을, 원/달러는 환율 API 의 매매기준율을 그대로 표시합니다. 등락은 같은 API 가 주는 전일 종가와 비교한 값입니다.")
        }
        .editorPane()
    }
}

struct IndicatorDisplayPane: View {
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
        _displayName = State(initialValue: env.store.indicatorConfig(id)?.displayName ?? "")
        _format = State(initialValue: env.store.indicatorConfig(id)?.format ?? "")
    }

    private var hasCustomFormat: Bool { format.nilIfBlank != nil }

    private var category: MarketIndicator.Category? { store.indicatorConfig(id)?.indicator?.category }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("메뉴바 표시 이름", text: $displayName, prompt: Text("비우면 지표명 사용"))
                    .onChange(of: displayName) { _, name in
                        store.updateIndicator(id) { $0.displayName = name.nilIfBlank }
                    }
                Toggle("메뉴바에 이름 표시", isOn: store.indicatorBinding(id, \.showName, default: true))
                    .disabled(hasCustomFormat)
                if category != .exchangeRate {
                    Toggle(category == .bond ? "메뉴바에 전일 대비 등락폭 표시" : "메뉴바에 전일 대비 등락률 표시",
                           isOn: store.indicatorBinding(id, \.showChange, default: true))
                        .disabled(hasCustomFormat)
                }
                if hasCustomFormat {
                    CaptionText("사용자 지정 형식을 쓰는 동안에는 형식에 넣은 값만 표시합니다.")
                }
                if category == .exchangeRate {
                    CaptionText("환율 API 는 이전 값을 제공하지 않아 등락률과 등락폭(%r, %a)은 비어 있습니다.")
                }
            }
            .formStyle(.columns)

            Divider()

            if let item = store.item(id), let config = store.indicatorConfig(id) {
                TitleFormatEditor<IndicatorTitleToken>(
                    format: $format,
                    defaultFormat: config.defaultFormat,
                    preview: TitleRenderer.preview(for: item, env: env)
                )
            }
        }
        .editorPane()
        .onChange(of: format) { _, format in
            store.updateIndicator(id) { $0.format = format.nilIfBlank == nil ? nil : format }
        }
    }
}
