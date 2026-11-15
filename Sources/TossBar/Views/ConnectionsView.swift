import SwiftUI

// MARK: - Settings tab

enum ConnectionEditorTarget: Identifiable {
    case new(Provider)
    case edit(UUID)

    var id: String {
        switch self {
        case .new(let provider): return "new." + provider.rawValue
        case .edit(let id): return id.uuidString
        }
    }
}

/// The 연결 tab: every connection, synced or kept on this Mac, and the editor for each.
struct ConnectionsSettingsView: View {
    let env: AppEnvironment
    @ObservedObject private var connections: ConnectionStore
    @ObservedObject private var store: ItemStore
    @State private var selection: UUID?
    @State private var editor: ConnectionEditorTarget?
    @State private var pendingDelete: StoredConnection?

    init(env: AppEnvironment) {
        self.env = env
        self.connections = env.connections
        self.store = env.store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("증권사 API 연결을 관리합니다. 같은 증권사도 여러 개 연결할 수 있고, 항목마다 어떤 연결로 불러올지 고를 수 있습니다.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ConnectionSyncSection(connections: connections)

            List(selection: $selection) {
                ForEach(connections.connections) { stored in
                    row(stored)
                        .tag(stored.id)
                        .contextMenu {
                            Button("편집…") { editor = .edit(stored.id) }
                            Button("삭제", role: .destructive) { pendingDelete = stored }
                        }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if connections.isEmpty {
                    Text("아직 연결이 없습니다.\n아래 + 버튼으로 연결을 추가하세요.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(Provider.allCases) { provider in
                        Button("\(provider.title) 연결 추가…") { editor = .new(provider) }
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .fixedSize()

                Button {
                    if let selection { editor = .edit(selection) }
                } label: {
                    Label("편집", systemImage: "pencil")
                }
                .disabled(selection == nil)

                Button(role: .destructive) {
                    pendingDelete = selection.flatMap(connections.connection)
                } label: {
                    Label("삭제", systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(20)
        .sheet(item: $editor) { target in
            switch target {
            case .new(let provider):
                ConnectionEditor(connections: connections, provider: provider, existingID: nil) { editor = nil }
            case .edit(let id):
                if let stored = connections.connection(id) {
                    ConnectionEditor(connections: connections, provider: stored.connection.provider, existingID: id) { editor = nil }
                } else {
                    // Deleted, here or on another Mac, while the editor was opening.
                    VStack(spacing: 12) {
                        Text("삭제된 연결입니다.").foregroundStyle(.secondary)
                        Button("닫기") { editor = nil }.keyboardShortcut(.cancelAction)
                    }
                    .padding(20)
                }
            }
        }
        .confirmationDialog(
            "'\(pendingDelete?.connection.displayName ?? "")' 연결을 삭제할까요?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { stored in
            Button("삭제", role: .destructive) {
                connections.delete(stored.id)
                if selection == stored.id { selection = nil }
            }
        } message: { stored in
            Text(deleteMessage(stored))
        }
    }

    private func usageCount(_ stored: StoredConnection) -> Int {
        env.data.items(for: stored.id).count
    }

    private func deleteMessage(_ stored: StoredConnection) -> String {
        var lines: [String] = []
        if connections.syncsWithICloud {
            lines.append("연결을 iCloud 로 동기화하고 있어 다른 Mac 에서도 삭제됩니다.")
        }
        let count = usageCount(stored)
        if count > 0 {
            lines.append("이 연결을 쓰는 항목 \(count)개는 다른 연결을 지정할 때까지 ⚠︎ 로 표시됩니다.")
        }
        return lines.isEmpty ? "저장된 키와 토큰이 삭제됩니다." : lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func row(_ stored: StoredConnection) -> some View {
        let connection = stored.connection
        HStack(spacing: 10) {
            Image(systemName: connection.provider.systemImage).foregroundStyle(.blue).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.displayName)
                Text([
                    connection.provider.title,
                    connection.identity.map { "Client ID \($0)" },
                    usageCount(stored) > 0 ? "항목 \(usageCount(stored))개" : "사용하는 항목 없음",
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

/// Sheet for adding or editing one connection.
struct ConnectionEditor: View {
    @ObservedObject var connections: ConnectionStore
    let provider: Provider
    let existingID: UUID?
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingID == nil ? "\(provider.title) 연결 추가" : "연결 편집").font(.title3.weight(.semibold))
            DisclosureGroup("API 키 발급 방법") {
                ProviderHelp(provider: provider).padding(.top, 4)
            }
            GroupBox {
                ConnectionForm(connections: connections, provider: provider, existingID: existingID).padding(6)
            }
            HStack {
                Spacer()
                Button("닫기", action: dismiss).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

// MARK: - Form

/// Name and keys for one connection, with a connection test. Used by the connection editor
/// and by onboarding.
struct ConnectionForm: View {
    @ObservedObject var connections: ConnectionStore
    let provider: Provider
    /// nil adds a new connection. After the first save the form edits that one.
    let existingID: UUID?
    var onConnected: (StoredConnection, [Account]) -> Void = { _, _ in }

    @State private var savedID: UUID?
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var isTesting = false
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    private var existing: StoredConnection? {
        (savedID ?? existingID).flatMap(connections.connection)
    }

    /// Whether a field can be left blank: a secret that is already saved.
    private func keepsSaved(_ field: ProviderField) -> Bool {
        field.isSecret && existing?.connection.values[field.key]?.nilIfBlank != nil
    }

    private var canSave: Bool {
        !isTesting && provider.fields.allSatisfy { values[$0.key]?.nilIfBlank != nil || keepsSaved($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("이름").gridColumnAlignment(.trailing)
                    TextField("이름", text: $name, prompt: Text("비우면 '\(provider.title)'"))
                        .textFieldStyle(.roundedBorder)
                }
                ForEach(provider.fields) { field in
                    GridRow {
                        Text(field.label)
                        if field.isSecret {
                            SecureField(keepsSaved(field) ? "저장됨 (변경 시에만 입력)" : field.placeholder, text: binding(field))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(save)
                        } else {
                            TextField(field.placeholder, text: binding(field))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
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
                .disabled(!canSave)
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
        .onAppear(perform: load)
    }

    private func binding(_ field: ProviderField) -> Binding<String> {
        Binding(get: { values[field.key] ?? "" }, set: { values[field.key] = $0 })
    }

    /// Fills the form from the saved connection. Secrets are never shown again.
    private func load() {
        guard let existing else { return }
        name = existing.connection.name
        values = existing.connection.values.filter { key, _ in
            provider.fields.contains { $0.key == key && !$0.isSecret }
        }
    }

    private func save() {
        guard canSave else { return }
        let saved: StoredConnection
        do {
            saved = try connections.save(
                id: savedID ?? existingID,
                provider: provider,
                name: name,
                values: values
            )
        } catch {
            status = .failure(error.localizedDescription)
            return
        }
        // Later saves edit this connection, even if the test below fails.
        savedID = saved.id
        load()
        isTesting = true
        status = .idle
        Task {
            defer { isTesting = false }
            do {
                let accounts = try await connections.test(saved.id)
                status = .success(accounts.isEmpty
                                  ? "연결되었습니다. (조회 가능한 종합매매 계좌가 없습니다)"
                                  : "연결되었습니다. 계좌 \(accounts.count)개를 찾았습니다.")
                onConnected(saved, accounts)
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}

/// The Mac-wide switch for syncing every connection through the iCloud Keychain, and an
/// offer to turn it on when another Mac has shared connections there.
struct ConnectionSyncSection: View {
    @ObservedObject var connections: ConnectionStore
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("iCloud 키체인으로 연결 동기화", isOn: Binding(
                get: { connections.syncsWithICloud },
                set: { enabled in
                    do {
                        try connections.setSync(enabled)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            ))
            .disabled(!connections.canSync)

            Group {
                if connections.syncsWithICloud {
                    Text("모든 연결과 토큰을 같은 Apple 계정의 다른 Mac 과 함께 씁니다. 끄면 지금 연결이 이 Mac 에 남고, 다른 Mac 은 iCloud 의 연결을 계속 씁니다. 각 Mac 의 공인 IP 는 따로 허용 IP 로 등록해야 합니다.")
                } else {
                    Text("켜면 이 Mac 의 모든 연결과 토큰을 iCloud 키체인으로 옮겨 같은 Apple 계정의 다른 Mac 과 함께 씁니다.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if connections.unsyncedSharedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.fill").foregroundStyle(.blue)
                    Text("다른 Mac 이 iCloud 에 공유한 연결 \(connections.unsyncedSharedCount)개가 있습니다. 동기화를 켜면 이 Mac 의 연결과 합쳐집니다.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

/// How to get a provider's API keys.
struct ProviderHelp: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch provider {
            case .tossinvest:
                Text("1. PC 웹(토스증권 WTS)에 로그인 → 설정 → Open API 에서 클라이언트를 등록합니다.")
                Text("2. 이 Mac 이 사용하는 공인 IP 를 허용 IP 로 등록해야 합니다. (미등록 시 403)")
                Text("3. 발급된 client_id / client_secret 을 입력하세요. 연결은 기본적으로 이 Mac 사용자만 읽을 수 있는 파일(~/Library/Application Support/TossBar)에 저장되며, 연결 설정에서 iCloud 동기화를 켜면 모든 연결을 다른 Mac 과 함께 쓸 수 있습니다.")
                Text("※ 토스증권은 클라이언트당 토큰을 1개만 유효하게 유지합니다. 같은 키를 다른 프로그램과 함께 쓰면 서로의 토큰이 무효화되니 Invest Stats 전용 키를 쓰는 것을 권장합니다. iCloud 로 동기화한 Mac 끼리는 토큰도 함께 공유해 이를 줄이지만, 동기화가 늦으면 잠시 오류가 날 수 있습니다.")
                    .foregroundStyle(.secondary)
                Link("토스증권 Open API 문서 열기", destination: URL(string: "https://developers.tossinvest.com/docs")!)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Item editors

/// Picks the connection an item reads from.
struct ConnectionPicker: View {
    @ObservedObject var connections: ConnectionStore
    @Binding var selection: UUID?

    var body: some View {
        Picker("연결", selection: $selection) {
            if selection.flatMap(connections.connection) == nil {
                Text("연결을 선택하세요").tag(UUID?.none)
            }
            ForEach(connections.connections) { stored in
                Text(Self.title(stored)).tag(UUID?.some(stored.id))
            }
        }
    }

    static func title(_ stored: StoredConnection) -> String {
        let connection = stored.connection
        if connection.name.nilIfBlank == nil { return connection.provider.title }
        return "\(connection.displayName) · \(connection.provider.title)"
    }
}
