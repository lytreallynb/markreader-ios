import SwiftUI

struct ReaderView: View {
    let fileURL: URL

    @State private var text: String = ""
    @State private var originalText: String?
    @State private var pdfData: Data?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var htmlBody: String = ""
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var mode: PaneMode = .preview
    @State private var showsTranslation = false
    @State private var translationTarget: TranslationTarget = .english
    @State private var highlightMessage: String?
    @State private var noteDraft = ""
    @State private var showNoteAlert = false
    @State private var pendingNoteSelection: PendingSelection?
    @State private var selectionTranslationText: String?
    @State private var insightTitle = ""
    @State private var insightPrompt: String?
    @State private var showPresentation = false
    @State private var renderTask: Task<Void, Never>?
    @State private var autosaveTask: Task<Void, Never>?
    @StateObject private var previewController = PreviewController()

    private enum PendingSelection {
        case preview(PreviewSelection)
        case editor(NSRange)
    }

    @AppStorage("reader.textSizeStep") private var textSizeStep: Int = 2
    @AppStorage("reader.showsSource") private var showsSource = false
    @AppStorage("reader.theme") private var themeName = "default"
    @AppStorage("reader.pageWidth") private var pageWidth = 760

    @EnvironmentObject private var outline: OutlineContext

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

    private var isPDF: Bool {
        fileURL.pathExtension.lowercased() == "pdf"
    }

    private static let serifFamily =
        "Georgia, 'Palatino', 'Songti SC', 'Noto Serif CJK SC', serif"

    private var previewAppearance: PreviewAppearance {
        var appearance = PreviewAppearance(
            fontSize: previewFontSize, maxWidth: pageWidth
        )
        switch themeName {
        case "serif":
            appearance.fontFamily = Self.serifFamily
        case "sepia":
            appearance.fontFamily = Self.serifFamily
            appearance.pageBackground = "#f6efdf"
            appearance.pageForeground = "#3d3427"
        default:
            break
        }
        return appearance
    }

    var body: some View {
        ZStack {
            mainReader
            if showPresentation {
                PresentationView(markdown: text) {
                    showPresentation = false
                }
                .transition(.opacity)
            }
        }
    }

