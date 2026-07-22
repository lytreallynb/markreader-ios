import SwiftUI
import PDFKit

/// PDF rendering pane backed by PDFKit. The document is loaded from data so
/// no security-scoped access needs to stay open while the view lives.
struct PDFViewer {
    let data: Data

    func makePDFView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    // The reader view is recreated per file, so the document never changes
    // after creation and updates are a no-op.
    func update(_ view: PDFView) {}
}

#if os(macOS)
extension PDFViewer: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        makePDFView()
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        update(nsView)
    }
}
#else
extension PDFViewer: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        makePDFView()
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        update(uiView)
    }
}
#endif
