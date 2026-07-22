import SwiftUI

struct ReaderView: View {
    let fileURL: URL

    @State private var text: String = ""
    @State private var originalText: String?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var htmlBody: String = ""
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var mode: PaneMode = .preview
    @State private var showsTranslation = false
    @State private var translationTarget: TranslationTarget = .english
    @State private var highlightMessage: String?
    @State private var renderTask: Task<Void, Never>?
    @State private var autosaveTask: Task<Void, Never>?
    @StateObject private var previewController = PreviewController()

    @AppStorage("reader.textSizeStep") private var textSizeStep: Int = 2

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private enum PaneMode: String, CaseIterable {
        case write = "Write"
        case preview = "Preview"
        case translation = "Translate"
    }

    private static let previewFontSizes = [13, 14, 16, 18, 21, 24]

    private var isDirty: Bool {
        guard let originalText else { return false }
        return text != originalText
    }

    private var showsSideBySide: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    private var availableModes: [PaneMode] {
        showsTranslation ? PaneMode.allCases : [.write, .preview]
    }

    private var previewFontSize: Int {
        let index = min(max(textSizeStep, 0), Self.previewFontSizes.count - 1)
        return Self.previewFontSizes[index]
    }

    var body: some View {
        Group {
            if originalText != nil {
                panes
            } else if let loadError {
                ContentUnavailableView {
                    Label("Could Not Load File", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { load() }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .background(
            Button("") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        )
        .task(id: fileURL) {
            load()
        }
        .onChange(of: text) { _, _ in
            scheduleRender()
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            if isDirty { save() }
        }
        .alert(
            "Could not save file",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .alert(
            "Highlight",
            isPresented: Binding(
                get: { highlightMessage != nil },
                set: { if !$0 { highlightMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(highlightMessage ?? "")
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var panes: some View {
        if showsSideBySide {
            HStack(spacing: 0) {
                editorPane
                Divider()
                previewPane
                if showsTranslation {
                    Divider()
                    translationPane
                }
            }
        } else {
            switch mode {
            case .write: editorPane
            case .preview: previewPane
            case .translation: translationPane
            }
        }
    }

    private var editorPane: some View {
        MarkdownSourceEditor(text: $text, selection: $editorSelection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewPane: some View {
        PreviewWebView(
            htmlBody: $htmlBody,
            baseURL: fileURL.deletingLastPathComponent(),
            fontSize: previewFontSize,
            controller: previewController
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationPane: some View {
        ScrollView {
            TranslationPane(sourceMarkdown: text, target: translationTarget)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !showsSideBySide {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(availableModes, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(HighlightColor.allCases) { color in
                    Button(color.displayName) {
                        applyHighlight(color)
                    }
                }
                Divider()
                Button("Remove Highlight") {
                    removeHighlight()
                }
            } label: {
                Label("Highlight", systemImage: "highlighter")
            }

            Menu {
                ForEach(TranslationTarget.allCases) { target in
                    Button {
                        translationTarget = target
                        showsTranslation = true
                        if !showsSideBySide {
                            mode = .translation
                        }
                    } label: {
                        if translationTarget == target && showsTranslation {
                            Label(target.displayName, systemImage: "checkmark")
                        } else {
                            Text(target.displayName)
                        }
                    }
                }
                if showsTranslation {
                    Divider()
                    Button("Hide Translation") {
                        showsTranslation = false
                        if mode == .translation {
                            mode = .preview
                        }
                    }
                }
            } label: {
                Label("Translate", systemImage: "translate")
            }

            Menu {
                Button("Smaller") {
                    if textSizeStep > 0 { textSizeStep -= 1 }
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(textSizeStep == 0)

                Button("Larger") {
                    if textSizeStep < Self.previewFontSizes.count - 1 { textSizeStep += 1 }
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(textSizeStep == Self.previewFontSizes.count - 1)
            } label: {
                Label("Text Size", systemImage: "textformat.size")
            }
        }
    }

    // MARK: - Highlighting

    private func applyHighlight(_ color: HighlightColor) {
        Task {
            let previewVisible = showsSideBySide || mode == .preview
            if previewVisible,
               let selection = await previewController.currentSelection(),
               !selection.text.isEmpty {
                if let updated = MarkdownHighlighter.applyToRenderedSelection(
                    source: text,
                    selectedText: selection.text,
                    sourcePos: selection.sourcePos,
                    color: color
                ) {
                    text = updated
                } else {
                    highlightMessage = "Could not match the selection in the source. "
                        + "Try selecting text without inline formatting, or highlight in Write mode."
                }
                return
            }

            if editorSelection.length > 0,
               let updated = MarkdownHighlighter.applyToSourceRange(
                   text, range: editorSelection, color: color
               ) {
                text = updated
                return
            }

            highlightMessage = "Select some text in the preview or the editor first."
        }
    }

    private func removeHighlight() {
        Task {
            let previewVisible = showsSideBySide || mode == .preview
            guard previewVisible,
                  let selection = await previewController.currentSelection(),
                  let markText = selection.markText
            else {
                highlightMessage = "Select a highlighted passage in the preview first."
                return
            }

            if let updated = MarkdownHighlighter.removeHighlight(
                source: text, markText: markText, sourcePos: selection.sourcePos
            ) {
                text = updated
            } else {
                highlightMessage = "Could not find that highlight in the source."
            }
        }
    }

    // MARK: - Rendering and persistence

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            htmlBody = MarkdownHTMLRenderer.renderBody(from: text)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, isDirty else { return }
            save()
        }
    }

    private func load() {
        loadError = nil
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatorError: NSError?
        var readResult: Result<String, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinatorError
        ) { url in
            readResult = Result { try String(contentsOf: url, encoding: .utf8) }
        }

        if let coordinatorError {
            loadError = coordinatorError.localizedDescription
            return
        }

        switch readResult {
        case .success(let loadedText):
            text = loadedText
            originalText = loadedText
            htmlBody = MarkdownHTMLRenderer.renderBody(from: loadedText)
        case .failure(let error):
            loadError = error.localizedDescription
        case nil:
            loadError = "The file could not be read."
        }
    }

    private func save() {
        saveError = nil
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let textToSave = text
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { newURL in
            do {
                try textToSave.write(to: newURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            saveError = coordinatorError.localizedDescription
            return
        }
        if let writeError {
            saveError = writeError.localizedDescription
            return
        }
        originalText = textToSave
    }
}
