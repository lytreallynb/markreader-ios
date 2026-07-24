import Foundation

/// One match from a folder-wide content scan.
struct ScanHit: Identifiable, Hashable {
    let url: URL
    let line: Int
    let text: String

    var id: String { "\(url.path)#\(line)" }

    var fileTitle: String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// Shared scanning engine for full-text search, the highlights digest, and
/// backlinks. Walks the Markdown files of a folder tree off the main thread.
enum FolderScanner {
    nonisolated static let maxFiles = 2000
    nonisolated static let maxHits = 300

    /// Flattens a folder tree into its Markdown file URLs.
    nonisolated static func markdownFiles(in nodes: [FileNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes {
            if node.isDirectory {
                result.append(contentsOf: markdownFiles(in: node.children ?? []))
            } else if node.url.pathExtension.lowercased() != "pdf" {
                result.append(node.url)
            }
            if result.count >= maxFiles {
                break
            }
        }
        return result
    }

    /// Case-insensitive substring search over file contents.
    nonisolated static func search(query: String, in files: [URL]) -> [ScanHit] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [ScanHit] = []

        for url in files {
            guard let content = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for (index, line) in content.components(separatedBy: "\n").enumerated() {
                guard line.lowercased().contains(needle) else { continue }
                hits.append(ScanHit(
                    url: url,
                    line: index + 1,
                    text: line.trimmingCharacters(in: .whitespaces)
                ))
                if hits.count >= maxHits {
                    return hits
                }
            }
        }
        return hits
    }

    private static let highlightPatterns = [
        try! NSRegularExpression(pattern: "==([^=\\n]+)=="),
        try! NSRegularExpression(pattern: "<mark[^>]*>([^<\\n]+)</mark>"),
        try! NSRegularExpression(pattern: "^\\[\\^n\\d+\\]:[ \\t]*(.+)$", options: [.anchorsMatchLines]),
    ]

    /// Collects all highlights and footnote notes across the files.
    nonisolated static func highlights(in files: [URL]) -> [ScanHit] {
        var hits: [ScanHit] = []
        for url in files {
            guard let content = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for (index, line) in content.components(separatedBy: "\n").enumerated() {
                for pattern in highlightPatterns {
                    let nsLine = line as NSString
                    pattern.enumerateMatches(
                        in: line, range: NSRange(location: 0, length: nsLine.length)
                    ) { match, _, _ in
                        guard let match, match.numberOfRanges > 1 else { return }
                        let captured = nsLine.substring(with: match.range(at: 1))
                            .trimmingCharacters(in: .whitespaces)
                        guard !captured.isEmpty else { return }
                        hits.append(ScanHit(url: url, line: index + 1, text: captured))
                    }
                }
                if hits.count >= maxHits {
                    return hits
                }
            }
        }
        return hits
    }

    /// Files that contain a [[wiki link]] to the given note name.
    nonisolated static func backlinks(to noteName: String, in files: [URL]) -> [ScanHit] {
        let needle = "[[\(noteName.lowercased())"
        var hits: [ScanHit] = []
        for url in files {
            guard url.deletingPathExtension().lastPathComponent.lowercased()
                != noteName.lowercased()
            else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for (index, line) in content.components(separatedBy: "\n").enumerated() {
                guard line.lowercased().contains(needle) else { continue }
                hits.append(ScanHit(
                    url: url,
                    line: index + 1,
                    text: line.trimmingCharacters(in: .whitespaces)
                ))
                break
            }
        }
        return hits
    }
}
