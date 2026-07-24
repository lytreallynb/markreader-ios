import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device intelligence via the system language model. Fully offline and
/// free; available on Apple Intelligence capable systems only.
enum AIAssist {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    struct UnavailableError: LocalizedError {
        var errorDescription: String? {
            "On-device intelligence is not available on this system."
        }
    }

    static func respond(to prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw UnavailableError()
    }

    static func explainPrompt(passage: String) -> String {
        """
        Explain the following passage from a document, concisely and clearly. \
        Answer in the same language as the passage.

        Passage:
        \(String(passage.prefix(4000)))
        """
    }

    static func summarizePrompt(document: String) -> String {
        """
        Summarize the following Markdown document in at most five short \
        bullet points. Answer in the document's language.

        Document:
        \(String(document.prefix(12000)))
        """
    }
}

/// Bottom card showing an on-device model response for a prompt.
struct InsightCard: View {
    let title: String
    let prompt: String
    let onClose: () -> Void

    @State private var result: String?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if let result {
                ScrollView {
                    Text(result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            } else if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .task(id: prompt) {
            result = nil
            errorText = nil
            do {
                result = try await AIAssist.respond(to: prompt)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
