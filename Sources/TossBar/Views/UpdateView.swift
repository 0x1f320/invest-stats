import SwiftUI

/// The update window: what's new since the current version, and the install controls.
struct UpdateView: View {
    @ObservedObject var updater: Updater
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let offer = updater.offer {
                header(offer)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(offer.notes) { ReleaseNoteView(note: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(height: 280)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                footer(offer)
            } else {
                Text("사용 가능한 업데이트가 없습니다.").foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("닫기", action: close).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func header(_ offer: UpdateOffer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("새 버전의 Invest Stats 가 있습니다").font(.title3.weight(.semibold))
                    if offer.version.isPrerelease {
                        Text("프리릴리스")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text("Invest Stats \(offer.version.description) 을 설치할 수 있습니다. 현재 버전은 \(updater.currentVersion?.description ?? AppVersion.shortVersion) 입니다.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func footer(_ offer: UpdateOffer) -> some View {
        switch updater.installState {
        case .downloading(let fraction):
            progress("내려받는 중…", fraction: fraction)
        case .installing:
            progress("설치 중… 완료되면 Invest Stats 가 다시 실행됩니다.", fraction: nil)
        case .idle, .failed:
            VStack(alignment: .leading, spacing: 10) {
                if case .failed(let message) = updater.installState {
                    Text(message).font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("이 버전 건너뛰기") {
                        updater.skipOffer()
                        close()
                    }
                    Link("릴리스 페이지", destination: offer.pageURL)
                    Spacer()
                    Button("나중에", action: close).keyboardShortcut(.cancelAction)
                    Button(updater.installState == .idle ? "업데이트" : "다시 시도") { updater.install() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func progress(_ title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct ReleaseNoteView: View {
    let note: UpdateOffer.Note

    var body: some View {
        let blocks = ReleaseNoteBlock.parse(note.body)
        VStack(alignment: .leading, spacing: 5) {
            // semantic-release notes start with their own version heading.
            if blocks.first.map(isHeading) != true {
                Text(note.version.description).font(.headline)
            }
            if blocks.isEmpty {
                Text("릴리스 노트가 없습니다.").foregroundStyle(.secondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(inline(text))
                        .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                        .padding(.top, level <= 2 ? 0 : 4)
                case .bullet(let depth, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                case .paragraph(let text):
                    Text(inline(text)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func isHeading(_ block: ReleaseNoteBlock) -> Bool {
        if case .heading = block { return true }
        return false
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// The update tab of the settings window.
struct UpdateSettingsView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section {
                LabeledContent("현재 버전") {
                    Text(updater.currentVersion?.description ?? "\(AppVersion.shortVersion) (로컬 빌드)")
                        .textSelection(.enabled)
                }
                if updater.isSupported {
                    HStack(spacing: 8) {
                        Button("지금 업데이트 확인") {
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(updater.checkState == .checking || updater.installState.isBusy)
                        status
                    }
                } else {
                    Text("로컬 빌드는 자동 업데이트를 지원하지 않습니다. GitHub Releases 의 릴리스 빌드를 설치하면 업데이트를 받을 수 있습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if updater.isSupported {
                Section {
                    Toggle("자동으로 업데이트 확인", isOn: $updater.automaticallyChecks)
                    Text("실행할 때와 30분마다 GitHub Releases 에서 새 버전을 확인하고, 있으면 변경 사항과 함께 알려 줍니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("프리릴리스 받기", isOn: $updater.includesPrereleases)
                    Text("dev 브랜치에서 빌드되어 아직 정식 릴리스에 포함되지 않은 변경이 들어 있는 버전(예: 1.2.0-dev.1)도 받습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Link("GitHub Releases 열기", destination: Updater.releasesPage)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(10)
    }

    @ViewBuilder
    private var status: some View {
        switch updater.checkState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
            Text("확인 중…").font(.callout).foregroundStyle(.secondary)
        case .upToDate:
            Text("최신 버전입니다.").font(.callout).foregroundStyle(.secondary)
        case .found:
            if let offer = updater.offer {
                Text("새 버전 \(offer.version.description)").font(.callout)
                Button("보기") { updater.presentOffer() }
            }
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2).help(message)
        }
    }
}
