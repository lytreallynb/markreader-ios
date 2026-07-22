import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Renders Markdown to HTML with cmark-gfm.
/// Emits data-sourcepos attributes on block elements so the preview can map
/// selections back to source line ranges, and passes raw HTML through so
/// <mark> highlights survive.
enum MarkdownHTMLRenderer {
    // cmark option bits, mirrored from cmark-gfm.h because the C macros
    // do not import into Swift.
    private static let optSourcePos: Int32 = 1 << 1
    private static let optValidateUTF8: Int32 = 1 << 9
    private static let optFootnotes: Int32 = 1 << 13
    private static let optUnsafe: Int32 = 1 << 17

    private static let options = optSourcePos | optValidateUTF8 | optFootnotes | optUnsafe
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]

    static func renderBody(from markdown: String) -> String {
        let processed = expandHighlightSyntax(in: markdown)

        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        var body = ""
        processed.withCString { cString in
            cmark_parser_feed(parser, cString, strlen(cString))
            guard let document = cmark_parser_finish(parser) else { return }
            defer { cmark_node_free(document) }

            guard let html = cmark_render_html(
                document, options, cmark_parser_get_syntax_extensions(parser)
            ) else { return }
            defer { free(html) }
            body = String(cString: html)
        }
        return body
    }

    /// Converts ==text== to <mark>text</mark> outside fenced code blocks and
    /// inline code spans, so the common highlight syntax renders with color.
    static func expandHighlightSyntax(in markdown: String) -> String {
        var output: [String] = []
        var inFence = false
        var fenceMarker = ""

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inFence {
                output.append(line)
                if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                fenceMarker = String(trimmed.prefix(3))
                output.append(line)
                continue
            }
            output.append(expandHighlightsOutsideInlineCode(in: line))
        }
        return output.joined(separator: "\n")
    }

    private static func expandHighlightsOutsideInlineCode(in line: String) -> String {
        guard line.contains("==") else { return line }

        var result = ""
        var plainRun = ""
        let chars = Array(line)
        var i = 0

        func flushPlain() {
            result += expandHighlights(in: plainRun)
            plainRun = ""
        }

        while i < chars.count {
            guard chars[i] == "`" else {
                plainRun.append(chars[i])
                i += 1
                continue
            }

            var openRun = 0
            var j = i
            while j < chars.count, chars[j] == "`" {
                openRun += 1
                j += 1
            }

            var closeEnd: Int?
            var k = j
            while k < chars.count {
                if chars[k] == "`" {
                    var run = 0
                    var n = k
                    while n < chars.count, chars[n] == "`" {
                        run += 1
                        n += 1
                    }
                    if run == openRun {
                        closeEnd = n
                        break
                    }
                    k = n
                } else {
                    k += 1
                }
            }

            if let closeEnd {
                flushPlain()
                result += String(chars[i..<closeEnd])
                i = closeEnd
            } else {
                plainRun.append(contentsOf: chars[i..<j])
                i = j
            }
        }
        flushPlain()
        return result
    }

    private static let highlightPattern = try! NSRegularExpression(
        pattern: "==([^=\\n](?:[^\\n]*?[^=\\n])?)=="
    )

    private static func expandHighlights(in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return highlightPattern.stringByReplacingMatches(
            in: text, range: range, withTemplate: "<mark>$1</mark>"
        )
    }
}
