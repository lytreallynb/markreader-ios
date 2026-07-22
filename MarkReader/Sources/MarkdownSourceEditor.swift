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

    var body: some View {
        MarkdownSourceEditorRepresentable(text: $text, selection: $selection)
    }
}

private enum MarkdownSyntaxColoring {
    #if os(iOS)
    static let baseFont = UIFont.monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
    #elseif os(macOS)
    static let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    #endif

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
    static func apply(to storage: NSTextStorage, baseColor: UIColor) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(
            [.font: baseFont, .foregroundColor: baseColor],
            range: full
        )
        colorize(storage: storage, fullRange: full)
        storage.endEditing()
    }
    #elseif os(macOS)
    static func apply(to storage: NSTextStorage, baseColor: NSColor) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(
            [.font: baseFont, .foregroundColor: baseColor],
            range: full
        )
        colorize(storage: storage, fullRange: full)
        storage.endEditing()
    }
    #endif

    private static func colorize(storage: NSTextStorage, fullRange: NSRange) {
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

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = MarkdownSyntaxColoring.baseFont
        textView.textColor = .label
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.delegate = context.coordinator
        textView.text = text
        MarkdownSyntaxColoring.apply(to: textView.textStorage, baseColor: .label)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }
        let selectedRange = uiView.selectedRange
        uiView.text = text
        MarkdownSyntaxColoring.apply(to: uiView.textStorage, baseColor: .label)
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

        init(text: Binding<String>, selection: Binding<NSRange>) {
            self.text = text
            self.selection = selection
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticUpdate else { return }
            let selectedRange = textView.selectedRange
            isApplyingProgrammaticUpdate = true
            text.wrappedValue = textView.text
            MarkdownSyntaxColoring.apply(to: textView.textStorage, baseColor: .label)
            textView.selectedRange = selectedRange
            isApplyingProgrammaticUpdate = false
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

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = MarkdownSyntaxColoring.baseFont
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = text
        if let storage = textView.textStorage {
            MarkdownSyntaxColoring.apply(to: storage, baseColor: .labelColor)
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
        guard textView.string != text else { return }
        let selectedRanges = textView.selectedRanges
        textView.string = text
        if let storage = textView.textStorage {
            MarkdownSyntaxColoring.apply(to: storage, baseColor: .labelColor)
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

        init(text: Binding<String>, selection: Binding<NSRange>) {
            self.text = text
            self.selection = selection
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRanges = textView.selectedRanges
            isApplyingProgrammaticUpdate = true
            text.wrappedValue = textView.string
            if let storage = textView.textStorage {
                MarkdownSyntaxColoring.apply(to: storage, baseColor: .labelColor)
            }
            textView.selectedRanges = selectedRanges
            isApplyingProgrammaticUpdate = false
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
