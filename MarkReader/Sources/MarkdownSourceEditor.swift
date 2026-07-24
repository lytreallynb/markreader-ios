import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Plain-text editor with lightweight Markdown syntax coloring.
/// Backed by UITextView on iOS and NSTextView on macOS.
/// The selection binding reports the current selected range (UTF-16) so the
/// toolbar highlighter can wrap the selection in the source.
struct MarkdownSourceEditor: View {
    @Binding var text: String
    @Binding var selection: NSRange
    var fontSize: CGFloat = 13

    var body: some View {
        MarkdownSourceEditorRepresentable(
            text: $text, selection: $selection, fontSize: fontSize
        )
    }
}

private enum MarkdownSyntaxColoring {
    #if os(iOS)
    static func baseFont(size: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    #elseif os(macOS)
    static func baseFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    #endif

    /// Above this many UTF-16 units, regex colorization is skipped entirely:
    /// running several full-document regexes on the main thread makes typing
    /// lag in large files. Base font and color still apply.
    static let colorizeCharacterLimit = 150_000

    private static let headingRegex = try! NSRegularExpression(
        pattern: "^#{1,6}[ \t].*$", options: [.anchorsMatchLines]
    )
    private static let quoteRegex = try! NSRegularExpression(
        pattern: "^[ \t]{0,3}>.*$", options: [.anchorsMatchLines]
    )
    private static let listMarkerRegex = try! NSRegularExpression(
        pattern: "^[ \t]*([-*+]|\\d+\\.)[ \t]", options: [.anchorsMatchLines]
    )
    private static let fencedCodeBlockRegex = try! NSRegularExpression(
        pattern: "^```[^\n]*$[\\s\\S]*?^```[ \t]*$", options: [.anchorsMatchLines]
    )
    private static let inlineCodeRegex = try! NSRegularExpression(
        pattern: "`[^`\n]+`"
    )
    private static let boldRegex = try! NSRegularExpression(
        pattern: "(\\*\\*|__)(?=\\S)[^\n]*?\\S\\1"
    )
    private static let italicRegex = try! NSRegularExpression(
        pattern: "(?<![*_])([*_])(?!\\1)(?=\\S)[^\n]*?\\S\\1(?!\\1)"
    )
    private static let linkRegex = try! NSRegularExpression(
        pattern: "\\[[^\\]\n]*\\]\\([^)\n]*\\)"
    )
    private static let highlightRegex = try! NSRegularExpression(
        pattern: "==[^=\n]+==|<mark[^>]*>|</mark>"
    )

    #if os(iOS)
    static func apply(to storage: NSTextStorage, baseColor: UIColor, size: CGFloat) {
        let font = baseFont(size: size)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(
            [.font: font, .foregroundColor: baseColor],
            range: full
        )
        colorize(storage: storage, fullRange: full, baseFont: font)
        storage.endEditing()
    }
    #elseif os(macOS)
    static func apply(to storage: NSTextStorage, baseColor: NSColor, size: CGFloat) {
        let font = baseFont(size: size)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(
            [.font: font, .foregroundColor: baseColor],
            range: full
        )
        colorize(storage: storage, fullRange: full, baseFont: font)
        storage.endEditing()
    }
    #endif

    #if os(iOS)
    private typealias PlatformFont = UIFont
    #elseif os(macOS)
    private typealias PlatformFont = NSFont
    #endif

    private static func colorize(
        storage: NSTextStorage, fullRange: NSRange, baseFont: PlatformFont
    ) {
        guard fullRange.length <= colorizeCharacterLimit else { return }
        fencedCodeBlockRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: PlatformSemanticColor.codeBlock, range: range)
        }

        headingRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: PlatformSemanticColor.heading, range: range)
            storage.addAttribute(.font, value: boldVariant(of: baseFont), range: range)
        }

        quoteRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: PlatformSemanticColor.quote, range: range)
        }

        listMarkerRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let match else { return }
            let markerRange = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: PlatformSemanticColor.listMarker, range: markerRange)
        }

        linkRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: PlatformSemanticColor.link, range: range)
        }

        boldRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.font, value: boldVariant(of: baseFont), range: range)
        }

        italicRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.font, value: italicVariant(of: baseFont), range: range)
        }

        inlineCodeRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: PlatformSemanticColor.inlineCode, range: range)
            storage.addAttribute(.backgroundColor, value: PlatformSemanticColor.inlineCodeBackground, range: range)
        }

        highlightRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.backgroundColor, value: PlatformSemanticColor.highlightBackground, range: range)
        }
    }

    #if os(iOS)
    private static func boldVariant(of font: UIFont) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
    }

    private static func italicVariant(of font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) ?? font.fontDescriptor
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
    #elseif os(macOS)
    private static func boldVariant(of font: NSFont) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
    }

    private static func italicVariant(of font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        return manager.convert(font, toHaveTrait: .italicFontMask)
    }
    #endif
}

