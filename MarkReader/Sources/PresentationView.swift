import SwiftUI

/// Minimal presentation mode: the document is split into slides at H1 and H2
/// headings and rendered with the existing preview pipeline at display size.
struct PresentationView: View {
    let markdown: String
    let onClose: () -> Void

    @State private var slides: [String] = []
    @State private var index = 0
    @State private var htmlBody = ""
    @FocusState private var focused: Bool
    @StateObject private var controller = PreviewController()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            PreviewWebView(
                htmlBody: $htmlBody,
                baseURL: nil,
                appearance: PreviewAppearance(fontSize: 24, maxWidth: 960),
                documentKey: nil,
                controller: controller
            )
            .padding(.vertical, 24)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .padding(16)
                }
                Spacer()
                HStack(spacing: 18) {
                    Button {
                        previous()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Text("\(index + 1) / \(max(slides.count, 1))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        next()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= slides.count - 1)
                }
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 18)
            }
        }
        .focusable()
        .focused($focused)
        .onKeyPress(.rightArrow) { next(); return .handled }
        .onKeyPress(.leftArrow) { previous(); return .handled }
        .onKeyPress(.space) { next(); return .handled }
        .onAppear {
            slides = Self.split(markdown)
            focused = true
            render()
        }
        .onChange(of: index) { _, _ in
            render()
        }
    }

    private func next() {
        if index < slides.count - 1 {
            index += 1
        }
    }

    private func previous() {
        if index > 0 {
            index -= 1
        }
    }

    private func render() {
        guard slides.indices.contains(index) else {
            htmlBody = ""
            return
        }
        htmlBody = MarkdownHTMLRenderer.renderBody(from: slides[index])
    }

    /// Splits at H1 and H2 headings outside fenced code blocks.
    static func split(_ markdown: String) -> [String] {
        var slides: [String] = []
        var current: [String] = []
        var inFence = false
        var fenceMarker = ""

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inFence {
                current.append(line)
                if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                fenceMarker = String(trimmed.prefix(3))
                current.append(line)
                continue
            }
            let isSlideBreak = trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ")
            if isSlideBreak,
               !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slides.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(line)
        }
        if !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            slides.append(current.joined(separator: "\n"))
        }
        return slides.isEmpty ? [markdown] : slides
    }
}
