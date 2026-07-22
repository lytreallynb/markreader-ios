import Foundation
import NaturalLanguage
import SwiftUI
import MarkdownUI

#if canImport(Translation)
import Translation
#endif

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum TranslationTarget: String, CaseIterable, Identifiable, Equatable {
    case english
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese"
        }
    }

    var localeLanguage: Locale.Language {
        switch self {
        case .english: return Locale.Language(identifier: "en")
        case .chinese: return Locale.Language(identifier: "zh-Hans")
        }
    }
}

struct TranslationPane: View {
    let sourceMarkdown: String
    let target: TranslationTarget

    var body: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) {
            LiveTranslationContent(sourceMarkdown: sourceMarkdown, target: target)
        } else {
            UnavailableTranslationContent()
        }
        #else
        UnavailableTranslationContent()
        #endif
    }
}

private struct UnavailableTranslationContent: View {
    var body: some View {
        ContentUnavailableView {
            Label("Translation Unavailable", systemImage: "translate")
        } description: {
            Text("Requires iOS 18 or macOS 15.")
        }
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
@MainActor
private struct LiveTranslationContent: View {
    let sourceMarkdown: String
    let target: TranslationTarget

    @State private var configuration: TranslationSession.Configuration?
    @State private var document = TranslatableDocument(units: [])
    @State private var state: PaneState = .idle
    @State private var prepareRequested = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var generation: Int = 0

    private enum PaneState: Equatable {
        case idle
        case translating
        case success(String)
        case failure(String)
    }

    var body: some View {
        Group {
            switch state {
            case .idle:
                Color.clear
            case .translating:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .failure(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Label("Translation failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Retry") { scheduleTranslation(delay: 0) }
                        Button("Download Language Support") {
                            prepareRequested = true
                            scheduleTranslation(delay: 0)
                        }
                    }
                }
            case .success(let text):
                VStack(alignment: .trailing, spacing: 8) {
                    CopyButton(text: text)
                    Markdown(text)
                        .markdownCodeSyntaxHighlighter(NativeCodeBlockHighlighter())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .translationTask(configuration) { session in
            await performTranslation(using: session)
        }
        .onAppear { scheduleTranslation() }
        .onChange(of: sourceMarkdown) { _, _ in scheduleTranslation() }
        .onChange(of: target) { _, _ in scheduleTranslation() }
    }

    private func scheduleTranslation(delay: UInt64 = 400_000_000) {
        debounceTask?.cancel()
        generation += 1
        let currentGeneration = generation

        guard !sourceMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            configuration = nil
            return
        }

        debounceTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, currentGeneration == generation else { return }

            document = MarkdownTranslationSegmenter.segment(sourceMarkdown)
            guard document.hasTranslatableContent else {
                state = .success(sourceMarkdown)
                return
            }
            state = .translating

            if configuration?.target != target.localeLanguage {
                configuration = TranslationSession.Configuration(
                    source: nil, target: target.localeLanguage
                )
            } else if var existing = configuration {
                existing.invalidate()
                configuration = existing
            } else {
                configuration = TranslationSession.Configuration(
                    source: nil, target: target.localeLanguage
                )
            }
        }
    }

    private func performTranslation(using session: TranslationSession) async {
        let requestGeneration = generation
        let requestDocument = document

        if prepareRequested {
            prepareRequested = false
            do {
                try await session.prepareTranslation()
            } catch {
                state = .failure(error.localizedDescription)
                return
            }
        }

        let requests = requestDocument.requests()
        guard !requests.isEmpty else { return }

        var translated: [String: String] = [:]
        var lastError: Error?
        let batchSize = 32

        for start in stride(from: 0, to: requests.count, by: batchSize) {
            guard requestGeneration == generation else { return }
            let batch = Array(requests[start..<min(start + batchSize, requests.count)])
            do {
                let responses = try await withTranslationTimeout(seconds: 30) {
                    try await session.translations(from: batch)
                }
                for response in responses {
                    translated[response.clientIdentifier ?? ""] = response.targetText
                }
            } catch {
                lastError = error
                // A single undecidable segment can fail its whole batch, for
                // example when its detected language equals the target. Retry
                // segment by segment and keep originals for the failures.
                for request in batch {
                    guard requestGeneration == generation else { return }
                    let response = (try? await withTranslationTimeout(seconds: 10) {
                        try await session.translations(from: [request]).first
                    }) ?? nil
                    if let response {
                        translated[response.clientIdentifier ?? ""] = response.targetText
                    }
                }
            }
        }

        guard requestGeneration == generation else { return }
        if translated.isEmpty {
            let detail = lastError.map { $0.localizedDescription } ?? "No segments were translated."
            state = .failure(
                detail + " If the language model is not installed yet, "
                    + "use Download Language Support below."
            )
            return
        }
        state = .success(requestDocument.assemble(with: translated))
    }
}
#endif

// MARK: - Selection translation card

/// Bottom card that translates a text selection from the preview. Detects the
/// source language itself (falling back to the whole document's dominant
/// language for short selections) so the user is never asked to pick one.
struct SelectionTranslationCard: View {
    let sourceText: String
    let documentText: String
    let preferredTarget: TranslationTarget
    let onClose: () -> Void

    var body: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) {
            LiveSelectionTranslationCard(
                sourceText: sourceText,
                documentText: documentText,
                preferredTarget: preferredTarget,
                onClose: onClose
            )
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
@MainActor
private struct LiveSelectionTranslationCard: View {
    let sourceText: String
    let documentText: String
    let preferredTarget: TranslationTarget
    let onClose: () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var result: String?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close translation")
            }

            if let result {
                Text(result)
                    .textSelection(.enabled)
            } else if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 480, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .translationTask(configuration) { session in
            do {
                let response = try await withTranslationTimeout(seconds: 20) {
                    try await session.translate(sourceText)
                }
                result = response.targetText
            } catch {
                errorText = error.localizedDescription
            }
        }
        .onAppear { configure() }
        .onChange(of: sourceText) { _, _ in configure() }
    }

    private func configure() {
        result = nil
        errorText = nil
        let source = Self.detectLanguage(sourceText) ?? Self.detectLanguage(documentText)
        var target = preferredTarget.localeLanguage
        if let source, source.languageCode == target.languageCode {
            let other: TranslationTarget = preferredTarget == .english ? .chinese : .english
            target = other.localeLanguage
        }
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    private static func detectLanguage(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return Locale.Language(identifier: dominant.rawValue)
    }
}
#endif

private struct CopyButton: View {
    let text: String

    var body: some View {
        Button {
            copyToPasteboard(text)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Segmentation

/// A Markdown document broken into passthrough parts (code, structure,
/// protected tokens) and translatable parts (prose, code comments).
struct TranslatableDocument {
    enum Unit {
        case passthrough(String)
        case translatable(id: String, text: String, protected: [String: String])
    }

    var units: [Unit]

    var hasTranslatableContent: Bool {
        units.contains {
            if case .translatable = $0 { return true }
            return false
        }
    }
}

private struct TranslationTimeoutError: LocalizedError {
    var errorDescription: String? { "Translation timed out." }
}

/// Runs the operation with a hard timeout so a hung translation request
/// cannot leave the pane stuck on the spinner forever.
private func withTranslationTimeout<T: Sendable>(
    seconds: Double, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TranslationTimeoutError()
        }
        guard let result = try await group.next() else {
            throw TranslationTimeoutError()
        }
        group.cancelAll()
        return result
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
extension TranslatableDocument {
    func requests() -> [TranslationSession.Request] {
        units.compactMap { unit in
            guard case .translatable(let id, let text, _) = unit else { return nil }
            return TranslationSession.Request(sourceText: text, clientIdentifier: id)
        }
    }
}
#endif

extension TranslatableDocument {
    /// Reassembles the document, restoring protected tokens inside each
    /// translated unit. Units whose translation is missing or whose protected
    /// tokens were mangled fall back to their original text.
    func assemble(with translations: [String: String]) -> String {
        var parts: [String] = []
        for unit in units {
            switch unit {
            case .passthrough(let text):
                parts.append(text)
            case .translatable(let id, let original, let protected):
                guard var candidate = translations[id] else {
                    parts.append(restoreProtected(original, protected))
                    continue
                }
                var restored = true
                for (token, value) in protected {
                    if candidate.contains(token) {
                        candidate = candidate.replacingOccurrences(of: token, with: value)
                    } else {
                        restored = false
                        break
                    }
                }
                parts.append(restored ? candidate : restoreProtected(original, protected))
            }
        }
        return parts.joined()
    }

    private func restoreProtected(_ text: String, _ protected: [String: String]) -> String {
        var result = text
        for (token, value) in protected {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }
}

/// Splits Markdown into translation units line by line.
/// Rules: code stays as is, comments inside code are translatable, inline
/// code and file names or paths are protected and never leave the device
/// as translation input.
enum MarkdownTranslationSegmenter {
    static func segment(_ markdown: String) -> TranslatableDocument {
        var units: [TranslatableDocument.Unit] = []
        var unitIndex = 0
        var inFence = false
        var fenceMarker = ""
        var fenceLanguage = ""

        let lines = markdown.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            let suffix = lineIndex == lines.count - 1 ? "" : "\n"
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inFence {
                if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                    units.append(.passthrough(line + suffix))
                } else {
                    appendCodeLine(
                        line, language: fenceLanguage, suffix: suffix,
                        to: &units, unitIndex: &unitIndex
                    )
                }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                fenceMarker = String(trimmed.prefix(3))
                fenceLanguage = trimmed
                    .drop(while: { $0 == "`" || $0 == "~" })
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                units.append(.passthrough(line + suffix))
                continue
            }

            appendProseLine(line, suffix: suffix, to: &units, unitIndex: &unitIndex)
        }
        return TranslatableDocument(units: units)
    }

    // MARK: Prose

    /// Leading Markdown structure that should never reach the translator:
    /// heading markers, blockquote markers, list markers, task checkboxes.
    private static let structuralPrefix = try! NSRegularExpression(
        pattern: "^[ \t]*(?:(?:#{1,6}|>|[-*+]|\\d+[.)])[ \t]+)*(?:\\[[ xX]\\][ \t]+)?"
    )

    private static func appendProseLine(
        _ line: String, suffix: String,
        to units: inout [TranslatableDocument.Unit], unitIndex: inout Int
    ) {
        let nsLine = line as NSString
        let prefixRange = structuralPrefix.firstMatch(
            in: line, range: NSRange(location: 0, length: nsLine.length)
        )?.range ?? NSRange(location: 0, length: 0)

        let prefix = nsLine.substring(to: prefixRange.length)
        let content = nsLine.substring(from: prefixRange.length)

        guard containsTranslatableText(content) else {
            units.append(.passthrough(line + suffix))
            return
        }

        let (masked, protected) = protectSpans(in: content)
        // The protection tokens contain no letters, so if nothing translatable
        // remains the line was only code spans and file names. Keep it as is.
        guard containsTranslatableText(masked) else {
            units.append(.passthrough(line + suffix))
            return
        }

        if !prefix.isEmpty {
            units.append(.passthrough(prefix))
        }
        units.append(.translatable(id: nextID(&unitIndex), text: masked, protected: protected))
        units.append(.passthrough(suffix))
    }

    // MARK: Code

    private static let lineCommentMarkers: [String: [String]] = [
        "python": ["#"], "py": ["#"], "ruby": ["#"], "rb": ["#"],
        "shell": ["#"], "sh": ["#"], "bash": ["#"], "zsh": ["#"], "fish": ["#"],
        "yaml": ["#"], "yml": ["#"], "toml": ["#"], "r": ["#"],
        "perl": ["#"], "makefile": ["#"], "dockerfile": ["#"], "cmake": ["#"],
        "swift": ["//"], "javascript": ["//"], "js": ["//"], "typescript": ["//"],
        "ts": ["//"], "tsx": ["//"], "jsx": ["//"], "java": ["//"], "c": ["//"],
        "cpp": ["//"], "c++": ["//"], "objc": ["//"], "objective-c": ["//"],
        "go": ["//"], "rust": ["//"], "rs": ["//"], "kotlin": ["//"], "kt": ["//"],
        "scala": ["//"], "csharp": ["//"], "cs": ["//"], "php": ["//", "#"],
        "dart": ["//"], "json5": ["//"],
        "sql": ["--"], "lua": ["--"], "haskell": ["--"], "hs": ["--"],
        "html": [], "xml": [], "svg": [], "markdown": [], "md": [], "json": [],
    ]

    private static func appendCodeLine(
        _ line: String, language: String, suffix: String,
        to units: inout [TranslatableDocument.Unit], unitIndex: inout Int
    ) {
        // Whole-line HTML comments are translatable in any language.
        if let inner = htmlCommentBody(of: line), containsTranslatableText(inner) {
            let nsLine = line as NSString
            let open = nsLine.range(of: "<!--")
            let close = nsLine.range(of: "-->", options: .backwards)
            units.append(.passthrough(nsLine.substring(to: open.location + open.length)))
            units.append(.translatable(id: nextID(&unitIndex), text: inner, protected: [:]))
            units.append(.passthrough(nsLine.substring(from: close.location) + suffix))
            return
        }

        let markers = lineCommentMarkers[language] ?? ["//", "#"]
        for marker in markers {
            guard let markerRange = line.range(of: marker) else { continue }
            // Heuristic: skip markers that are likely inside a string literal.
            let before = line[line.startIndex..<markerRange.lowerBound]
            let quoteCount = before.filter { $0 == "\"" }.count
            guard quoteCount % 2 == 0 else { continue }

            let comment = String(line[markerRange.upperBound...])
            guard containsTranslatableText(comment) else { continue }

            units.append(.passthrough(String(before) + marker))
            units.append(.translatable(
                id: nextID(&unitIndex),
                text: comment,
                protected: [:]
            ))
            units.append(.passthrough(suffix))
            return
        }
        units.append(.passthrough(line + suffix))
    }

    private static func htmlCommentBody(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"),
              trimmed.count > 7
        else { return nil }
        return String(trimmed.dropFirst(4).dropLast(3))
    }

    // MARK: Protection

    private static let inlineCodePattern = try! NSRegularExpression(
        pattern: "`+[^`\\n]+`+"
    )
    private static let knownExtensions: Set<String> = [
        "md", "markdown", "txt", "swift", "py", "js", "ts", "tsx", "jsx",
        "json", "yml", "yaml", "toml", "sh", "zsh", "bash", "c", "h", "cpp",
        "hpp", "cc", "m", "mm", "java", "kt", "go", "rs", "rb", "php", "html",
        "css", "scss", "xml", "sql", "csv", "pdf", "png", "jpg", "jpeg", "gif",
        "svg", "mp4", "mov", "zip", "app", "plist", "lock", "gradle", "cfg",
        "ini", "log", "ipynb", "xcodeproj", "entitlements",
    ]
    private static let fileTokenPattern = try! NSRegularExpression(
        pattern: "(?<![\\w/])(~?/?[\\w.@-]+(?:/[\\w.@-]+)+/?|[\\w@-]+\\.[A-Za-z0-9]{1,10})(?![\\w/])"
    )
    // Markdown constructs whose syntax the translator must never see:
    // whole images, the "](target)" tail of links, and bare URLs.
    private static let imagePattern = try! NSRegularExpression(
        pattern: "!\\[[^\\]\\n]*\\]\\([^)\\n]*\\)"
    )
    private static let linkTargetPattern = try! NSRegularExpression(
        pattern: "\\]\\([^)\\n]*\\)"
    )
    private static let bareURLPattern = try! NSRegularExpression(
        pattern: "https?://[^\\s<>()]+"
    )

    /// Replaces inline code spans, file names, and paths with bracket tokens
    /// that survive machine translation, returning the masked text and the
    /// token map.
    private static func protectSpans(
        in text: String
    ) -> (masked: String, protected: [String: String]) {
        var protected: [String: String] = [:]
        var tokenIndex = 0
        var masked = text

        func protect(matching regex: NSRegularExpression, where include: (String) -> Bool) {
            let nsMasked = masked as NSString
            let matches = regex.matches(
                in: masked, range: NSRange(location: 0, length: nsMasked.length)
            )
            var result = masked
            for match in matches.reversed() {
                let value = nsMasked.substring(with: match.range)
                guard include(value), !value.contains("\u{27E6}") else { continue }
                let token = "\u{27E6}\(tokenIndex)\u{27E7}"
                tokenIndex += 1
                protected[token] = value
                let ns = result as NSString
                result = ns.replacingCharacters(in: match.range, with: token)
            }
            masked = result
        }

        protect(matching: inlineCodePattern) { _ in true }
        protect(matching: imagePattern) { _ in true }
        protect(matching: linkTargetPattern) { _ in true }
        protect(matching: bareURLPattern) { _ in true }
        protect(matching: fileTokenPattern) { value in
            if value.contains("/") { return true }
            let ext = value.components(separatedBy: ".").last?.lowercased() ?? ""
            return knownExtensions.contains(ext)
        }
        return (masked, protected)
    }

    private static func containsTranslatableText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar)
        }
    }

    private static func nextID(_ index: inout Int) -> String {
        let id = "unit\(index)"
        index += 1
        return id
    }
}
