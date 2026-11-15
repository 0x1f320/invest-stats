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
    private func release(_ tag: String, notes: String? = nil, archive: Bool = true) -> GitHubRelease {
        let version = SemanticVersion(tag)
        return GitHubRelease(
            tagName: tag,
            body: notes,
            pageURL: URL(string: "https://example.com/\(tag)")!,
            publishedAt: nil,
            assets: archive && version != nil
                ? [.init(name: GitHubRelease.archiveName(for: version!), downloadURL: URL(string: "https://example.com/\(tag).zip")!, size: 10)]
                : []
        )
    }

    private func releases() -> [GitHubRelease] {
        [
            release("v1.2.0-dev.1", notes: "## dev notes"),
            release("v1.1.0", notes: "## 1.1.0 notes"),
            release("v1.1.0-dev.2"),
            release("v1.0.1", notes: "## 1.0.1 notes"),
            release("not-a-version", archive: false),
        ]
    }

    private func select(_ current: String, prereleases: Bool, from list: [GitHubRelease]? = nil) -> UpdateOffer? {
        UpdateOffer.select(from: list ?? releases(), current: SemanticVersion(current)!, includePrereleases: prereleases)
    }

    @Test func archiveLocation() {
        let version = SemanticVersion("1.2.0-dev.1")!
        #expect(GitHubRelease.archiveName(for: version) == "InvestStats-1.2.0-dev.1.zip")
        #expect(
            GitHubRelease.archiveURL(repository: "owner/repo", tag: "v1.2.0-dev.1", version: version)
                == URL(string: "https://github.com/owner/repo/releases/download/v1.2.0-dev.1/InvestStats-1.2.0-dev.1.zip")
        )
    }

    @Test func stableChannelSkipsPrereleases() throws {
        let offer = try #require(select("1.0.0", prereleases: false))
        #expect(offer.version.description == "1.1.0")
        #expect(offer.archive.name == "InvestStats-1.1.0.zip")
        #expect(offer.notes.map(\.version.description) == ["1.1.0", "1.0.1"])
    }

    @Test func prereleaseChannelTakesNewest() throws {
        let offer = try #require(select("1.0.0", prereleases: true))
        #expect(offer.version.description == "1.2.0-dev.1")
        #expect(offer.notes.map(\.version.description) == ["1.2.0-dev.1", "1.1.0", "1.1.0-dev.2", "1.0.1"])
    }

    @Test func prereleaseBuildMovesToItsRelease() throws {
        // On 1.1.0-dev.2 without prereleases, the stable 1.1.0 is newer.
        let offer = try #require(select("1.1.0-dev.2", prereleases: false))
        #expect(offer.version.description == "1.1.0")
        #expect(offer.notes.map(\.version.description) == ["1.1.0"])
    }

    @Test func upToDate() {
        #expect(select("1.2.0-dev.1", prereleases: true) == nil)
        #expect(select("1.1.0", prereleases: false) == nil)
        // Never offers a downgrade.
        #expect(select("2.0.0", prereleases: true) == nil)
    }

    @Test func skipsReleaseWithoutArchive() throws {
        var list = releases()
        list[1] = release("v1.1.0", notes: "uploading", archive: false)
        let offer = try #require(select("1.0.0", prereleases: false, from: list))
        #expect(offer.version.description == "1.0.1")
    }

    @Test func candidatesAreNewestFirst() {
        let list = releases().reversed().map { $0 }
        let current = SemanticVersion("1.0.0")!
        #expect(UpdateOffer.candidates(from: list, current: current, includePrereleases: true).map(\.0.description)
            == ["1.2.0-dev.1", "1.1.0", "1.1.0-dev.2", "1.0.1"])
        #expect(UpdateOffer.candidates(from: list, current: current, includePrereleases: false).map(\.0.description)
            == ["1.1.0", "1.0.1"])
    }
}

