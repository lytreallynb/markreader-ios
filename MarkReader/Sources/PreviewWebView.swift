import SwiftUI
import WebKit

/// Result of asking the preview what is currently selected.
struct PreviewSelection {
    var text: String
    var sourcePos: String?
    var markText: String?
}

/// Rendered Markdown preview backed by WKWebView.
/// The page is fully self contained (inlined CSS and highlight.js), and the
/// base URL is the document's folder so relative images resolve.
struct PreviewWebView {
    @Binding var htmlBody: String
    var baseURL: URL?
    var fontSize: Int
    var controller: PreviewController

    static func makeWebView(controller: PreviewController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = controller
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        controller.webView = webView
        return webView
    }

    func update(_ webView: WKWebView) {
        controller.setDocument(body: htmlBody, baseURL: baseURL, fontSize: fontSize)
    }
}

/// Owns the WKWebView lifecycle: template loading, incremental body updates,
/// and selection queries used by the highlighter.
final class PreviewController: NSObject, ObservableObject, WKNavigationDelegate {
    weak var webView: WKWebView?

    private var pageLoaded = false
    private var loadedBaseURL: URL?
    private var pendingBody: String?
    private var pendingFontSize: Int = 16
    private var lastBody: String?

    func setDocument(body: String, baseURL: URL?, fontSize: Int) {
        guard let webView else { return }

        if !pageLoaded || loadedBaseURL != baseURL {
            pageLoaded = false
            loadedBaseURL = baseURL
            pendingBody = body
            pendingFontSize = fontSize
            lastBody = body
            webView.loadHTMLString(Self.pageTemplate, baseURL: baseURL)
            return
        }

        applyFontSize(fontSize)
        guard body != lastBody else { return }
        lastBody = body
        apply(body: body)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        applyFontSize(pendingFontSize)
        if let body = pendingBody {
            pendingBody = nil
            apply(body: body)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            return
        }
        decisionHandler(.allow)
    }

    func currentSelection() async -> PreviewSelection? {
        guard let webView else { return nil }
        let result = try? await webView.evaluateJavaScript("window.getSelectionInfo()")
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true,
              let text = object["text"] as? String
        else { return nil }
        return PreviewSelection(
            text: text,
            sourcePos: object["pos"] as? String,
            markText: object["markText"] as? String
        )
    }

    private func apply(body: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [body]),
              let encoded = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.setDoc(\(encoded)[0])")
    }

    private func applyFontSize(_ size: Int) {
        pendingFontSize = size
        webView?.evaluateJavaScript("window.setFontSize(\(size))")
    }

    private static let pageTemplate: String = {
        let bundle = Bundle.main
        let js = (try? String(
            contentsOf: bundle.url(forResource: "highlight.min", withExtension: "js")!,
            encoding: .utf8
        )) ?? ""
        let lightCSS = (try? String(
            contentsOf: bundle.url(forResource: "hljs-github.min", withExtension: "css")!,
            encoding: .utf8
        )) ?? ""
        let darkCSS = (try? String(
            contentsOf: bundle.url(forResource: "hljs-github-dark.min", withExtension: "css")!,
            encoding: .utf8
        )) ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { --base-size: 16px; color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
          margin: 0 auto;
          padding: 24px 28px 60px;
          max-width: 760px;
          font-family: -apple-system, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", sans-serif;
          font-size: var(--base-size);
          line-height: 1.65;
          color: #1f2328;
          background: transparent;
          -webkit-text-size-adjust: 100%;
          word-wrap: break-word;
        }
        h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.3em 0 0.55em; font-weight: 650; }
        h1 { font-size: 1.75em; padding-bottom: 0.25em; border-bottom: 1px solid rgba(140,140,140,0.28); }
        h2 { font-size: 1.4em; padding-bottom: 0.2em; border-bottom: 1px solid rgba(140,140,140,0.2); }
        h3 { font-size: 1.18em; }
        h4 { font-size: 1.05em; }
        p, ul, ol, table, blockquote, pre { margin: 0 0 0.9em; }
        ul, ol { padding-left: 1.6em; }
        li + li { margin-top: 0.2em; }
        li.task-list-item { list-style: none; margin-left: -1.3em; }
        a { color: #0969da; text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; border-radius: 6px; }
        hr { border: none; border-top: 1px solid rgba(140,140,140,0.3); margin: 1.6em 0; }
        blockquote {
          padding: 2px 0 2px 14px;
          border-left: 3px solid rgba(9,105,218,0.5);
          color: #59636e;
        }
        code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 0.875em;
          background: rgba(140,140,140,0.15);
          padding: 0.15em 0.35em;
          border-radius: 4px;
        }
        pre {
          padding: 14px 16px;
          border-radius: 8px;
          overflow-x: auto;
          background: rgba(140,140,140,0.1);
          border: 1px solid rgba(140,140,140,0.18);
        }
        pre code { background: none; padding: 0; font-size: 0.85em; line-height: 1.55; }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(140,140,140,0.35); padding: 6px 12px; }
        th { background: rgba(140,140,140,0.12); }
        mark {
          background: #ffec9e;
          color: #1f2328;
          border-radius: 3px;
          padding: 0.05em 0.15em;
        }
        \(lightCSS)
        @media (prefers-color-scheme: dark) {
          body { color: #e6e6e6; }
          a { color: #4da3ff; }
          blockquote { color: #a0a8b0; }
          \(darkCSS)
        }
        </style>
        <script>\(js)</script>
        </head>
        <body>
        <div id="content"></div>
        <script>
        window.setDoc = function (html) {
          var y = window.scrollY;
          document.getElementById("content").innerHTML = html;
          document.querySelectorAll("pre code").forEach(function (el) {
            try { hljs.highlightElement(el); } catch (e) {}
          });
          window.scrollTo(0, y);
        };
        window.setFontSize = function (px) {
          document.documentElement.style.setProperty("--base-size", px + "px");
        };
        window.getSelectionInfo = function () {
          var sel = window.getSelection();
          if (!sel || sel.isCollapsed || !sel.toString()) {
            return JSON.stringify({ ok: false });
          }
          var text = sel.toString();
          var node = sel.anchorNode;
          if (node && node.nodeType === Node.TEXT_NODE) { node = node.parentElement; }
          var mark = null;
          var pos = null;
          var el = node;
          while (el && el !== document.body) {
            if (!mark && el.tagName === "MARK") { mark = el; }
            if (!pos && el.hasAttribute && el.hasAttribute("data-sourcepos")) {
              pos = el.getAttribute("data-sourcepos");
            }
            el = el.parentElement;
          }
          return JSON.stringify({
            ok: true,
            text: text,
            pos: pos,
            markText: mark ? mark.textContent : null
          });
        };
        </script>
        </body>
        </html>
        """
    }()
}

#if os(macOS)
extension PreviewWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        Self.makeWebView(controller: controller)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        update(nsView)
    }
}
#else
extension PreviewWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        Self.makeWebView(controller: controller)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        update(uiView)
    }
}
#endif
