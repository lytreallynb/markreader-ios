import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var store: RecentFilesStore
    @EnvironmentObject private var treeStore: FileTreeStore
    @EnvironmentObject private var outline: OutlineContext

    @State private var importerMode: ImporterMode?
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
                    : [Self.markdownType, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                let mode = importerMode
                importerMode = nil
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if mode == .folder {
                        treeStore.openFolder(url)
                    } else {
                        open(url: url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .onOpenURL { url in
                open(url: url)
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
            if let selectedURL {
                ReaderView(fileURL: selectedURL)
                    .id(selectedURL)
            } else {
                emptyDetail
            }
        }
        .onChange(of: selectedURL) { _, url in
            guard let url else { return }
            store.add(url: url)
            ensureTreeShows(url)
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

    private func sidebarItems(from nodes: [FileNode]) -> [SidebarItem] {
        nodes.map { node in
            if node.isDirectory {
                return SidebarItem(
                    id: node.url.path,
                    title: node.name,
                    kind: .folder,
                    url: node.url,
                    children: sidebarItems(from: node.children ?? [])
                )
            }
            var children: [SidebarItem]?
            if node.url == selectedURL, !outline.headings.isEmpty {
                children = outline.headings.map { heading in
                    SidebarItem(
                        id: "\(node.url.path)#\(heading.line)",
                        title: heading.title,
                        kind: .heading(level: heading.level, line: heading.line),
                        url: node.url,
                        children: nil
                    )
                }
            }
            return SidebarItem(
                id: node.url.path,
                title: node.url.deletingPathExtension().lastPathComponent,
                kind: .file,
                url: node.url,
                children: children
            )
        }
    }

    @ViewBuilder
    private func sidebarRow(for item: SidebarItem) -> some View {
        switch item.kind {
        case .folder:
            Label(item.title, systemImage: "folder")
                .lineLimit(1)
                .selectionDisabled(true)
        case .file:
            Label(item.title, systemImage: "doc.text")
                .lineLimit(1)
                .tag(item.url)
        case .heading(let level, let line):
            Button {
                outline.jump(toLine: line)
            } label: {
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, CGFloat(max(0, level - 1)) * 10)
            }
            .buttonStyle(.plain)
            .selectionDisabled(true)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedURL) {
            if !treeStore.tree.isEmpty {
                Section(treeStore.rootURL?.lastPathComponent ?? "Folder") {
                    OutlineGroup(sidebarItems(from: treeStore.tree), children: \.children) { item in
                        sidebarRow(for: item)
                    }
                }
            }

            if !store.recents.isEmpty {
                Section("Recent") {
                    ForEach(store.recents) { file in
                        if let url = store.resolveURL(for: file) {
                            Label(
                                url.deletingPathExtension().lastPathComponent,
                                systemImage: "clock"
                            )
                            .lineLimit(1)
                            .tag(url)
                        }
                    }
                    .onDelete { offsets in
                        store.remove(at: offsets)
                    }
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
                    Button("Open File") { importerMode = .file }
                    Button("Open Folder") { importerMode = .folder }
                    Divider()
                    Button("Refresh Folder") { treeStore.refresh() }
                        .disabled(treeStore.rootURL == nil)
                    Button("Close Folder") { treeStore.closeFolder() }
                        .disabled(treeStore.rootURL == nil)
                    Divider()
                    Button("Set as Default Markdown App") { setAsDefaultMarkdownApp() }
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
            Button("Open Folder") { importerMode = .folder }
            Button("Open File") { importerMode = .file }
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

    // MARK: - iOS: navigation stack with recents

    private var mainContent: some View {
        NavigationStack(path: $path) {
            Group {
                if store.recents.isEmpty {
                    emptyState
                } else {
                    recentsList
                }
            }
            .navigationTitle("MarkReader")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importerMode = .file
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                }
            }
            .navigationDestination(for: URL.self) { url in
                ReaderView(fileURL: url)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Files Yet", systemImage: "doc.text")
        } description: {
            Text("Open a Markdown file from iCloud Drive or the Files app to start reading.")
        } actions: {
            Button("Open File") {
                importerMode = .file
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var recentsList: some View {
        List {
            Section("Recent") {
                ForEach(store.recents) { file in
                    Button {
                        if let url = store.resolveURL(for: file) {
                            open(url: url)
                        } else {
                            errorMessage = "The file may have been moved or deleted."
                        }
                    } label: {
                        Label(file.name, systemImage: "doc.text")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .onDelete { offsets in
                    store.remove(at: offsets)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    #endif

    private func open(url rawURL: URL) {
        #if os(macOS)
        let url = rawURL.canonicalized
        store.add(url: url)
        ensureTreeShows(url)
        selectedURL = url
        #else
        store.add(url: rawURL)
        path.append(rawURL)
        #endif
    }

    #if os(macOS)
    /// Shows the file's folder as the sidebar tree automatically, so the user
    /// never has to pick a folder by hand. Runs on every selection change
    /// (tree, recents, picker, Finder). Keeps the current tree when the file
    /// already lives inside it.
    private func ensureTreeShows(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        let insideCurrentTree = treeStore.rootURL.map {
            url.path.hasPrefix($0.path + "/")
        } ?? false
        if !insideCurrentTree {
            treeStore.openFolder(parent)
        }
    }
    #endif
}