    private var mainReader: some View {
        Group {
            if isPDF, let pdfData {
                PDFViewer(data: pdfData)
            } else if !isPDF, originalText != nil {
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
        .onAppear {
            previewController.onSelectionAction = { action, color, selection in
                handleSelectionAction(action, color: color, selection: selection)
            }
            previewController.onWikiLink = { name in
                outline.openWiki(name)
            }
            outline.jumpHandler = { line in
                if !showsSideBySide && mode == .write {
                    mode = .preview
                }
                previewController.scrollToLine(line)
            }
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
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("Note text", text: $noteDraft)
            Button("Add") { confirmNote() }
            Button("Cancel", role: .cancel) { pendingNoteSelection = nil }
        } message: {
            Text("The note is attached to the selected text as a footnote.")
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var panes: some View {
        if showsSideBySide {
            HStack(spacing: 0) {
                if showsSource {
                    editorPane
                    Divider()
                }
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
        MarkdownSourceEditor(
            text: $text,
            selection: $editorSelection,
            fontSize: CGFloat(previewFontSize) - 2
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewPane: some View {
        PreviewWebView(
            htmlBody: $htmlBody,
            baseURL: fileURL.deletingLastPathComponent(),
            appearance: previewAppearance,
            documentKey: fileURL.path,
            controller: previewController
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let insightPrompt {
                InsightCard(title: insightTitle, prompt: insightPrompt) {
                    self.insightPrompt = nil
                }
                .padding(16)
            } else if let selectionTranslationText {
                SelectionTranslationCard(
                    sourceText: selectionTranslationText,
                    documentText: text,
                    preferredTarget: translationTarget
                ) {
                    self.selectionTranslationText = nil
                }
                .padding(16)
            }
        }
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
        if !showsSideBySide && !isPDF {
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
            if showsSideBySide && !isPDF {
                Toggle(isOn: $showsSource) {
                    Label("Show Source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            if !isPDF {
            Menu {
                ForEach(outline.headings) { heading in
                    Button {
                        jump(to: heading)
                    } label: {
                        Text(String(repeating: "    ", count: heading.level - 1)
                            + heading.title)
                    }
                }
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            .disabled(outline.headings.isEmpty)

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
                ForEach(InlineFormat.allCases) { format in
                    Button {
                        applyFormat(format)
                    } label: {
                        Label(format.displayName, systemImage: format.systemImage)
                    }
                }
                Divider()
                Button {
                    beginNote()
                } label: {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                }
            } label: {
                Label("Format", systemImage: "bold")
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

            if AIAssist.isAvailable {
                Menu {
                    Button("Summarize Document") {
                        selectionTranslationText = nil
                        insightTitle = "Summary"
                        insightPrompt = AIAssist.summarizePrompt(document: text)
                    }
                } label: {
                    Label("Assistant", systemImage: "sparkles")
                }
            }

            Button {
                showPresentation = true
            } label: {
                Label("Present", systemImage: "play.rectangle")
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

                Divider()

                Picker("Theme", selection: $themeName) {
                    Text("Default").tag("default")
                    Text("Serif").tag("serif")
                    Text("Sepia").tag("sepia")
                }

                Picker("Width", selection: $pageWidth) {
                    Text("Narrow").tag(620)
                    Text("Normal").tag(760)
                    Text("Wide").tag(920)
                }
            } label: {
                Label("Appearance", systemImage: "textformat.size")
            }
            }
        }
    }

    // MARK: - Floating selection toolbar

    private func handleSelectionAction(
        _ action: String, color: String?, selection: PreviewSelection
    ) {
        switch action {
        case "highlight":
            guard let color, let highlightColor = HighlightColor(rawValue: color) else { return }
            if let updated = MarkdownHighlighter.applyToRenderedSelection(
                source: text,
                selectedText: selection.text,
                sourcePos: selection.sourcePos,
                color: highlightColor
            ) {
                text = updated
            } else {
                highlightMessage = "Could not match the selection in the source. "
                    + "Try selecting text without inline formatting."
            }
        case "bold", "underline", "strikethrough":
            guard let format = InlineFormat(rawValue: action) else { return }
            if let updated = MarkdownHighlighter.wrapRenderedSelection(
                source: text,
                selectedText: selection.text,
                sourcePos: selection.sourcePos,
                prefix: format.prefix,
                suffix: format.suffix
            ) {
                text = updated
            } else {
                highlightMessage = "Could not match the selection in the source. "
                    + "Try selecting text without inline formatting."
            }
        case "note":
            pendingNoteSelection = .preview(selection)
            noteDraft = ""
            showNoteAlert = true
        case "translate":
            insightPrompt = nil
            selectionTranslationText = selection.text
        case "explain":
            guard AIAssist.isAvailable else {
                highlightMessage = "On-device intelligence is not available on this system."
                return
            }
            selectionTranslationText = nil
            insightTitle = "Explain"
            insightPrompt = AIAssist.explainPrompt(passage: selection.text)
        case "clear":
            guard let markText = selection.markText else { return }
            if let updated = MarkdownHighlighter.removeHighlight(
                source: text, markText: markText, sourcePos: selection.sourcePos
            ) {
                text = updated
            } else {
                highlightMessage = "Could not find that highlight in the source."
            }
        default:
            break
        }
    }

    // MARK: - Outline, formatting, notes

    private func jump(to heading: OutlineHeading) {
        if !showsSideBySide && mode == .write {
            mode = .preview
        }
        previewController.scrollToLine(heading.line)
    }

    private func applyFormat(_ format: InlineFormat) {
        Task {
            let previewVisible = showsSideBySide || mode == .preview
            if previewVisible,
               let selection = await previewController.currentSelection(),
               !selection.text.isEmpty {
                if let updated = MarkdownHighlighter.wrapRenderedSelection(
                    source: text,
                    selectedText: selection.text,
                    sourcePos: selection.sourcePos,
                    prefix: format.prefix,
                    suffix: format.suffix
                ) {
                    text = updated
                } else {
                    highlightMessage = "Could not match the selection in the source. "
                        + "Try selecting text without inline formatting, or format in Write mode."
                }
                return
            }

            if editorSelection.length > 0,
               let updated = MarkdownHighlighter.wrapSourceRange(
                   text, range: editorSelection,
                   prefix: format.prefix, suffix: format.suffix
               ) {
                text = updated
                return
            }

            highlightMessage = "Select some text in the preview or the editor first."
        }
    }

    private func beginNote() {
        Task {
            let previewVisible = showsSideBySide || mode == .preview
            if previewVisible,
               let selection = await previewController.currentSelection(),
               !selection.text.isEmpty {
                pendingNoteSelection = .preview(selection)
            } else if editorSelection.length > 0 {
                pendingNoteSelection = .editor(editorSelection)
            } else {
                highlightMessage = "Select the text you want to annotate first."
                return
            }
            noteDraft = ""
            showNoteAlert = true
        }
    }

    private func confirmNote() {
        guard let pending = pendingNoteSelection else { return }
        pendingNoteSelection = nil
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        let label = MarkdownNotes.nextLabel(in: text)
        let reference = "[^\(label)]"
        var updated: String?
        switch pending {
        case .preview(let selection):
            updated = MarkdownHighlighter.wrapRenderedSelection(
                source: text,
                selectedText: selection.text,
                sourcePos: selection.sourcePos,
                prefix: "",
                suffix: reference
            )
        case .editor(let range):
            updated = MarkdownHighlighter.wrapSourceRange(
                text, range: range, prefix: "", suffix: reference
            )
        }

        guard let updated else {
            highlightMessage = "Could not match the selection in the source."
            return
        }
        text = MarkdownNotes.appendDefinition(to: updated, label: label, note: note)
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
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            htmlBody = MarkdownHTMLRenderer.renderBody(from: text)
            let headings = MarkdownOutline.headings(in: text)
            if headings != outline.headings {
                outline.headings = headings
            }
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

        if isPDF {
            var coordinatorError: NSError?
            var readResult: Result<Data, Error>?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(
                readingItemAt: fileURL,
                options: [],
                error: &coordinatorError
            ) { url in
                readResult = Result { try Data(contentsOf: url) }
            }
            outline.headings = []
            switch readResult {
            case .success(let data):
                pdfData = data
            case .failure(let error):
                loadError = error.localizedDescription
            case nil:
                loadError = coordinatorError?.localizedDescription
                    ?? "The file could not be read."
            }
            return
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
            outline.headings = MarkdownOutline.headings(in: loadedText)
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
