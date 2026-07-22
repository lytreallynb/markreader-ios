import SwiftUI

#if os(macOS)
import AppKit

/// Receives file URLs from Finder (double click, Open With) and hands them
/// to the view layer.
@MainActor
final class OpenFileRouter: ObservableObject {
    static let shared = OpenFileRouter()
    @Published var pendingURL: URL?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            OpenFileRouter.shared.pendingURL = url
        }
    }
}
#endif

@main
struct MarkReaderApp: App {
    @StateObject private var store = RecentFilesStore()
    @StateObject private var treeStore = FileTreeStore()
    @StateObject private var outline = OutlineContext()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(treeStore)
                .environmentObject(outline)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 800)
        #endif
    }
}
