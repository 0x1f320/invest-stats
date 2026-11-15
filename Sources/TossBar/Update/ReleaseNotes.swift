import Foundation

/// The block structure of a release note, enough for what semantic-release writes:
/// headings, bullet lists and plain paragraphs. Inline Markdown (links, bold, code)
/// stays in the text and is rendered by `AttributedString`.
enum ReleaseNoteBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(depth: Int, text: String)
    case paragraph(String)

    static func parse(_ markdown: String) -> [ReleaseNoteBlock] {
        var blocks: [ReleaseNoteBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flushParagraph()
                let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: hashes, text: text))
                continue
            }

            if let marker = trimmed.first, "*-+".contains(marker), trimmed.dropFirst().first == " " {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                    .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                blocks.append(.bullet(depth: indent / 2, text: text))
                continue
            }

            paragraph.append(trimmed)
        }
        flushParagraph()
        return blocks
    }
}
