import Foundation

#if os(macOS)
import AppKit
#endif

extension URL {
    /// Resolves symlinks and firmlinks (such as the /System/Volumes/Data
    /// prefix that bookmark resolution adds on macOS) so URLs for the same
    /// file compare equal regardless of how they were obtained.
    var canonicalized: URL {
        if let path = (try? resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath {
            return URL(fileURLWithPath: path)
        }
        return standardizedFileURL.resolvingSymlinksInPath()
    }
}

/// A node in the folder tree. Folders carry children; Markdown files are leaves.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var id: URL { url }
}

/// Holds the folder the user opened for browsing: persists a security-scoped
/// bookmark, keeps access alive while the app runs, and builds the tree of
/// Markdown files inside it.
@MainActor
final class FileTreeStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var tree: [FileNode] = []

    private let storageKey = "openedFolderBookmark.v1"
    private var accessedURL: URL?

    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let maxDepth = 8

    init() {
        restore()
        #if os(macOS)
        // Pick up files created, renamed, or deleted outside the app whenever
        // it comes back to the foreground.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        #endif
    }

    func openFolder(_ url: URL) {
        stopAccess()
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
        rootURL = url.canonicalized
        if let bookmark = try? url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: storageKey)
        }
        refresh()
    }

    func closeFolder() {
        stopAccess()
        rootURL = nil
        tree = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func refresh() {
        guard let rootURL else {
            tree = []
            return
        }
        tree = Self.buildChildren(of: rootURL, depth: 0) ?? []
    }

    private func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: storageKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
        if isStale, let fresh = try? url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: storageKey)
        }
        rootURL = url.canonicalized
        refresh()
    }

    private func stopAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    /// Returns the Markdown-bearing children of a folder: subfolders that
    /// contain Markdown somewhere below them, and Markdown files themselves.
    /// Folders sort before files, both alphabetically.
    private static func buildChildren(of url: URL, depth: Int) -> [FileNode]? {
        guard depth < maxDepth else { return nil }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(
                forKeys: [.isDirectoryKey]
            ))?.isDirectory ?? false

            if isDirectory {
                if let children = buildChildren(of: entry, depth: depth + 1),
                   !children.isEmpty {
                    folders.append(FileNode(
                        url: entry,
                        name: entry.lastPathComponent,
                        isDirectory: true,
                        children: children
                    ))
                }
            } else if markdownExtensions.contains(entry.pathExtension.lowercased()) {
                files.append(FileNode(
                    url: entry,
                    name: entry.lastPathComponent,
                    isDirectory: false,
                    children: nil
                ))
            }
        }

        let sortByName: (FileNode, FileNode) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return folders.sorted(by: sortByName) + files.sorted(by: sortByName)
    }
}
