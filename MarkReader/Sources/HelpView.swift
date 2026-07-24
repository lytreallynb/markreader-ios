import SwiftUI

/// In-app guide: what each feature does, where it lives, and the system
/// settings some of them need. Shown automatically on first launch.
struct HelpView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Welcome to Inkdown", systemImage: "book")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Getting Started", icon: "folder", items: [
                        ("Open things", "Use the sidebar menu (circle button) to open a file or a whole folder. Opening a folder shows its Markdown and PDF files as a tree."),
                        ("Make Inkdown the default", "Sidebar menu > Set as Default Markdown App. After that, double-clicking .md files in Finder opens them here."),
                        ("Edit the source", "The rendered page is shown by default. Press Cmd+E or the </> button to open the source editor. Changes save automatically."),
                    ])
                    section("Annotate", icon: "highlighter", items: [
                        ("Highlight and format", "Select text in the rendered page. A small toolbar appears: pick a color to highlight, B / U / S to format, Clear to remove a highlight. Everything is written into the .md file itself."),
                        ("Notes", "Select text and choose Note in the floating toolbar. The note is stored as a standard Markdown footnote."),
                        ("Review everything", "Cmd+Shift+H collects every highlight and note in the folder into one list."),
                    ])
                    section("Navigate", icon: "list.bullet.indent", items: [
                        ("Outline", "Headings of the open file appear under it in the sidebar; click one to jump. The toolbar outline menu does the same."),
                        ("Quick open", "Cmd+P, then type part of a file name."),
                        ("Search in folder", "Cmd+Shift+F searches the text of every file in the folder."),
                        ("Wiki links", "[[Note Name]] links jump to that note. The sidebar Backlinks section lists notes that link to the current one."),
                    ])
                    section("Translate", icon: "translate", items: [
                        ("Whole document", "Toolbar translate menu > choose English or Chinese. Code, file names, and links are never translated; comments inside code are."),
                        ("Just a selection", "Select text and press Translate in the floating toolbar."),
                        ("First time setup", "Translation uses Apple's on-device models (macOS 15 or iOS 18 and newer). If a language model is missing, press Download Language Support when prompted; the download happens once."),
                    ])
                    section("Assistant", icon: "sparkles", items: [
                        ("Explain and summarize", "Select text and press Explain, or use the sparkles menu to summarize the document. Runs entirely on this device."),
                        ("Requires Apple Intelligence", "Turn it on in System Settings > Apple Intelligence & Siri (iPhone: Settings > Apple Intelligence & Siri). Available on Apple Silicon Macs and recent iPhones; the model downloads in the background. The sparkles menu appears once it is ready."),
                    ])
                    section("More", icon: "play.rectangle", items: [
                        ("Appearance", "The AA menu sets text size (Cmd+Plus / Cmd+Minus), theme (Default, Serif, Sepia) and page width."),
                        ("Math and diagrams", "TeX between $ signs and mermaid code blocks render automatically."),
                        ("PDF", "PDF files open in a built-in viewer with zoom, selection, and Cmd+F search."),
                        ("Present", "The play button turns the document into slides, split at # and ## headings. Use arrow keys; Esc exits."),
                        ("Reading position", "Each file reopens where you left off."),
                    ])
                }
                .padding(16)
            }

            Divider()

            Button {
                onClose()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(12)
        }
        #if os(macOS)
        .frame(width: 560, height: 560)
        #endif
    }

    private func section(
        _ title: String, icon: String, items: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0)
                        .font(.subheadline.weight(.medium))
                    Text(item.1)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
