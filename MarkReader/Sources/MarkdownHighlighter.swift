import Foundation

/// Named highlight colors offered in the toolbar. The hex values are written
/// into the Markdown source as inline mark styles, so they travel with the file.
enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case orange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .orange: return "Orange"
        }
    }

    var hex: String {
        switch self {
        case .yellow: return "#ffec9e"
        case .green: return "#c3edc0"
        case .blue: return "#bcd8ff"
        case .pink: return "#ffcfe1"
        case .orange: return "#ffd8a8"
        }
    }
}

/// Inline formats that can be applied to a selection, written back into the
/// Markdown source. Bold and strikethrough use Markdown syntax; underline has
/// no Markdown form so it uses the HTML tag, which the preview passes through.
enum InlineFormat: String, CaseIterable, Identifiable {
    case bold
    case underline
    case strikethrough

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bold: return "Bold"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: return "bold"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        }
    }

    var prefix: String {
        switch self {
        case .bold: return "**"
        case .underline: return "<u>"
        case .strikethrough: return "~~"
        }
    }

    var suffix: String {
        switch self {
        case .bold: return "**"
        case .underline: return "</u>"
        case .strikethrough: return "~~"
        }
    }
}

/// Applies and removes <mark> highlights in Markdown source text.
enum MarkdownHighlighter {
    static func markup(for text: String, color: HighlightColor) -> String {
        if color == .yellow {
            return "<mark>\(text)</mark>"
        }
        return "<mark style=\"background:\(color.hex)\">\(text)</mark>"
    }

    /// Wraps the given UTF-16 range of the source in a mark tag.
    /// Used when the selection comes from the source editor.
    static func applyToSourceRange(
        _ source: String, range: NSRange, color: HighlightColor
    ) -> String? {
        let nsSource = source as NSString
        guard range.length > 0,
              range.location >= 0,
              range.location + range.length <= nsSource.length
        else { return nil }

        let selected = nsSource.substring(with: range)
        guard !selected.contains("\n") || !selected
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return nsSource.replacingCharacters(in: range, with: markup(for: selected, color: color))
    }

    /// Finds the selected plain text near the given cmark sourcepos
    /// ("startLine:startCol-endLine:endCol") and wraps it in a mark tag.
    /// Used when the selection comes from the rendered preview.
    static func applyToRenderedSelection(
        source: String, selectedText: String, sourcePos: String?, color: HighlightColor
    ) -> String? {
        replaceNearSourcePos(
            source: source,
            needle: selectedText,
            sourcePos: sourcePos
        ) { markup(for: $0, color: color) }
    }

    /// Wraps the given UTF-16 range of the source with arbitrary prefix and
    /// suffix. Used for inline formats and note references from the editor.
    static func wrapSourceRange(
        _ source: String, range: NSRange, prefix: String, suffix: String
    ) -> String? {
        let nsSource = source as NSString
        guard range.length > 0,
              range.location >= 0,
              range.location + range.length <= nsSource.length
        else { return nil }
        let selected = nsSource.substring(with: range)
        return nsSource.replacingCharacters(in: range, with: prefix + selected + suffix)
    }

    /// Finds the selected plain text near sourcepos and wraps it with the
    /// given prefix and suffix. Used for inline formats and note references
    /// from the rendered preview.
    static func wrapRenderedSelection(
        source: String, selectedText: String, sourcePos: String?,
        prefix: String, suffix: String
    ) -> String? {
        replaceNearSourcePos(
            source: source,
            needle: selectedText,
            sourcePos: sourcePos
        ) { prefix + $0 + suffix }
    }

    /// Removes the highlight around the given mark content near sourcepos.
    /// Handles both <mark ...>text</mark> and ==text== forms.
    static func removeHighlight(
        source: String, markText: String, sourcePos: String?
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: normalize(markText))
        let patterns = [
            "<mark[^>]*>\(escaped)</mark>",
            "==\(escaped)==",
        ]

        let (searchRange, nsSource) = searchWindow(source: source, sourcePos: sourcePos)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for range in [searchRange, NSRange(location: 0, length: nsSource.length)] {
                if let match = regex.firstMatch(in: source, range: range) {
                    return nsSource.replacingCharacters(in: match.range, with: markText)
                }
            }
        }
        return nil
    }

    private static func replaceNearSourcePos(
        source: String, needle: String, sourcePos: String?,
        transform: (String) -> String
    ) -> String? {
        let cleanNeedle = normalize(needle)
        guard !cleanNeedle.isEmpty else { return nil }

        let (windowRange, nsSource) = searchWindow(source: source, sourcePos: sourcePos)
        for range in [windowRange, NSRange(location: 0, length: nsSource.length)] {
            let found = nsSource.range(of: cleanNeedle, options: [], range: range)
            if found.location != NSNotFound {
                return nsSource.replacingCharacters(
                    in: found, with: transform(nsSource.substring(with: found))
                )
            }
        }
        return nil
    }

    /// Returns the UTF-16 range of the source lines covered by a cmark
    /// sourcepos string, expanded by one line on each side, or the full
    /// range when no sourcepos is available.
    private static func searchWindow(
        source: String, sourcePos: String?
    ) -> (NSRange, NSString) {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        guard let sourcePos,
              let (startLine, endLine) = parse(sourcePos: sourcePos)
        else { return (fullRange, nsSource) }

        let lines = source.components(separatedBy: "\n")
        let start = max(0, startLine - 2)
        let end = min(lines.count, endLine + 1)
        guard start < end else { return (fullRange, nsSource) }

        let prefix = lines.prefix(start).reduce(0) { $0 + ($1 as NSString).length + 1 }
        let windowLength = lines[start..<end].reduce(0) { $0 + ($1 as NSString).length + 1 }
        let clamped = NSRange(
            location: min(prefix, nsSource.length),
            length: min(windowLength, nsSource.length - min(prefix, nsSource.length))
        )
        return (clamped, nsSource)
    }

    private static func parse(sourcePos: String) -> (Int, Int)? {
        let parts = sourcePos.components(separatedBy: "-")
        guard parts.count == 2,
              let startLine = Int(parts[0].components(separatedBy: ":").first ?? ""),
              let endLine = Int(parts[1].components(separatedBy: ":").first ?? "")
        else { return nil }
        return (startLine, endLine)
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
