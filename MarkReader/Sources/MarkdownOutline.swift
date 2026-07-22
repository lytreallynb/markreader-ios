import Foundation

/// Shares the open document's headings between the reader and the sidebar,
/// and carries the jump action back to the reader's preview.
@MainActor
final class OutlineContext: ObservableObject {
    @Published var headings: [OutlineHeading] = []
    var jumpHandler: ((Int) -> Void)?

    func jump(toLine line: Int) {
        jumpHandler?(line)
    }
}

/// A heading in the document, used for the outline jump menu.
struct OutlineHeading: Identifiable, Hashable {
    let level: Int
    let title: String
    let line: Int

    var id: Int { line }
}

enum MarkdownOutline {
    private static let headingPattern = try! NSRegularExpression(
        pattern: "^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$"
    )

    /// Parses ATX headings outside fenced code blocks.
    /// Line numbers are 1-based to match cmark sourcepos.
    static func headings(in markdown: String) -> [OutlineHeading] {
        var result: [OutlineHeading] = []
        var inFence = false
        var fenceMarker = ""

        for (index, line) in markdown.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inFence {
                if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                fenceMarker = String(trimmed.prefix(3))
                continue
            }

            let nsLine = trimmed as NSString
            guard let match = headingPattern.firstMatch(
                in: trimmed, range: NSRange(location: 0, length: nsLine.length)
            ) else { continue }

            let level = match.range(at: 1).length
            var title = nsLine.substring(with: match.range(at: 2))
            title = stripInlineMarkup(from: title)
            guard !title.isEmpty else { continue }
            result.append(OutlineHeading(level: level, title: title, line: index + 1))
        }
        return result
    }

    private static let markupPattern = try! NSRegularExpression(
        pattern: "[*_`~]|==|<[^>]+>"
    )

    private static func stripInlineMarkup(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return markupPattern
            .stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Footnote helpers for the note feature.
enum MarkdownNotes {
    private static let notePattern = try! NSRegularExpression(
        pattern: "\\[\\^n(\\d+)\\]"
    )

    /// Returns the next unused note label, scanning existing [^nX] references.
    static func nextLabel(in markdown: String) -> String {
        let nsSource = markdown as NSString
        var highest = 0
        notePattern.enumerateMatches(
            in: markdown, range: NSRange(location: 0, length: nsSource.length)
        ) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let value = Int(nsSource.substring(with: match.range(at: 1)))
            else { return }
            highest = max(highest, value)
        }
        return "n\(highest + 1)"
    }

    /// Appends the footnote definition for a label at the end of the document.
    static func appendDefinition(
        to markdown: String, label: String, note: String
    ) -> String {
        let cleanNote = note
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        var result = markdown
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        result += "\n[^\(label)]: \(cleanNote)\n"
        return result
    }
}
