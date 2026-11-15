import SwiftUI

// MARK: - Settings window

/// The settings window's tabs, shown as toolbar tabs like other macOS settings windows.
@MainActor
enum SettingsTabs {
    /// UserDefaults key for the last selected tab.
    static let selectionKey = "settingsTab"

    /// The tab to open with, from the last one selected.
    static var savedSelection: String? {
        let saved = UserDefaults.standard.string(forKey: selectionKey)
        // The tab was called "api" before connections.
        return saved == "api" ? "connections" : saved
    }

    static func make(env: AppEnvironment) -> [ToolbarTab] {
        [
            ToolbarTab("items", "항목", symbol: "menubar.rectangle") {
                ItemsSettingsView(env: env)
                    .frame(width: 560, height: 400)
            },
            ToolbarTab("connections", "연결", symbol: "link") {
                ConnectionsSettingsView(env: env)
                    .frame(width: 560, height: 400)
            },
            ToolbarTab("general", "일반", symbol: "gearshape") {
                GeneralSettingsView(settings: env.settings, env: env)
                    .frame(width: 560, height: 300)
            },
            ToolbarTab("update", "업데이트", symbol: "arrow.down.circle") {
                UpdateSettingsView(updater: env.updater)
                    .frame(width: 560, height: 340)
            },
        ]
    }
}

// MARK: - Items

struct ItemsSettingsView: View {
    let env: AppEnvironment
    @ObservedObject private var store: ItemStore
    @ObservedObject private var data: MarketDataHub
    @ObservedObject private var connections: ConnectionStore
    @State private var selection: UUID?

    init(env: AppEnvironment) {
        self.env = env
        self.store = env.store
        self.data = env.data
        self.connections = env.connections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("각 항목이 메뉴바 아이템 하나가 됩니다. 메뉴바에서의 위치는 ⌘+드래그나 Thaw·Ice 같은 메뉴바 관리 앱으로 바꿀 수 있습니다.")
                .font(.callout).foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(store.items) { item in
                    row(item)
                        .tag(item.id)
                        .contextMenu {
                            Button("편집…") { env.editItem(item.id) }
                            Button("삭제", role: .destructive) { store.remove(item.id) }
                        }
                }
                .onDelete { offsets in
                    offsets.map { store.items[$0].id }.forEach(store.remove)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if store.items.isEmpty {
                    Text(connections.isEmpty
                         ? "아직 연결이 없습니다.\n먼저 '연결' 탭에서 증권사를 연결하세요."
                         : "아직 항목이 없습니다.\n아래 + 버튼으로 '주가', '자산' 또는 '지표' 항목을 추가하세요.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    Button("주가 항목 추가…") { env.openEditor(.newStock) }
                    Button("자산 항목 추가…") { env.openEditor(.newAsset) }
                    Button("지표 항목 추가…") { env.openEditor(.newIndicator) }
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .fixedSize()
                .disabled(connections.isEmpty)

                Button {
                    if let selection { env.editItem(selection) }
                } label: {
                    Label("편집", systemImage: "pencil")
                }
                .disabled(selection == nil)

                Button(role: .destructive) {
                    if let selection { store.remove(selection) }
                    selection = nil
                } label: {
                    Label("삭제", systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func row(_ item: MenuItemConfig) -> some View {
        HStack(spacing: 10) {
            let service = data.service(for: item)
            switch item.kind {
            case .stock(let config):
                Image(systemName: "chart.xyaxis.line").foregroundStyle(.blue).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("주가 · \(config.displayName?.nilIfBlank ?? service?.stockInfo[config.symbol]?.name ?? config.symbol)")
                    detail(item, stockDetail(config))
                }
            case .asset(let config):
                Image(systemName: "wallet.pass").foregroundStyle(.orange).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("자산" + (config.label.nilIfBlank.map { " · \($0)" } ?? ""))
                    detail(item, assetDetail(config, service: service))
                }
            case .indicator(let config):
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.purple).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("지표 · \(config.displayName?.nilIfBlank ?? config.indicator?.name ?? config.symbol)")
                    detail(item, indicatorDetail(config))
                }
            }
            Spacer()
            Button {
                store.remove(item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
        .padding(.vertical, 3)
    }

    private func stockDetail(_ config: StockItemConfig) -> String {
        [
            config.symbol,
            config.showName ? "이름 표시" : "이름 숨김",
            config.showChange ? "등락률 표시" : "등락률 숨김",
            config.displayCurrency == .krw ? "원화 환산" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// The item's settings, led by its connection when there is more than one, or a warning
    /// when its connection is gone.
    @ViewBuilder
    private func detail(_ item: MenuItemConfig, _ text: String) -> some View {
        if let connection = connections.resolve(item.connectionID) {
            Text(connections.connections.count > 1 ? "\(ConnectionPicker.title(connection)) · \(text)" : text)
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("⚠︎ 연결 없음 · 편집해서 연결을 지정하세요")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func indicatorDetail(_ config: IndicatorItemConfig) -> String {
        guard let indicator = config.indicator else { return "\(config.symbol) · 지원하지 않는 지표" }
        return [
            indicator.displaySymbol,
            indicator.category.title,
            config.showName ? "이름 표시" : "이름 숨김",
            indicator.category == .exchangeRate ? nil : (config.showChange ? "등락 표시" : "등락 숨김"),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private func assetDetail(_ config: AssetItemConfig, service: MarketDataService?) -> String {
        let account = service?.accounts.first { $0.accountSeq == config.accountSeq }?.maskedNumber ?? "기본 계좌"
        return [
            account,
            config.mode.title,
            config.usesAfterCost ? "수수료·세금 제외" : nil,
            config.colorByTrend ? "손익 색상" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    let env: AppEnvironment
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Picker("갱신 주기", selection: $settings.refreshInterval) {
                Text("5초").tag(5.0)
                Text("10초").tag(10.0)
                Text("15초").tag(15.0)
                Text("30초").tag(30.0)
                Text("1분").tag(60.0)
                Text("5분").tag(300.0)
            }
            .onChange(of: settings.refreshInterval) { _, _ in env.data.start() }

            Picker("등락 색상 규칙", selection: $settings.koreanColorConvention) {
                Text("상승 빨강 · 하락 파랑 (국내식)").tag(true)
                Text("상승 초록 · 하락 빨강 (해외식)").tag(false)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("장이 닫힌 항목 흐리게 표시", isOn: $settings.dimClosedMarkets)
                Text("항목이 따르는 시장이 모두 닫혀 있으면 메뉴바 텍스트를 흐리게 표시합니다. 프리마켓·애프터마켓·데이마켓은 열린 것으로 봅니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.set(newValue)
                        launchError = nil
                    } catch {
                        launchError = "설정하지 못했습니다: \(error.localizedDescription) (.app 번들로 실행해야 동작합니다)"
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }

            Section {
                Text("데이터 출처: 각 연결의 증권사 Open API (REST). 시세는 갱신 주기마다 연결별로 일괄 조회하며, 그룹별 호출 한도를 넘지 않도록 자동 조절합니다. 항목들이 따르는 시장이 모두 닫혀 있으면 5분마다 조회하고, 장이 열리면 갱신 주기로 돌아갑니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Invest Stats 종료") { env.quit() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(10)
    }
}
