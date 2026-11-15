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
        let includePrereleases = includesPrereleases
        do {
            let releases = try await Self.fetchReleases(current: currentVersion, includePrereleases: includePrereleases)
            guard let found = UpdateOffer.select(
                from: releases, current: currentVersion, includePrereleases: includePrereleases
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

    /// Reads the releases from the repository's Atom feed and finds the archive of the newest
    /// one that may be offered. Everything comes from github.com rather than the REST API, whose
    /// 60 unauthenticated requests per hour are shared by every client behind the same IP.
    ///
    /// The feed holds only the 10 newest releases, so notes reach back at most that far. When it
    /// has no stable release at all (a run of prereleases), the latest stable one is found
    /// through the `releases/latest` redirect so the stable channel still sees it.
    private static func fetchReleases(current: SemanticVersion, includePrereleases: Bool) async throws -> [GitHubRelease] {
        let feedURL = URL(string: "https://github.com/\(repository)/releases.atom")!
        let (data, _) = try await send(feedURL, method: "GET", accept: "application/atom+xml")
        var releases = try ReleaseFeed.parse(data)

        if !includePrereleases,
           !releases.contains(where: { $0.version?.isPrerelease == false }),
           let latest = try await latestStableRelease(),
           !releases.contains(where: { $0.version == latest.version }) {
            releases.append(latest)
        }

        // A release whose archive is still uploading is passed over for the next newest.
        for (version, release) in UpdateOffer.candidates(from: releases, current: current, includePrereleases: includePrereleases) {
            guard let archive = try await findArchive(of: release, version: version) else { continue }
            if let index = releases.firstIndex(of: release) { releases[index].assets = [archive] }
            break
        }
        return releases
    }

    /// The latest stable release, which `github.com/{repo}/releases/latest` redirects to,
    /// without notes. Nil when the repository has none.
    private static func latestStableRelease() async throws -> GitHubRelease? {
        let (_, response) = try await send(URL(string: "https://github.com/\(repository)/releases/latest")!, method: "HEAD")
        guard let pageURL = response.url,
              pageURL.deletingLastPathComponent().lastPathComponent == "tag",
              SemanticVersion(pageURL.lastPathComponent) != nil
        else { return nil }
        return GitHubRelease(tagName: pageURL.lastPathComponent, body: nil, pageURL: pageURL, publishedAt: nil, assets: [])
    }

    /// The release's app archive, or nil while it hasn't been uploaded.
    private static func findArchive(of release: GitHubRelease, version: SemanticVersion) async throws -> GitHubRelease.Asset? {
        let url = GitHubRelease.archiveURL(repository: repository, tag: release.tagName, version: version)
        do {
            let (_, response) = try await send(url, method: "HEAD")
            return GitHubRelease.Asset(
                name: GitHubRelease.archiveName(for: version),
                downloadURL: url,
                size: max(0, Int(response.expectedContentLength))
            )
        } catch UpdateError.github(status: 404) {
            return nil
        }
    }

    private static func send(_ url: URL, method: String, accept: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        request.setValue("InvestStats/\(AppVersion.release?.description ?? AppVersion.shortVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UpdateError.github(status: 0) }
        guard http.statusCode == 200 else { throw UpdateError.forResponse(http) }
        return (data, http)
    }
}
