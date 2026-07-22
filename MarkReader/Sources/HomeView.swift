import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var store: RecentFilesStore
    @State private var showImporter = false
    @State private var path: [URL] = []
    @State private var errorMessage: String?

    private static let markdownType = UTType(
        importedAs: "net.daringfireball.markdown"
    )

    var body: some View {
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
                        showImporter = true
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                }
            }
            .navigationDestination(for: URL.self) { url in
                ReaderView(fileURL: url)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [Self.markdownType, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    open(url: url)
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            open(url: url)
        }
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Files Yet", systemImage: "doc.text")
        } description: {
            Text("Open a Markdown file from iCloud Drive or the Files app to start reading.")
        } actions: {
            Button("Open File") {
                showImporter = true
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
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(file.lastOpened, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    store.remove(at: offsets)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private func open(url: URL) {
        store.add(url: url)
        path.append(url)
    }
}