/// Semantic colors that adapt to light/dark mode and stay legible against the system background.
private enum PlatformSemanticColor {
    #if os(iOS)
    static let heading = UIColor.systemBlue
    static let quote = UIColor.systemGreen
    static let listMarker = UIColor.systemOrange
    static let link = UIColor.systemTeal
    static let inlineCode = UIColor.systemPurple
    static let inlineCodeBackground = UIColor.secondarySystemFill
    static let codeBlock = UIColor.systemPurple
    static let highlightBackground = UIColor.systemYellow.withAlphaComponent(0.35)
    #elseif os(macOS)
    static let heading = NSColor.systemBlue
    static let quote = NSColor.systemGreen
    static let listMarker = NSColor.systemOrange
    static let link = NSColor.systemTeal
    static let inlineCode = NSColor.systemPurple
    static let inlineCodeBackground = NSColor.textBackgroundColor.withAlphaComponent(0.5)
    static let codeBlock = NSColor.systemPurple
    static let highlightBackground = NSColor.systemYellow.withAlphaComponent(0.35)
    #endif
}

#if os(iOS)
private struct MarkdownSourceEditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var fontSize: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = MarkdownSyntaxColoring.baseFont(size: fontSize)
        textView.textColor = .label
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.delegate = context.coordinator
        textView.text = text
        context.coordinator.fontSize = fontSize
        MarkdownSyntaxColoring.apply(to: textView.textStorage, baseColor: .label, size: fontSize)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.fontSize = fontSize
        let sizeChanged = abs((uiView.font?.pointSize ?? 0) - fontSize) > 0.1
        guard uiView.text != text || sizeChanged else { return }
        let selectedRange = uiView.selectedRange
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = MarkdownSyntaxColoring.baseFont(size: fontSize)
        MarkdownSyntaxColoring.apply(to: uiView.textStorage, baseColor: .label, size: fontSize)
        uiView.selectedRange = clampedRange(selectedRange, forLength: (uiView.text as NSString).length)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    private func clampedRange(_ range: NSRange, forLength length: Int) -> NSRange {
        let location = min(range.location, length)
        let maxLength = length - location
        return NSRange(location: location, length: min(range.length, maxLength))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let selection: Binding<NSRange>
        private var isApplyingProgrammaticUpdate = false
        var fontSize: CGFloat = 13

        init(text: Binding<String>, selection: Binding<NSRange>) {
            self.text = text
            self.selection = selection
        }

        private var pendingColorize: DispatchWorkItem?

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticUpdate else { return }
            isApplyingProgrammaticUpdate = true
            text.wrappedValue = textView.text
            isApplyingProgrammaticUpdate = false
            scheduleColorize(for: textView)
        }

        /// Recolorizing on every keystroke runs full-document regexes on the
        /// main thread and makes typing lag; debounce it instead. Attribute
        /// changes do not re-enter textViewDidChange.
        private func scheduleColorize(for textView: UITextView) {
            pendingColorize?.cancel()
            let size = fontSize
            let item = DispatchWorkItem { [weak textView] in
                guard let textView else { return }
                let selectedRange = textView.selectedRange
                MarkdownSyntaxColoring.apply(
                    to: textView.textStorage, baseColor: .label, size: size
                )
                textView.selectedRange = selectedRange
            }
            pendingColorize = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticUpdate else { return }
            let range = textView.selectedRange
            DispatchQueue.main.async {
                self.selection.wrappedValue = range
            }
        }
    }
}
#elseif os(macOS)
private struct MarkdownSourceEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var fontSize: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = MarkdownSyntaxColoring.baseFont(size: fontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = text
        context.coordinator.fontSize = fontSize
        if let storage = textView.textStorage {
            MarkdownSyntaxColoring.apply(to: storage, baseColor: .labelColor, size: fontSize)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.fontSize = fontSize
        let sizeChanged = abs((textView.font?.pointSize ?? 0) - fontSize) > 0.1
        guard textView.string != text || sizeChanged else { return }
        let selectedRanges = textView.selectedRanges
        if textView.string != text {
            textView.string = text
        }
        textView.font = MarkdownSyntaxColoring.baseFont(size: fontSize)
        if let storage = textView.textStorage {
            MarkdownSyntaxColoring.apply(to: storage, baseColor: .labelColor, size: fontSize)
        }
        textView.selectedRanges = selectedRanges
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let selection: Binding<NSRange>
        private var isApplyingProgrammaticUpdate = false
        var fontSize: CGFloat = 13

        init(text: Binding<String>, selection: Binding<NSRange>) {
            self.text = text
            self.selection = selection
        }

        private var pendingColorize: DispatchWorkItem?

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView = notification.object as? NSTextView else { return }
            isApplyingProgrammaticUpdate = true
            text.wrappedValue = textView.string
            isApplyingProgrammaticUpdate = false
            scheduleColorize(for: textView)
        }

        /// Recolorizing on every keystroke runs full-document regexes on the
        /// main thread and makes typing lag; debounce it instead. Attribute
        /// changes do not re-enter textDidChange.
        private func scheduleColorize(for textView: NSTextView) {
            pendingColorize?.cancel()
            let size = fontSize
            let item = DispatchWorkItem { [weak textView] in
                guard let textView, let storage = textView.textStorage else { return }
                let selectedRanges = textView.selectedRanges
                MarkdownSyntaxColoring.apply(
                    to: storage, baseColor: .labelColor, size: size
                )
                textView.selectedRanges = selectedRanges
            }
            pendingColorize = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            DispatchQueue.main.async {
                self.selection.wrappedValue = range
            }
        }
    }
}
#endif
