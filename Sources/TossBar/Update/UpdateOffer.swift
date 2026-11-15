import Foundation

/// A published release of this repository, as read from its Atom feed (`ReleaseFeed`).
struct GitHubRelease: Equatable {
    struct Asset: Equatable {
        let name: String
        let downloadURL: URL
        /// In bytes, or 0 when unknown.
        let size: Int
    }

    let tagName: String
    /// Markdown.
    let body: String?
    let pageURL: URL
    let publishedAt: Date?
    /// Filled in only for a release whose archive was found to exist.
    var assets: [Asset]

    var version: SemanticVersion? { SemanticVersion(tagName) }

    /// The zipped app: `InvestStats-<version>.zip`, as `scripts/release.sh` names it.
    var appArchive: Asset? {
        let expected = version.map(Self.archiveName)
        return assets.first { $0.name == expected }
            ?? assets.first { $0.name.hasPrefix("InvestStats-") && $0.name.hasSuffix(".zip") }
    }

    static func archiveName(for version: SemanticVersion) -> String {
        "InvestStats-\(version).zip"
    }

    /// Where GitHub serves the archive of the release tagged `tag` in `repository`.
    static func archiveURL(repository: String, tag: String, version: SemanticVersion) -> URL {
        URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(archiveName(for: version))")!
    }
}

/// A newer release to offer the user, with the notes of every release since the current one.
struct UpdateOffer: Equatable, Identifiable {
    struct Note: Equatable, Identifiable {
        let version: SemanticVersion
        let body: String
        let pageURL: URL
        let publishedAt: Date?
        var id: String { version.description }
    }

    let version: SemanticVersion
    let archive: GitHubRelease.Asset
    let pageURL: URL
    /// Newest first.
    let notes: [Note]

    var id: String { version.description }

    /// The newest release above `current` that has an app archive, or nil when there is none.
    /// Prereleases count only when `includePrereleases` is on. The notes cover every eligible
    /// release between `current` (exclusive) and the offered one (inclusive) that `releases`
    /// holds, so a user who skipped a few versions sees their changes.
    static func select(
        from releases: [GitHubRelease],
        current: SemanticVersion,
        includePrereleases: Bool
    ) -> UpdateOffer? {
        let newer = candidates(from: releases, current: current, includePrereleases: includePrereleases)
        // A release whose archive is still uploading is skipped until the next check.
        guard let index = newer.firstIndex(where: { $0.1.appArchive != nil }) else { return nil }
        let (version, release) = newer[index]
        let notes = newer[index...].map { version, release in
            Note(version: version, body: release.body ?? "", pageURL: release.pageURL, publishedAt: release.publishedAt)
        }
        return UpdateOffer(version: version, archive: release.appArchive!, pageURL: release.pageURL, notes: notes)
    }

    /// The releases above `current` that may be offered, newest first. Prereleases count only
    /// when `includePrereleases` is on.
    static func candidates(
        from releases: [GitHubRelease],
        current: SemanticVersion,
        includePrereleases: Bool
    ) -> [(SemanticVersion, GitHubRelease)] {
        releases
            .compactMap { release -> (SemanticVersion, GitHubRelease)? in
                guard let version = release.version, version > current else { return nil }
                if !includePrereleases, version.isPrerelease { return nil }
                return (version, release)
            }
            .sorted { $0.0 > $1.0 }
    }
}
