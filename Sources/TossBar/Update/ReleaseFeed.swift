import Foundation

/// Reads the repository's release Atom feed (`https://github.com/{owner}/{repo}/releases.atom`).
///
/// The feed is served by github.com, not the REST API, so it doesn't count against the API's
/// limit of 60 unauthenticated requests per hour, which every client behind the same public IP
/// shares. It holds only the 10 newest releases, without drafts or assets, and its notes are HTML.
enum ReleaseFeed {
    /// The releases in the feed, newest first. Entries whose tag can't be read are dropped.
    static func parse(_ data: Data) throws -> [GitHubRelease] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw UpdateError.feed }
        return delegate.entries.compactMap { entry in
            guard let pageURL = entry.link.flatMap(URL.init(string:)) else { return nil }
            let tag = pageURL.deletingLastPathComponent().lastPathComponent == "tag"
                ? pageURL.lastPathComponent
                : entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard SemanticVersion(tag) != nil else { return nil }
            return GitHubRelease(
                tagName: tag,
                body: ReleaseNoteHTML.markdown(from: entry.content),
                pageURL: pageURL,
                publishedAt: ISO8601DateFormatter().date(from: entry.updated.trimmingCharacters(in: .whitespacesAndNewlines)),
                assets: []
            )
        }
    }
}

private final class FeedParser: NSObject, XMLParserDelegate {
    struct Entry {
        var title = ""
        var link: String?
        var updated = ""
        var content = ""
    }

    private(set) var entries: [Entry] = []
    private var entry: Entry?
    private var field: String?

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        switch name {
        case "entry":
            entry = Entry()
        case "link":
            if attributes["rel"] ?? "alternate" == "alternate" { entry?.link = attributes["href"] }
        case "title", "updated", "content":
            if entry != nil { field = name }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch field {
        case "title": entry?.title += string
        case "updated": entry?.updated += string
        case "content": entry?.content += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        self.parser(parser, foundCharacters: String(decoding: data, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == field { field = nil }
        if name == "entry", let entry {
            entries.append(entry)
            self.entry = nil
        }
    }
}

/// Turns the HTML of a release note back into the Markdown subset `ReleaseNoteBlock` reads:
/// headings, nested bullet lists and paragraphs, with bold, italics, code and links inline.
/// Other tags are dropped and their text kept.
enum ReleaseNoteHTML {
    static func markdown(from html: String) -> String {
        var writer = Writer()
        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<" else {
                let next = html[index...].firstIndex(of: "<") ?? html.endIndex
                writer.text(String(html[index..<next]))
                index = next
                continue
            }
            guard let close = html[index...].firstIndex(of: ">") else {
                writer.text(String(html[index...]))
                break
            }
            writer.tag(String(html[html.index(after: index)..<close]))
            index = html.index(after: close)
        }
        return writer.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Writer {
        var output = ""
        private var listDepth = 0
        private var links: [String?] = []
        private var inCode = false

        mutating func tag(_ raw: String) {
            let closing = raw.hasPrefix("/")
            let body = closing ? raw.dropFirst() : Substring(raw)
            let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()

            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                blankLine()
                if !closing { output += String(repeating: "#", count: Int(name.dropFirst())!) + " " }
            case "p", "div", "pre", "blockquote", "hr", "table", "tr":
                blankLine()
            case "ul", "ol":
                newline()
                listDepth = max(0, listDepth + (closing ? -1 : 1))
                if closing, listDepth == 0 { blankLine() }
            case "li":
                newline()
                if !closing { output += String(repeating: "  ", count: max(0, listDepth - 1)) + "* " }
            case "br":
                output += " "
            case "strong", "b":
                output += "**"
            case "em", "i":
                output += "*"
            case "code":
                output += "`"
                inCode = !closing
            case "a":
                if closing {
                    if let href = links.popLast() ?? nil { output += "](\(href))" }
                } else {
                    let href = Self.attribute("href", in: body).map(Self.decodeEntities)
                    let target = href.map { $0.contains { " ()<>".contains($0) } ? "<\($0)>" : $0 }
                    links.append(target)
                    if target != nil { output += "[" }
                }
            default:
                break
            }
        }

        mutating func text(_ raw: String) {
            var text = Self.decodeEntities(raw)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if raw.first?.isWhitespace == true { text = " " + text }
            if raw.last?.isWhitespace == true, !text.hasSuffix(" ") { text += " " }
            if output.isEmpty || output.hasSuffix("\n") || output.hasSuffix(" ") {
                text = String(text.drop { $0 == " " })
            }
            guard !text.isEmpty else { return }
            output += inCode ? text : Self.escape(text)
        }

        private mutating func newline() {
            while output.hasSuffix(" ") { output.removeLast() }
            if !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
        }

        private mutating func blankLine() {
            newline()
            if !output.isEmpty, !output.hasSuffix("\n\n") { output += "\n" }
        }

        private static func escape(_ text: String) -> String {
            var escaped = ""
            for character in text {
                if "\\*_`[]".contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
            return escaped
        }

        private static func attribute(_ name: String, in tag: Substring) -> String? {
            guard let match = tag.range(of: #"\b\#(name)\s*=\s*("[^"]*"|'[^']*')"#, options: .regularExpression) else {
                return nil
            }
            let value = tag[match].drop { $0 != "\"" && $0 != "'" }
            return String(value.dropFirst().dropLast())
        }

        private static let namedEntities: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        ]

        static func decodeEntities(_ text: String) -> String {
            guard text.contains("&") else { return text }
            var result = ""
            var rest = Substring(text)
            while let ampersand = rest.firstIndex(of: "&") {
                result += rest[..<ampersand]
                let after = rest[rest.index(after: ampersand)...]
                if let semicolon = after.prefix(10).firstIndex(of: ";"),
                   let decoded = decodeEntity(after[..<semicolon]) {
                    result += decoded
                    rest = after[after.index(after: semicolon)...]
                } else {
                    result += "&"
                    rest = after
                }
            }
            return result + rest
        }

        private static func decodeEntity(_ name: Substring) -> String? {
            if let named = namedEntities[String(name)] { return named }
            guard name.hasPrefix("#") else { return nil }
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
    }
}
