import SwiftUI

#if os(macOS)

/// Spotlight-style palette: fuzzy file open or folder-wide content search.
struct CommandPaletteView: View {
    enum Mode {
        case files
        case content
    }

    let mode: Mode
    let tree: [FileNode]
    let onOpen: (URL, Int?) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var allFiles: [URL] = []
    @State private var fileResults: [URL] = []
    @State private var contentResults: [ScanHit] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: mode == .files ? "doc.text.magnifyingglass" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    mode == .files ? "Open file by name" : "Search text in folder",
                    text: $query
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit { submitFirst() }
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if mode == .files {
                        ForEach(fileResults, id: \.self) { url in
                            resultRow {
                                onOpen(url, nil)
                            } content: {
                                HStack(spacing: 8) {
                                    FileIconView(url: url)
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Spacer()
                                    Text(url.deletingLastPathComponent().lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        ForEach(contentResults) { hit in
                            resultRow {
                                onOpen(hit.url, hit.line)
                            } content: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.text)
                                        .lineLimit(1)
                                    Text("\(hit.fileTitle) · line \(hit.line)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if resultsAreEmpty && !query.isEmpty {
                        Text("No results")
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 580)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
        .onAppear {
            allFiles = FolderScanner.markdownFiles(in: tree)
            focused = true
            runQuery()
        }
        .onChange(of: query) { _, _ in
            runQuery()
        }
        .onExitCommand {
            onClose()
        }
    }

    private var resultsAreEmpty: Bool {
        mode == .files ? fileResults.isEmpty : contentResults.isEmpty
    }

    private func resultRow<Content: View>(
        action: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submitFirst() {
        if mode == .files, let first = fileResults.first {
            onOpen(first, nil)
        } else if mode == .content, let first = contentResults.first {
            onOpen(first.url, first.line)
        }
    }

    private func runQuery() {
        if mode == .files {
            fileResults = Self.fuzzyFilter(files: allFiles, query: query)
            return
        }
        searchTask?.cancel()
        let currentQuery = query
        let files = allFiles
        guard currentQuery.count >= 2 else {
            contentResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) {
                FolderScanner.search(query: currentQuery, in: files)
            }.value
            guard !Task.isCancelled, currentQuery == query else { return }
            contentResults = hits
        }
    }

    /// Prefix matches first, then substring, then in-order subsequence.
    static func fuzzyFilter(files: [URL], query: String) -> [URL] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return Array(files.prefix(30)) }

        var prefix: [URL] = []
        var contains: [URL] = []
        var subsequence: [URL] = []
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            if name.hasPrefix(needle) {
                prefix.append(url)
            } else if name.contains(needle) {
                contains.append(url)
            } else if isSubsequence(needle, of: name) {
                subsequence.append(url)
            }
        }
        return Array((prefix + contains + subsequence).prefix(30))
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        outer: for char in needle {
            while let candidate = iterator.next() {
                if candidate == char {
                    continue outer
                }
            }
            return false
        }
        return true
    }
}

/// Aggregated review of every highlight and note across the open folder.
struct HighlightsDigestView: View {
    let files: [URL]
    let onOpen: (URL, Int) -> Void

    @State private var hits: [ScanHit] = []
    @State private var loading = true

    private var grouped: [(URL, [ScanHit])] {
        Dictionary(grouping: hits, by: \.url)
            .sorted { $0.key.path < $1.key.path }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView("Collecting highlights")
            } else if hits.isEmpty {
                ContentUnavailableView {
                    Label("No Highlights Yet", systemImage: "highlighter")
                } description: {
                    Text("Highlights and notes you make in this folder show up here.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.0) { url, fileHits in
                        Section(url.deletingPathExtension().lastPathComponent) {
                            ForEach(fileHits) { hit in
                                Button {
                                    onOpen(hit.url, hit.line)
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(hit.text)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                Color.yellow.opacity(0.35),
                                                in: RoundedRectangle(cornerRadius: 4)
                                            )
                                        Spacer()
                                        Text("line \(hit.line)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Highlights")
        .task {
            let target = files
            hits = await Task.detached(priority: .userInitiated) {
                FolderScanner.highlights(in: target)
            }.value
            loading = false
        }
    }
}
#endif
