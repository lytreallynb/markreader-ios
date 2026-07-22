import SwiftUI

@main
struct MarkReaderApp: App {
    @StateObject private var store = RecentFilesStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
