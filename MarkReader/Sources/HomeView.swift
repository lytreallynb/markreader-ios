import SwiftUI
import UniformTypeIdentifiers

/// Colored file icon: teal for Markdown and text, red for PDF.
struct FileIconView: View {
    let url: URL

    var body: some View {
        if url.pathExtension.lowercased() == "pdf" {
            Image(systemName: "doc.richtext.fill")
                .foregroundStyle(.red)
        } else {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.teal)
        }
    }
}

#if os(macOS)
/// Lazy Finder-like browser row: lists one directory level on expand, so the
/// whole home directory is browsable without ever scanning it up front.
struct SystemBrowserFolder: View {
    let url: URL

    @State private var isExpanded = false
    @State private var entries: [FileNode]?

    private static let shownExtensions: Set<String> = ["md", "markdown", "pdf"]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let entries {
                if entries.isEmpty {
                    Text("No Markdown or PDF files")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entries) { node in
                    if node.isDirectory {
                        SystemBrowserFolder(url: node.url)
                    } else {
                        Label {
                            Text(node.url.deletingPathExtension().lastPathComponent)
                        } icon: {
                            FileIconView(url: node.url)
                        }
                        .lineLimit(1)
                        .tag(node.url)
                    }
                }
            } else {
                Text("Loading")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Label {
                Text(url.lastPathComponent)
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
            }
            .lineLimit(1)
            .selectionDisabled(true)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && entries == nil {
                loadEntries()
            }
        }
    }

    private func loadEntries() {
        let target = url
        Task.detached(priority: .userInitiated) {
            let listed = (try? FileManager.default.contentsOfDirectory(
                at: target,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            var folders: [FileNode] = []
            var files: [FileNode] = []
            for entry in listed {
                let isDirectory = (try? entry.resourceValues(
                    forKeys: [.isDirectoryKey]
                ))?.isDirectory ?? false
                if isDirectory {
                    folders.append(FileNode(
                        url: entry, name: entry.lastPathComponent,
                        isDirectory: true, children: nil
                    ))
                } else if Self.shownExtensions.contains(entry.pathExtension.lowercased()) {
                    files.append(FileNode(
                        url: entry, name: entry.lastPathComponent,
                        isDirectory: false, children: nil
                    ))
                }
            }
            let sortByName: (FileNode, FileNode) -> Bool = {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let result = folders.sorted(by: sortByName) + files.sorted(by: sortByName)
            await MainActor.run {
                entries = result
            }
        }
    }
}
#endif

struct HomeView: View {
    @EnvironmentObject private var store: RecentFilesStore
    @EnvironmentObject private var treeStore: FileTreeStore
    @EnvironmentObject private var outline: OutlineContext

    @AppStorage("sidebar.recentExpanded") private var recentExpanded = true
    @AppStorage("sidebar.homeExpanded") private var homeExpanded = false
    @AppStorage("sidebar.folderExpanded") private var folderExpanded = true
    @AppStorage("help.shownOnce") private var helpShownOnce = false
    @State private var showHelp = false
    @State private var importerMode: ImporterMode?
    #if os(macOS)
    @State private var showPalette = false
    @State private var paletteMode: CommandPaletteView.Mode = .files
    @State private var showDigest = false
    @State private var backlinks: [ScanHit] = []
    @State private var showRenameAlert = false
    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var showNewFileAlert = false
    @State private var newFileFolder: URL?
    @State private var newFileName = ""
    #endif
    // The dismiss binding clears importerMode before the completion handler
    // runs, so the completion must not read it. This copy survives dismissal.
    @State private var lastPickedMode: ImporterMode = .file
    @State private var errorMessage: String?
    #if os(macOS)
    @State private var selectedURL: URL?
    #else
    @State private var path: [URL] = []
    #endif

    private enum ImporterMode: Identifiable {
        case file
        case folder

        var id: Int {
            switch self {
            case .file: return 0
            case .folder: return 1
            }
        }
    }

    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    var body: some View {
        mainContent
            .fileImporter(
                isPresented: Binding(
                    get: { importerMode != nil },
                    set: { if !$0 { importerMode = nil } }
                ),
                allowedContentTypes: importerMode == .folder
                    ? [.folder]
                    : [Self.markdownType, .plainText, .text, .pdf],
                allowsMultipleSelection: false
            ) { result in
                importerMode = nil
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if lastPickedMode == .folder {
                        treeStore.openFolder(url)
                    } else {
                        open(url: url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .onOpenURL { url in
                // inkdown://open?path=/... lets Shortcuts and automation open
                // a specific file; anything else is a document URL.
                if url.scheme == "inkdown" {
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                        open(url: URL(fileURLWithPath: path))
                    }
                    return
                }
                open(url: url)
            }
            .onAppear {
                outline.wikiResolver = { name in
                    resolveWikiLink(name)
                }
                if !helpShownOnce {
                    helpShownOnce = true
                    showHelp = true
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpView { showHelp = false }
            }
            #if os(macOS)
            .onReceive(OpenFileRouter.shared.$pendingURL) { url in
                guard let url else { return }
                OpenFileRouter.shared.pendingURL = nil
                open(url: url)
            }
            #endif
            .alert(
                "Could not open file",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: - macOS: split view with folder tree sidebar

    #if os(macOS)
    private var mainContent: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if showDigest {
                HighlightsDigestView(
                    files: FolderScanner.markdownFiles(in: treeStore.tree)
                ) { url, line in
                    showDigest = false
                    open(url: url)
                    jumpAfterOpen(line: line)
                }
            } else if let selectedURL {
                ReaderView(fileURL: selectedURL)
                    .id(selectedURL)
            } else {
                emptyDetail
            }
        }
        .overlay {
            if showPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { showPalette = false }
                    CommandPaletteView(
                        mode: paletteMode,
                        tree: treeStore.tree,
                        onOpen: { url, line in
                            showPalette = false
                            showDigest = false
                            open(url: url)
                            if let line {
                                jumpAfterOpen(line: line)
                            }
                        },
                        onClose: { showPalette = false }
                    )
                    .padding(.top, 90)
                }
            }
        }
        .background {
            Group {
                Button("") { presentPalette(.files) }
                    .keyboardShortcut("p", modifiers: .command)
                Button("") { presentPalette(.content) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("") { showDigest = true; selectedURL = nil }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            .hidden()
        }
        .onChange(of: selectedURL) { _, url in
            guard let url else { return }
            showDigest = false
            store.add(url: url)
            ensureTreeShows(url)
            refreshBacklinks(for: url)
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New File", isPresented: $showNewFileAlert) {
            TextField("File name", text: $newFileName)
            Button("Create") { performCreateFile() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Sidebar tree rows: folders, files, and, under the open file, its
    /// headings as expandable children.
    private struct SidebarItem: Identifiable, Hashable {
        enum Kind: Hashable {
            case folder
            case file
            case heading(level: Int, line: Int)
        }

        let id: String
        let title: String
        let kind: Kind
        let url: URL
        var children: [SidebarItem]?
    }

    /// Files map to their row plus, when the file is the open one, its
    /// heading rows directly below: the outline expands automatically on
    /// open instead of hiding behind a disclosure chevron.
    private func sidebarItems(from nodes: [FileNode]) -> [SidebarItem] {
        nodes.flatMap { node -> [SidebarItem] in
            if node.isDirectory {
                return [SidebarItem(
                    id: node.url.path,
                    title: node.name,
                    kind: .folder,
                    url: node.url,
                    children: sidebarItems(from: node.children ?? [])
                )]
            }
            var items = [SidebarItem(
                id: node.url.path,
                title: node.url.deletingPathExtension().lastPathComponent,
                kind: .file,
                url: node.url,
                children: nil
            )]
            if node.url == selectedURL {
                items += outline.headings.map { heading in
                    SidebarItem(
                        id: "\(node.url.path)#\(heading.line)",
                        title: heading.title,
                        kind: .heading(level: heading.level, line: heading.line),
                        url: node.url,
                        children: nil
                    )
                }
            }
            return items
        }
    }

    @ViewBuilder
    private func sidebarRow(for item: SidebarItem) -> some View {
        switch item.kind {
        case .folder:
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
            }
            .lineLimit(1)
            .selectionDisabled(true)
            .contextMenu {
                fileOperationMenu(for: item.url, isDirectory: true)
            }
        case .file:
            Label {
                Text(item.title)
            } icon: {
                FileIconView(url: item.url)
            }
            .lineLimit(1)
            .tag(item.url)
            .contextMenu {
                fileOperationMenu(for: item.url, isDirectory: false)
            }
        case .heading(let level, let line):
            Button {
                outline.jump(toLine: line)
            } label: {
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 22 + CGFloat(max(0, level - 1)) * 10)
            }
            .buttonStyle(.plain)
            .selectionDisabled(true)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedURL) {
            Section(isExpanded: $homeExpanded) {
                SystemBrowserFolder(
                    url: FileManager.default.homeDirectoryForCurrentUser
                )
            } header: {
                Text("Home")
            }

            if !treeStore.tree.isEmpty {
                Section(isExpanded: $folderExpanded) {
                    OutlineGroup(sidebarItems(from: treeStore.tree), children: \.children) { item in
                        sidebarRow(for: item)
                    }
                } header: {
                    Text(treeStore.rootURL?.lastPathComponent ?? "Folder")
                }
            }

            if let selectedURL,
               !outline.headings.isEmpty,
               !treeContains(selectedURL, in: treeStore.tree) {
                Section("Outline") {
                    ForEach(outline.headings) { heading in
                        Button {
                            outline.jump(toLine: heading.line)
                        } label: {
                            Text(heading.title)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
                        }
                        .buttonStyle(.plain)
                        .selectionDisabled(true)
                    }
                }
            }

            if !backlinks.isEmpty {
                Section("Backlinks") {
                    ForEach(backlinks) { hit in
                        Button {
                            open(url: hit.url)
                        } label: {
                            Label {
                                Text(hit.fileTitle)
                            } icon: {
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .selectionDisabled(true)
                    }
                }
            }

            if !store.recents.isEmpty {
                Section(isExpanded: $recentExpanded) {
                    let shown = Array(store.recents.prefix(10))
                    let ambiguous = Self.ambiguousNames(in: shown)
                    ForEach(shown) { file in
                        Button {
                            if let url = store.resolveURL(for: file) {
                                open(url: url)
                            } else {
                                errorMessage = "The file may have been moved or deleted."
                            }
                        } label: {
                            HStack(spacing: 7) {
                                FileIconView(url: URL(
                                    fileURLWithPath: file.path ?? file.name
                                ))
                                Text((file.name as NSString).deletingPathExtension)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                // Folder shown only when two recents share a
                                // name; keeps rows to a single clean line.
                                if ambiguous.contains(file.name.lowercased()),
                                   let parent = file.parentFolderName {
                                    Text(parent)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .selectionDisabled(true)
                        .contextMenu {
                            Button("Remove from Recent", role: .destructive) {
                                store.remove(file)
                            }
                        }
                    }
                } header: {
                    Text("Recent")
                }
            }

            if treeStore.tree.isEmpty && store.recents.isEmpty {
                emptySidebarHint
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MarkReader")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Open File") { presentImporter(.file) }
                    Button("Open Folder") { presentImporter(.folder) }
                    Button("New File") {
                        newFileFolder = treeStore.rootURL
                        newFileName = "Untitled.md"
                        showNewFileAlert = true
                    }
                    .disabled(treeStore.rootURL == nil)
                    Divider()
                    Button("Refresh Folder") { treeStore.refresh() }
                        .disabled(treeStore.rootURL == nil)
                    Button("Close Folder") { treeStore.closeFolder() }
                        .disabled(treeStore.rootURL == nil)
                    Divider()
                    Button("Quick Open") { presentPalette(.files) }
                    Button("Search in Folder") { presentPalette(.content) }
                        .disabled(treeStore.tree.isEmpty)
                    Button("All Highlights") {
                        selectedURL = nil
                        showDigest = true
                    }
                    .disabled(treeStore.tree.isEmpty)
                    Divider()
                    Button("Set as Default Markdown App") { setAsDefaultMarkdownApp() }
                    Button("Help") { showHelp = true }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var emptySidebarHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open a folder to browse its Markdown files, or open a single file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Folder") { presentImporter(.folder) }
            Button("Open File") { presentImporter(.file) }
        }
        .padding(.vertical, 8)
    }

    private var emptyDetail: some View {
        ContentUnavailableView {
            Label("No File Selected", systemImage: "doc.text")
        } description: {
            Text("Select a file in the sidebar, or open one from Finder.")
        }
    }

    private static func ambiguousNames(in files: [RecentFile]) -> Set<String> {
        var seen: Set<String> = []
        var duplicated: Set<String> = []
        for file in files {
            let key = file.name.lowercased()
            if !seen.insert(key).inserted {
                duplicated.insert(key)
            }
        }
        return duplicated
    }

    private func presentPalette(_ mode: CommandPaletteView.Mode) {
        paletteMode = mode
        showPalette = true
    }

    /// Opens happen through selection change and the reader view needs a
    /// moment to install its jump handler before we can scroll to a line.
    private func jumpAfterOpen(line: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            outline.jump(toLine: line)
        }
    }

    private func refreshBacklinks(for url: URL) {
        backlinks = []
        guard url.pathExtension.lowercased() != "pdf" else { return }
        let name = url.deletingPathExtension().lastPathComponent
        let files = FolderScanner.markdownFiles(in: treeStore.tree)
        guard !files.isEmpty else { return }
        Task {
            let hits = await Task.detached(priority: .utility) {
                FolderScanner.backlinks(to: name, in: files)
            }.value
            if selectedURL == url {
                backlinks = hits
            }
        }
    }

    // MARK: - File operations

    @ViewBuilder
    private func fileOperationMenu(for url: URL, isDirectory: Bool) -> some View {
        Button("Rename") {
            renameTarget = url
            renameText = url.lastPathComponent
            showRenameAlert = true
        }
        Button("New File \(isDirectory ? "Here" : "in Folder")") {
            newFileFolder = isDirectory ? url : url.deletingLastPathComponent()
            newFileName = "Untitled.md"
            showNewFileAlert = true
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            moveToTrash(url)
        }
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        var name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }

        let isDirectory = (try? target.resourceValues(
            forKeys: [.isDirectoryKey]
        ))?.isDirectory ?? false
        if !isDirectory, !name.contains("."), !target.pathExtension.isEmpty {
            name += "." + target.pathExtension
        }

        let destination = target.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: target, to: destination)
            store.remove(path: target.path)
            if selectedURL == target {
                open(url: destination)
            }
            treeStore.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performCreateFile() {
        guard let folder = newFileFolder else { return }
        var name = newFileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }
        if !name.contains(".") {
            name += ".md"
        }

        let destination = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A file named \(name) already exists."
            return
        }
        let title = (name as NSString).deletingPathExtension
        do {
            try Data("# \(title)\n".utf8).write(to: destination)
            treeStore.refresh()
            open(url: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToTrash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            store.remove(path: url.path)
            if selectedURL == url {
                selectedURL = nil
            }
            treeStore.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setAsDefaultMarkdownApp() {
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: Bundle.main.bundleURL,
                    toOpen: Self.markdownType
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    #else

    // MARK: - iOS: navigation stack with folder tree and recents

    private var mainContent: some View {
        NavigationStack(path: $path) {
            List {
                if !treeStore.tree.isEmpty {
                    Section(folderSectionTitle) {
                        OutlineGroup(treeStore.tree, children: \.children) { node in
                            if node.isDirectory {
                                Label {
                                    Text(node.name)
                                } icon: {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                }
                                .lineLimit(1)
                            } else {
                                Button {
                                    open(url: node.url)
                                } label: {
                                    Label {
                                        Text(node.url.deletingPathExtension().lastPathComponent)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        FileIconView(url: node.url)
                                    }
                                    .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                if !store.recents.isEmpty {
                    Section("Recent") {
                        ForEach(store.recents) { file in
                            Button {
                                if let url = store.resolveURL(for: file) {
                                    open(url: url)
                                } else {
                                    errorMessage = "The file may have been moved or deleted."
                                }
                            } label: {
                                Label {
                                    Text((file.name as NSString).deletingPathExtension)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    FileIconView(url: URL(
                                        fileURLWithPath: file.path ?? file.name
                                    ))
                                }
                                .lineLimit(1)
                            }
                        }
                        .onDelete { offsets in
                            store.remove(at: offsets)
                        }
                    }
                }

                if treeStore.tree.isEmpty && store.recents.isEmpty {
                    ContentUnavailableView {
                        Label("No Files Yet", systemImage: "doc.text")
                    } description: {
                        Text("Open a file or folder from iCloud Drive, or drop Markdown files into the Inkdown folder in the Files app.")
                    } actions: {
                        Button("Open File") {
                            presentImporter(.file)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Inkdown")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Open File") { presentImporter(.file) }
                        Button("Open Folder") { presentImporter(.folder) }
                        Button("Show My Files") { openDocumentsFolder() }
                        Divider()
                        Button("Help") { showHelp = true }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: URL.self) { url in
                ReaderView(fileURL: url)
            }
            .onAppear {
                if treeStore.rootURL == nil {
                    openDocumentsFolder()
                }
                // Automation hook for screenshots and UI tests.
                if let auto = ProcessInfo.processInfo.environment["INKDOWN_AUTO_OPEN"],
                   path.isEmpty {
                    open(url: URL(fileURLWithPath: auto))
                }
            }
        }
    }

    private var folderSectionTitle: String {
        let name = treeStore.rootURL?.lastPathComponent ?? "Folder"
        return name == "Documents" ? "My Files" : name
    }

    /// The app's own Documents folder, visible in the Files app thanks to
    /// UIFileSharingEnabled, so files dropped there are always readable.
    private func openDocumentsFolder() {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        treeStore.openFolder(documents)
    }
    #endif

    private func resolveWikiLink(_ name: String) {
        let lower = name.lowercased()
        #if os(macOS)
        if let url = findFile(named: lower, in: treeStore.tree) {
            open(url: url)
            return
        }
        #endif
        if let file = store.recents.first(where: {
            ($0.name as NSString).deletingPathExtension.lowercased() == lower
        }), let url = store.resolveURL(for: file) {
            open(url: url)
            return
        }
        errorMessage = "Note \(name) was not found in the open folder."
    }

    #if os(macOS)
    private func findFile(named lowercasedName: String, in nodes: [FileNode]) -> URL? {
        for node in nodes {
            if node.isDirectory {
                if let hit = findFile(named: lowercasedName, in: node.children ?? []) {
                    return hit
                }
            } else if node.url.deletingPathExtension().lastPathComponent.lowercased()
                == lowercasedName {
                return node.url
            }
        }
        return nil
    }
    #endif

    private func presentImporter(_ mode: ImporterMode) {
        lastPickedMode = mode
        importerMode = mode
    }

    private func open(url rawURL: URL) {
        // A folder can arrive here regardless of picker mode, for example
        // dropped on the Dock icon. Browse it instead of reading it as text.
        let isDirectory = (try? rawURL.resourceValues(
            forKeys: [.isDirectoryKey]
        ))?.isDirectory ?? rawURL.hasDirectoryPath
        #if os(macOS)
        if isDirectory {
            treeStore.openFolder(rawURL)
            return
        }
        let url = rawURL.canonicalized
        store.add(url: url)
        ensureTreeShows(url)
        selectedURL = url
        #else
        if isDirectory {
            treeStore.openFolder(rawURL)
            return
        }
        store.add(url: rawURL)
        path.append(rawURL)
        #endif
    }

    #if os(macOS)
    /// Loads the file's folder into the sidebar tree, but only when no folder
    /// is open yet. Replacing an existing tree on every open made the sidebar
    /// jump around; files outside the tree get a standalone Outline section
    /// instead.
    private func ensureTreeShows(_ url: URL) {
        guard treeStore.rootURL == nil else { return }
        treeStore.openFolder(url.deletingLastPathComponent())
    }

    private func treeContains(_ url: URL, in nodes: [FileNode]) -> Bool {
        for node in nodes {
            if node.isDirectory {
                if treeContains(url, in: node.children ?? []) {
                    return true
                }
            } else if node.url == url {
                return true
            }
        }
        return false
    }
    #endif
}