@Suite("Release feed")
struct ReleaseFeedTests {
    // Trimmed from github.com/<owner>/<repo>/releases.atom; the notes are escaped HTML.
    private static let feed = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xml:lang="en-US">
      <id>tag:github.com,2008:https://github.com/owner/repo/releases</id>
      <link type="text/html" rel="alternate" href="https://github.com/owner/repo/releases"/>
      <title>Release notes from repo</title>
      <updated>2026-11-15T06:49:39Z</updated>
      <entry>
        <id>tag:github.com,2008:Repository/1/v1.1.1-dev.2</id>
        <updated>2026-11-15T06:49:46Z</updated>
        <link rel="alternate" type="text/html" href="https://github.com/owner/repo/releases/tag/v1.1.1-dev.2"/>
        <title>v1.1.1-dev.2</title>
        <content type="html">&lt;h2&gt;&lt;a href=&quot;https://github.com/owner/repo/compare/v1.1.1-dev.1...v1.1.1-dev.2&quot;&gt;1.1.1-dev.2&lt;/a&gt; (2026-11-15)&lt;/h2&gt;
    &lt;h3&gt;Bug Fixes&lt;/h3&gt;
    &lt;ul&gt;
    &lt;li&gt;&lt;strong&gt;status-bar:&lt;/strong&gt; close the popover (&lt;a href=&quot;https://github.com/owner/repo/issues/40&quot; data-hovercard-type=&quot;pull_request&quot;&gt;#40&lt;/a&gt;) (&lt;a href=&quot;https://github.com/owner/repo/commit/fa08b37&quot;&gt;&lt;code&gt;fa08b37&lt;/code&gt;&lt;/a&gt;)&lt;/li&gt;
    &lt;/ul&gt;</content>
        <author><name>release[bot]</name></author>
      </entry>
      <entry>
        <id>tag:github.com,2008:Repository/1/v1.1.0</id>
        <updated>2026-11-15T06:34:26Z</updated>
        <link rel="alternate" type="text/html" href="https://github.com/owner/repo/releases/tag/v1.1.0"/>
        <title>Version one point one</title>
        <content type="html"></content>
      </entry>
      <entry>
        <id>tag:github.com,2008:Repository/1/nightly</id>
        <updated>2026-11-14T00:00:00Z</updated>
        <link rel="alternate" type="text/html" href="https://github.com/owner/repo/releases/tag/nightly"/>
        <title>nightly</title>
        <content type="html">&lt;p&gt;not a version&lt;/p&gt;</content>
      </entry>
    </feed>
    """#

    @Test func parsesEntries() throws {
        let releases = try ReleaseFeed.parse(Data(Self.feed.utf8))
        // The tag comes from the release page link, not the title; tags that aren't versions are dropped.
        #expect(releases.map(\.tagName) == ["v1.1.1-dev.2", "v1.1.0"])
        #expect(releases[0].pageURL == URL(string: "https://github.com/owner/repo/releases/tag/v1.1.1-dev.2"))
        #expect(releases[0].publishedAt == ISO8601DateFormatter().date(from: "2026-11-15T06:49:46Z"))
        #expect(releases[0].assets.isEmpty)
        #expect(releases[1].body == "")
    }

    @Test func notesBecomeMarkdownBlocks() throws {
        let body = try #require(try ReleaseFeed.parse(Data(Self.feed.utf8)).first?.body)
        #expect(ReleaseNoteBlock.parse(body) == [
            .heading(level: 2, text: "[1.1.1-dev.2](https://github.com/owner/repo/compare/v1.1.1-dev.1...v1.1.1-dev.2) (2026-11-15)"),
            .heading(level: 3, text: "Bug Fixes"),
            .bullet(depth: 0, text: "**status-bar:** close the popover ([#40](https://github.com/owner/repo/issues/40)) ([`fa08b37`](https://github.com/owner/repo/commit/fa08b37))"),
        ])
    }

    @Test func rejectsMalformedFeed() {
        #expect(throws: UpdateError.feed) { try ReleaseFeed.parse(Data("<feed><entry>".utf8)) }
    }

    @Test func convertsNestedListsAndInlineText() {
        let html = """
        <p>Intro with <em>emphasis</em>, a_snake [bracket] &amp; &#x27;quotes&#39;.</p>
        <ul>
          <li>outer
            <ul><li><a href="https://example.com/a b">inner</a></li></ul>
          </li>
          <li>next<br>line</li>
        </ul>
        <p>after</p>
        """
        #expect(ReleaseNoteBlock.parse(ReleaseNoteHTML.markdown(from: html)) == [
            .paragraph(#"Intro with *emphasis*, a\_snake \[bracket\] & 'quotes'."#),
            .bullet(depth: 0, text: "outer"),
            .bullet(depth: 1, text: "[inner](<https://example.com/a b>)"),
            .bullet(depth: 0, text: "next line"),
            .paragraph("after"),
        ])
    }
}

@Suite("Update errors")
struct UpdateErrorTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    @Test func rateLimitNeedsTheServerToSaySo() {
        // A 403 is a rate limit only when no requests remain.
        #expect(UpdateError.forResponse(response(403), now: now) == .github(status: 403))
        #expect(UpdateError.forResponse(response(403, ["X-RateLimit-Remaining": "12"]), now: now) == .github(status: 403))
        #expect(UpdateError.forResponse(response(404), now: now) == .github(status: 404))
        #expect(UpdateError.forResponse(response(500), now: now) == .github(status: 500))
    }

    @Test func rateLimitCarriesTheRetryDate() {
        #expect(
            UpdateError.forResponse(response(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1000600"]), now: now)
                == .rateLimited(until: Date(timeIntervalSince1970: 1_000_600))
        )
        #expect(
            UpdateError.forResponse(response(429, ["Retry-After": "60", "X-RateLimit-Reset": "1000600"]), now: now)
                == .rateLimited(until: now.addingTimeInterval(60))
        )
        #expect(UpdateError.forResponse(response(429), now: now) == .rateLimited(until: nil))
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
