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
        var mathStore: [String] = []
        let processed = preprocess(markdown, mathStore: &mathStore)

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

        // Math spans were masked before parsing so cmark could not mangle
        // them; restore them HTML-escaped for MathJax to typeset in place.
        for (index, math) in mathStore.enumerated() {
            body = body.replacingOccurrences(
                of: mathToken(index), with: htmlEscape(math)
            )
        }
        return body
    }

    private static func mathToken(_ index: Int) -> String {
        "\u{27E6}MJ\(index)\u{27E7}"
    }

    private static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Fence-aware preprocessing of non-code regions: masks TeX math,
    /// converts [[wiki links]] to inkdown-wiki links, and expands ==text==
    /// highlights.
    private static func preprocess(
        _ markdown: String, mathStore: inout [String]
    ) -> String {
        var output: [String] = []
        var nonCodeBuffer: [String] = []
        var inFence = false
        var fenceMarker = ""

        func flushNonCode() {
            guard !nonCodeBuffer.isEmpty else { return }
            var segment = nonCodeBuffer.joined(separator: "\n")
            segment = maskMath(in: segment, store: &mathStore)
            segment = expandWikiLinks(in: segment)
            segment = segment.components(separatedBy: "\n")
                .map(expandHighlightsOutsideInlineCode)
                .joined(separator: "\n")
            output.append(segment)
            nonCodeBuffer = []
        }

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
                flushNonCode()
                inFence = true
                fenceMarker = String(trimmed.prefix(3))
                output.append(line)
                continue
            }
            nonCodeBuffer.append(line)
        }
        flushNonCode()
        return output.joined(separator: "\n")
    }

    private static let blockMathPattern = try! NSRegularExpression(
        pattern: "\\$\\$([\\s\\S]+?)\\$\\$"
    )
    private static let inlineMathPattern = try! NSRegularExpression(
        pattern: "(?<![\\\\$])\\$(?![\\s$])([^$\\n]+?)(?<![\\s\\\\])\\$(?!\\d)"
    )
    private static let wikiLinkPattern = try! NSRegularExpression(
        pattern: "\\[\\[([^\\]|\\n]+?)(?:\\|([^\\]\\n]+?))?\\]\\]"
    )

    private static func maskMath(in text: String, store: inout [String]) -> String {
        var result = text
        for pattern in [blockMathPattern, inlineMathPattern] {
            let nsResult = result as NSString
            let matches = pattern.matches(
                in: result, range: NSRange(location: 0, length: nsResult.length)
            )
            var updated = result
            for match in matches.reversed() {
                let raw = nsResult.substring(with: match.range)
                store.append(raw)
                let ns = updated as NSString
                updated = ns.replacingCharacters(
                    in: match.range, with: mathToken(store.count - 1)
                )
            }
            result = updated
        }
        return result
    }

    private static func expandWikiLinks(in text: String) -> String {
        let nsText = text as NSString
        let matches = wikiLinkPattern.matches(
            in: text, range: NSRange(location: 0, length: nsText.length)
        )
        var result = text
        for match in matches.reversed() {
            let target = nsText.substring(with: match.range(at: 1))
            let alias = match.range(at: 2).location != NSNotFound
                ? nsText.substring(with: match.range(at: 2))
                : target
            let encoded = target.addingPercentEncoding(
                withAllowedCharacters: .urlHostAllowed
            ) ?? target
            let link = "<a href=\"inkdown-wiki:\(encoded)\" class=\"wiki\">\(htmlEscape(alias))</a>"
            let ns = result as NSString
            result = ns.replacingCharacters(in: match.range, with: link)
        }
        return result
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
