import Foundation
import Testing
@testable import TossBar

@Suite("Semantic versions")
struct SemanticVersionTests {
    private func v(_ string: String) -> SemanticVersion { SemanticVersion(string)! }

    @Test func parses() {
        #expect(v("1.2.3").description == "1.2.3")
        #expect(v("v1.2.3-dev.4").description == "1.2.3-dev.4")
        #expect(v("1.2.3+build.5").description == "1.2.3")
        #expect(v("1.2.3-dev.4").prerelease == ["dev", "4"])
        #expect(v("1.2.3-dev.4").isPrerelease)
        #expect(!v("1.2.3").isPrerelease)
    }

    @Test func rejectsInvalid() {
        for bad in ["", "1.2", "1.2.3.4", "a.b.c", "1.2.3-", "1.2.3-dev..1", "1.-2.3", "latest"] {
            #expect(SemanticVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func precedence() {
        // The order from the Semantic Versioning spec, plus this repository's dev channel.
        let ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
            "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0-dev.1", "1.1.0-dev.2",
            "1.1.0-dev.10", "1.1.0", "2.0.0",
        ].map(v)
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            #expect(lower < higher, "\(lower) < \(higher)")
            #expect(!(higher < lower), "\(higher) !< \(lower)")
        }
        #expect(v("v1.2.3") == v("1.2.3+meta"))
    }
}

@Suite("Update selection")
struct UpdateOfferTests {
    private static let releasesJSON = #"""
    [
      {
        "tag_name": "v1.2.0-dev.1", "body": "## dev notes", "draft": false, "prerelease": true,
        "html_url": "https://example.com/v1.2.0-dev.1", "published_at": "2026-11-20T00:00:00Z",
        "assets": [{"name": "InvestStats-1.2.0-dev.1.zip", "browser_download_url": "https://example.com/dev1.zip", "size": 10}]
      },
      {
        "tag_name": "v1.1.0", "body": "## 1.1.0 notes", "draft": false, "prerelease": false,
        "html_url": "https://example.com/v1.1.0", "published_at": "2026-11-18T00:00:00Z",
        "assets": [{"name": "InvestStats-1.1.0.zip", "browser_download_url": "https://example.com/110.zip", "size": 20}]
      },
      {
        "tag_name": "v1.1.0-dev.2", "body": null, "draft": false, "prerelease": true,
        "html_url": "https://example.com/v1.1.0-dev.2", "published_at": null,
        "assets": [{"name": "InvestStats-1.1.0-dev.2.zip", "browser_download_url": "https://example.com/dev2.zip", "size": 30}]
      },
      {
        "tag_name": "v1.0.1", "body": "## 1.0.1 notes", "draft": false, "prerelease": false,
        "html_url": "https://example.com/v1.0.1", "published_at": "2026-11-16T00:00:00Z",
        "assets": [{"name": "InvestStats-1.0.1.zip", "browser_download_url": "https://example.com/101.zip", "size": 40}]
      },
      {
        "tag_name": "v9.0.0", "body": "draft", "draft": true, "prerelease": false,
        "html_url": "https://example.com/v9.0.0", "published_at": null,
        "assets": [{"name": "InvestStats-9.0.0.zip", "browser_download_url": "https://example.com/900.zip", "size": 50}]
      },
      {
        "tag_name": "not-a-version", "body": "", "draft": false, "prerelease": false,
        "html_url": "https://example.com/x", "published_at": null, "assets": []
      }
    ]
    """#

    private func releases() throws -> [GitHubRelease] {
        try GitHubRelease.makeDecoder().decode([GitHubRelease].self, from: Data(Self.releasesJSON.utf8))
    }

    private func select(_ current: String, prereleases: Bool, from list: [GitHubRelease]? = nil) throws -> UpdateOffer? {
        UpdateOffer.select(from: try list ?? releases(), current: SemanticVersion(current)!, includePrereleases: prereleases)
    }

    @Test func decodesGitHubReleases() throws {
        let list = try releases()
        #expect(list.count == 6)
        #expect(list[0].appArchive?.downloadURL == URL(string: "https://example.com/dev1.zip"))
        #expect(list[0].publishedAt != nil)
        #expect(list[2].body == nil)
    }

    @Test func stableChannelSkipsPrereleases() throws {
        let offer = try #require(try select("1.0.0", prereleases: false))
        #expect(offer.version.description == "1.1.0")
        #expect(offer.archive.name == "InvestStats-1.1.0.zip")
        #expect(offer.notes.map(\.version.description) == ["1.1.0", "1.0.1"])
    }

    @Test func prereleaseChannelTakesNewest() throws {
        let offer = try #require(try select("1.0.0", prereleases: true))
        #expect(offer.version.description == "1.2.0-dev.1")
        #expect(offer.notes.map(\.version.description) == ["1.2.0-dev.1", "1.1.0", "1.1.0-dev.2", "1.0.1"])
    }

    @Test func prereleaseBuildMovesToItsRelease() throws {
        // On 1.1.0-dev.2 without prereleases, the stable 1.1.0 is newer.
        let offer = try #require(try select("1.1.0-dev.2", prereleases: false))
        #expect(offer.version.description == "1.1.0")
        #expect(offer.notes.map(\.version.description) == ["1.1.0"])
    }

    @Test func upToDate() throws {
        #expect(try select("1.2.0-dev.1", prereleases: true) == nil)
        #expect(try select("1.1.0", prereleases: false) == nil)
        // Never offers a downgrade: drafts and older releases are ignored.
        #expect(try select("2.0.0", prereleases: true) == nil)
    }

    @Test func skipsReleaseWithoutArchive() throws {
        var list = try releases()
        list[1] = GitHubRelease(
            tagName: "v1.1.0", body: "uploading", draft: false, prerelease: false,
            pageURL: list[1].pageURL, publishedAt: nil, assets: []
        )
        let offer = try #require(try select("1.0.0", prereleases: false, from: list))
        #expect(offer.version.description == "1.0.1")
    }
}

@Suite("Release notes")
struct ReleaseNoteBlockTests {
    @Test func parsesSemanticReleaseNotes() {
        let body = """
        ## [1.0.0-dev.2](https://example.com/compare) (2026-11-15)

        ### Features

        * **asset:** color profit ([#13](https://example.com/13))
        * share keys
          * nested detail

        A paragraph
        over two lines.
        """
        #expect(ReleaseNoteBlock.parse(body) == [
            .heading(level: 2, text: "[1.0.0-dev.2](https://example.com/compare) (2026-11-15)"),
            .heading(level: 3, text: "Features"),
            .bullet(depth: 0, text: "**asset:** color profit ([#13](https://example.com/13))"),
            .bullet(depth: 0, text: "share keys"),
            .bullet(depth: 1, text: "nested detail"),
            .paragraph("A paragraph over two lines."),
        ])
    }

    @Test func plainTextIsNotAHeadingOrBullet() {
        #expect(ReleaseNoteBlock.parse("#hashtag\n*emphasis*\r\n") == [.paragraph("#hashtag *emphasis*")])
        #expect(ReleaseNoteBlock.parse("") == [])
    }
}
