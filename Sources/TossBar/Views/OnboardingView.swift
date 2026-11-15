import SwiftUI

/// First-launch window: add a connection, confirm it works, then add starter items.
struct OnboardingView: View {
    let env: AppEnvironment
    var onFinish: () -> Void

    @State private var provider: Provider = .tossinvest
    @State private var connected: StoredConnection?
    @State private var addAsset = true
    @State private var addSamsung = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invest Stats 시작하기").font(.title2.weight(.semibold))
                    Text("증권사 Open API 를 연결하면 메뉴바에서 주가와 자산을 볼 수 있어요.")
                        .foregroundStyle(.secondary)
                }
            }

            if Provider.allCases.count > 1 {
                Picker("증권사", selection: $provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                .disabled(connected != nil)
            }

            ProviderHelp(provider: provider)

            GroupBox {
                ConnectionForm(connections: env.connections, provider: provider, existingID: nil) { stored, _ in
                    connected = stored
                }
                .id(provider)
                .padding(6)
            }

            if connected != nil, env.store.items.isEmpty {
                GroupBox("메뉴바에 추가할 항목") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("자산 — 보유 종목 전체 손익 ({수익}₩ ({수익률}%))", isOn: $addAsset)
                        Toggle("주가 — 삼성전자 (005930) 예시", isOn: $addSamsung)
                        Text("나중에 설정 > 항목에서 언제든 추가/삭제할 수 있습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }

            HStack {
                Button("나중에 하기") { onFinish() }
                Spacer()
                Button("시작하기") {
                    if let connected, env.store.items.isEmpty {
                        if addAsset {
                            env.store.upsert(MenuItemConfig(kind: .asset(AssetItemConfig()), connectionID: connected.id))
                        }
                        if addSamsung {
                            env.store.upsert(MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930")), connectionID: connected.id))
                        }
                    }
                    env.data.refreshSoon()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connected == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
