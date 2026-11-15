import Foundation

enum AppVersion {
    /// Info.plist key with the full release version, such as `1.2.0-dev.3`. Only release builds
    /// have it (`scripts/release.sh` sets it); `CFBundleShortVersionString` drops the suffix.
    static let releaseVersionKey = "TossBarReleaseVersion"

    static var release: SemanticVersion? {
        (Bundle.main.object(forInfoDictionaryKey: releaseVersionKey) as? String).flatMap(SemanticVersion.init)
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

/// Checks this repository's GitHub Releases for a newer build and installs it.
/// Release builds only: a local build has no release version to compare.
@MainActor
final class Updater: ObservableObject {
    enum CheckState: Equatable {
        case idle, checking, upToDate, found, failed(String)
    }

    enum InstallState: Equatable {
        case idle, downloading(Double?), installing, failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .installing: return true
            case .idle, .failed: return false
            }
        }
    }

    static let repository = "0x1f320/invest-stats"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
    private static let checkInterval: Duration = .seconds(30 * 60)
    private static let launchDelay: Duration = .seconds(5)

    private enum Key {
        static let automaticallyChecks = "updateAutomaticallyChecks"
        static let includesPrereleases = "updateIncludesPrereleases"
        static let skippedVersion = "updateSkippedVersion"
    }

    let currentVersion: SemanticVersion?
    var isSupported: Bool { currentVersion != nil }

    /// Check at launch and every 30 minutes.
    @Published var automaticallyChecks: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecks, forKey: Key.automaticallyChecks)
            schedule()
        }
    }
    /// Also offer prereleases built from `dev`.
    @Published var includesPrereleases: Bool {
        didSet {
            UserDefaults.standard.set(includesPrereleases, forKey: Key.includesPrereleases)
            if !installState.isBusy {
                offer = nil
                checkState = .idle
            }
        }
    }
    @Published private(set) var checkState: CheckState = .idle
    @Published private(set) var installState: InstallState = .idle
    /// The update found by the last check.
    @Published private(set) var offer: UpdateOffer?

    /// Shows the update window.
    var presentOffer: () -> Void = {}

    private var scheduled: Task<Void, Never>?

    init(currentVersion: SemanticVersion? = AppVersion.release) {
        self.currentVersion = currentVersion
        let defaults = UserDefaults.standard
        // A prerelease build subscribes to prereleases until the user says otherwise. Stored
        // right away, so updating to a stable release doesn't silently change the choice.
        if defaults.object(forKey: Key.includesPrereleases) == nil, let currentVersion {
            defaults.set(currentVersion.isPrerelease, forKey: Key.includesPrereleases)
        }
        defaults.register(defaults: [Key.automaticallyChecks: true, Key.includesPrereleases: false])
        automaticallyChecks = defaults.bool(forKey: Key.automaticallyChecks)
        includesPrereleases = defaults.bool(forKey: Key.includesPrereleases)
    }

    func start() {
        schedule()
    }

    private func schedule() {
        scheduled?.cancel()
        scheduled = nil
        guard isSupported, automaticallyChecks else { return }
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                await self?.check(userInitiated: false)
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// Looks for a newer release. An automatic check stays quiet on errors and doesn't
    /// bring up a version the user chose to skip.
    func check(userInitiated: Bool) async {
        guard let currentVersion, checkState != .checking, !installState.isBusy else { return }
        checkState = .checking
        do {
            let releases = try await Self.fetchReleases()
            guard let found = UpdateOffer.select(
                from: releases, current: currentVersion, includePrereleases: includesPrereleases
            ) else {
                offer = nil
                checkState = .upToDate
                return
            }
            let isNew = found != offer
            offer = found
            if case .failed = installState { installState = .idle }
            checkState = .found
            let skipped = UserDefaults.standard.string(forKey: Key.skippedVersion)
            if userInitiated || (isNew && found.version.description != skipped) {
                presentOffer()
            }
        } catch {
            checkState = .failed(error.localizedDescription)
        }
    }

    func skipOffer() {
        guard let offer else { return }
        UserDefaults.standard.set(offer.version.description, forKey: Key.skippedVersion)
    }

    /// Downloads, checks and installs the offered release, then relaunches.
    func install() {
        guard let offer, !installState.isBusy else { return }
        let appURL = Bundle.main.bundleURL
        installState = .downloading(nil)
        Task {
            var archive: URL?
            do {
                archive = try await UpdateInstaller.download(offer, replacing: appURL) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.installState else { return }
                        self.installState = .downloading(fraction)
                    }
                }
                installState = .installing
                let newApp = try await UpdateInstaller.unpack(archive!, expecting: offer.version)
                try UpdateInstaller.replace(appURL, with: newApp)
                UpdateInstaller.removeScratch(for: archive!)
                UpdateInstaller.relaunch(appURL)
            } catch {
                if let archive { UpdateInstaller.removeScratch(for: archive) }
                installState = .failed(error.localizedDescription)
            }
        }
    }

    private static func fetchReleases() async throws -> [GitHubRelease] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("InvestStats/\(AppVersion.release?.description ?? AppVersion.shortVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.github(status: status) }
        return try GitHubRelease.makeDecoder().decode([GitHubRelease].self, from: data)
    }
}
