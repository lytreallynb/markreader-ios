import SwiftUI
import MarkdownUI

struct ReaderView: View {
    let fileURL: URL

    @State private var content: String?
    @State private var loadError: String?
    @AppStorage("reader.textSizeStep") private var textSizeStep: Int = 2

    private static let typeSizes: [DynamicTypeSize] = [
        .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    ]

    var body: some View {
        Group {
            if let content {
                ScrollView {
                    Markdown(content)
                        .markdownTheme(.gitHub)
                        .markdownTextStyle(\.code) {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.88))
                        }
                        .dynamicTypeSize(currentTypeSize)
                        .textSelection(.enabled)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("Could Not Load File", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if textSizeStep > 0 { textSizeStep -= 1 }
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(textSizeStep == 0)

                Button {
                    if textSizeStep < Self.typeSizes.count - 1 { textSizeStep += 1 }
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(textSizeStep == Self.typeSizes.count - 1)
            }
        }
        .task(id: fileURL) {
            load()
        }
        .refreshable {
            load()
        }
    }

    private var currentTypeSize: DynamicTypeSize {
        let index = min(max(textSizeStep, 0), Self.typeSizes.count - 1)
        return Self.typeSizes[index]
    }

    private func load() {
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
            content = nil
            return
        }

        switch readResult {
        case .success(let text):
            content = text
            loadError = nil
        case .failure(let error):
            loadError = error.localizedDescription
            content = nil
        case nil:
            loadError = "The file could not be read."
            content = nil
        }
    }
}
