import Foundation

struct RecentFile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bookmark: Data
    var lastOpened: Date
    // Full path at the time the file was opened. Used to deduplicate and to
    // show the parent folder, without resolving the bookmark during list
    // rendering. Optional because entries saved by older versions lack it.
    var path: String?

    var parentFolderName: String? {
        guard let path else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }
}

@MainActor
final class RecentFilesStore: ObservableObject {
    @Published private(set) var recents: [RecentFile] = []

    private let storageKey = "recentFiles.v1"
    private let maxRecents = 30

    init() {
        load()
    }

    func add(url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        let name = url.lastPathComponent
        let path = url.path
        recents.removeAll {
            $0.path == path || ($0.path == nil && $0.name == name)
        }
        recents.insert(
            RecentFile(
                id: UUID(), name: name, bookmark: bookmark,
                lastOpened: Date(), path: path
            ),
            at: 0
        )
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where recents.indices.contains(index) {
            recents.remove(at: index)
        }
        save()
    }

    func remove(_ file: RecentFile) {
        recents.removeAll { $0.id == file.id }
        save()
    }

    func remove(path: String) {
        recents.removeAll { $0.path == path }
        save()
    }

    func resolveURL(for file: RecentFile) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: file.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale, let fresh = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ), let index = recents.firstIndex(of: file) {
            recents[index].bookmark = fresh
            save()
        }
        // Canonicalize only on macOS (needed so sidebar tree URLs compare
        // equal). On iOS the security scope is tied to this exact URL object,
        // and the app is sandboxed, so it must be returned as is.
        #if os(macOS)
        return url.canonicalized
        #else
        return url
        #endif
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentFile].self, from: data)
        else { return }
        recents = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
