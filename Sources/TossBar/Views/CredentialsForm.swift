import AppKit
import SwiftUI

/// Client ID / Secret fields with a connection test. Used by onboarding and settings.
/// Also offers keys that another Mac shared through the iCloud Keychain, and the choice
/// of storing these keys there.
struct CredentialsForm: View {
    @ObservedObject var credentials: CredentialStore
    var onConnected: ([Account]) -> Void = { _ in }

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var syncWithICloud = false
    @State private var confirmDelete = false
    @State private var isTesting = false
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let shared = credentials.sharedClientId {
                sharedKeysBanner(clientId: shared)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Client ID").gridColumnAlignment(.trailing)
                    TextField("발급받은 client_id", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Client Secret")
                    SecureField(credentials.hasSecret ? "저장됨 (변경 시에만 입력)" : "발급받은 client_secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("iCloud 키체인에 저장해 같은 Apple 계정의 다른 Mac 과 공유", isOn: $syncWithICloud)
                    .disabled(!credentials.canSync)
                Group {
                    if credentials.canSync {
                        Text("다른 Mac 에서 TossBar 를 처음 열면 이 키를 바로 쓸 수 있습니다. 각 Mac 의 공인 IP 는 따로 허용 IP 로 등록해야 합니다. 변경 사항은 저장할 때 적용됩니다.")
                    } else {
                        Text("서명된 정식 릴리스 빌드에서만 사용할 수 있습니다.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: save) {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("저장 및 연결 테스트")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTesting || clientId.nilIfBlank == nil || (clientSecret.nilIfBlank == nil && !credentials.hasSecret))

                if credentials.isConfigured {
                    Button("키 삭제", role: .destructive) {
                        if credentials.syncsWithICloud {
                            confirmDelete = true
                        } else {
                            clear()
                        }
                    }
                    .confirmationDialog("iCloud 키체인에서 키를 삭제할까요?", isPresented: $confirmDelete) {
                        Button("삭제", role: .destructive, action: clear)
                    } message: {
                        Text("같은 키를 iCloud 키체인으로 공유하는 다른 Mac 에서도 삭제됩니다.")
                    }
                }
                Spacer()
            }

            switch status {
            case .idle:
                EmptyView()
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            clientId = credentials.clientId
            syncWithICloud = credentials.syncsWithICloud
        }
    }

    private func sharedKeysBanner(clientId shared: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("다른 Mac 에서 iCloud 키체인으로 공유한 키가 있습니다.")
                    .font(.callout.weight(.semibold))
                Text("Client ID: \(shared)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("이 키 사용") { run { try await credentials.useSharedKeys() } }
                    .disabled(isTesting)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func clear() {
        Task {
            await credentials.clear()
            clientId = ""
            clientSecret = ""
            syncWithICloud = false
            status = .idle
        }
    }

    private func save() {
        guard !isTesting, clientId.nilIfBlank != nil else { return }
        run {
            try await credentials.saveAndTest(
                clientId: clientId,
                clientSecret: clientSecret.nilIfBlank,
                syncWithICloud: syncWithICloud
            )
        }
    }

    /// Runs a save or a switch to shared keys, then reports the connection test.
    private func run(_ operation: @escaping () async throws -> [Account]) {
        guard !isTesting else { return }
        isTesting = true
        status = .idle
        Task {
            defer { isTesting = false }
            do {
                let accounts = try await operation()
                clientId = credentials.clientId
                clientSecret = ""
                syncWithICloud = credentials.syncsWithICloud
                status = .success(accounts.isEmpty
                                  ? "연결되었습니다. (조회 가능한 종합매매 계좌가 없습니다)"
                                  : "연결되었습니다. 계좌 \(accounts.count)개를 찾았습니다.")
                onConnected(accounts)
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}

/// How to get the API keys.
struct CredentialsHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API 키 발급 방법").font(.subheadline.weight(.semibold))
            Text("1. PC 웹(토스증권 WTS)에 로그인 → 설정 → Open API 에서 클라이언트를 등록합니다.")
            Text("2. 이 Mac 이 사용하는 공인 IP 를 허용 IP 로 등록해야 합니다. (미등록 시 403)")
            Text("3. 발급된 client_id / client_secret 을 아래에 입력하세요. 키는 기본적으로 이 Mac 사용자만 읽을 수 있는 파일(~/Library/Application Support/TossBar)에 저장되며, 원하면 iCloud 키체인에 저장해 다른 Mac 과 공유할 수 있습니다.")
            Text("※ 토스증권은 클라이언트당 토큰을 1개만 유효하게 유지합니다. 같은 키를 다른 프로그램과 함께 쓰면 서로의 토큰이 무효화되니 TossBar 전용 키를 쓰는 것을 권장합니다. iCloud 로 공유한 Mac 끼리는 토큰도 함께 공유해 이를 줄이지만, 동기화가 늦으면 잠시 오류가 날 수 있습니다.")
                .foregroundStyle(.secondary)
            Link("토스증권 Open API 문서 열기", destination: URL(string: "https://developers.tossinvest.com/docs")!)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// First-launch window: enter the keys, confirm the connection, then add starter items.
struct OnboardingView: View {
    let env: AppEnvironment
    var onFinish: () -> Void

    @ObservedObject private var credentials: CredentialStore
    @State private var connectedAccounts: [Account]?
    @State private var addAsset = true
    @State private var addSamsung = false

    init(env: AppEnvironment, onFinish: @escaping () -> Void) {
        self.env = env
        self.onFinish = onFinish
        self.credentials = env.credentials
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TossBar 시작하기").font(.title2.weight(.semibold))
                    Text("토스증권 Open API 키를 입력하면 메뉴바에서 주가와 자산을 볼 수 있어요.")
                        .foregroundStyle(.secondary)
                }
            }

            CredentialsHelp()

            GroupBox {
                CredentialsForm(credentials: credentials) { accounts in
                    connectedAccounts = accounts
                }
                .padding(6)
            }

            if connectedAccounts != nil, env.store.items.isEmpty {
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
                    if env.store.items.isEmpty {
                        if addAsset {
                            env.store.upsert(MenuItemConfig(kind: .asset(AssetItemConfig())))
                        }
                        if addSamsung {
                            env.store.upsert(MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930"))))
                        }
                    }
                    env.data.refreshSoon()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectedAccounts == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
