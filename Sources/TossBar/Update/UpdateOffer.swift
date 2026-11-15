import Foundation

/// A release from the GitHub REST API (`GET /repos/{owner}/{repo}/releases`).
struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let downloadURL: URL
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
        }
    }

    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let pageURL: URL
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, draft, prerelease
        case pageURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    var version: SemanticVersion? { SemanticVersion(tagName) }

    /// The zipped app: `TossBar-<version>.zip`, as `scripts/release.sh` names it.
    var appArchive: Asset? {
        let expected = version.map { "TossBar-\($0).zip" }
        return assets.first { $0.name == expected }
            ?? assets.first { $0.name.hasPrefix("TossBar-") && $0.name.hasSuffix(".zip") }
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
    /// release between `current` (exclusive) and the offered one (inclusive), so a user who
    /// skipped a few versions sees all of their changes.
    static func select(
        from releases: [GitHubRelease],
        current: SemanticVersion,
        includePrereleases: Bool
    ) -> UpdateOffer? {
        let newer = releases
            .compactMap { release -> (SemanticVersion, GitHubRelease)? in
                guard !release.draft, let version = release.version, version > current else { return nil }
                if !includePrereleases, release.prerelease || version.isPrerelease { return nil }
                return (version, release)
            }
            .sorted { $0.0 > $1.0 }

        // A release whose archive is still uploading is skipped until the next check.
        guard let index = newer.firstIndex(where: { $0.1.appArchive != nil }) else { return nil }
        let (version, release) = newer[index]
        let notes = newer[index...].map { version, release in
            Note(version: version, body: release.body ?? "", pageURL: release.pageURL, publishedAt: release.publishedAt)
        }
        return UpdateOffer(version: version, archive: release.appArchive!, pageURL: release.pageURL, notes: notes)
    }
}
