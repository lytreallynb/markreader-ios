import SwiftUI
import WebKit

/// Result of asking the preview what is currently selected.
struct PreviewSelection {
    var text: String
    var sourcePos: String?
    var markText: String?
}

/// Visual parameters of the rendered page. Empty strings mean "use the
/// adaptive default" for that property.
struct PreviewAppearance: Equatable {
    var fontSize: Int = 16
    var fontFamily: String = ""
    var pageBackground: String = ""
    var pageForeground: String = ""
    var maxWidth: Int = 760
}

/// Rendered Markdown preview backed by WKWebView.
/// The page is fully self contained (inlined CSS and highlight.js), and the
/// base URL is the document's folder so relative images resolve.
struct PreviewWebView {
    @Binding var htmlBody: String
    var baseURL: URL?
    var appearance: PreviewAppearance
    var documentKey: String?
    var controller: PreviewController

    static func makeWebView(controller: PreviewController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(controller, name: "selectionAction")
        configuration.userContentController.add(controller, name: "scrollChanged")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = controller
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        controller.attach(webView)
        return webView
    }

    func update(_ webView: WKWebView) {
        controller.documentKey = documentKey
        controller.setDocument(body: htmlBody, baseURL: baseURL, appearance: appearance)
    }
}

/// Owns the WKWebView lifecycle: template loading, incremental body updates,
/// and selection queries used by the highlighter.
final class PreviewController: NSObject, ObservableObject, WKNavigationDelegate {
    weak var webView: WKWebView?

    /// Called when the user taps an action in the floating selection toolbar
    /// inside the preview: (action, color, selection).
    var onSelectionAction: ((String, String?, PreviewSelection) -> Void)?

    /// Called when the user clicks a [[wiki link]]; the argument is the
    /// target note name.
    var onWikiLink: ((String) -> Void)?

    /// Identifies the open document for per-file scroll position memory.
    var documentKey: String? {
        didSet {
            if documentKey != oldValue {
                needsScrollRestore = true
            }
        }
    }

    private var pageLoaded = false
    private var loadedBaseURL: URL?
    private var pendingBody: String?
    private var pendingAppearance = PreviewAppearance()
    private var pendingScrollLine: Int?
    private var needsScrollRestore = true
    private var lastBody: String?

    private func scrollDefaultsKey(_ key: String) -> String {
        "scroll.\(key)"
    }

    /// Called whenever SwiftUI creates a fresh WKWebView (for example when a
    /// compact layout switches panes). Resets load state so the template is
    /// reloaded into the new web view.
    func attach(_ webView: WKWebView) {
        self.webView = webView
        pageLoaded = false
        loadedBaseURL = nil
        lastBody = nil
        needsScrollRestore = true
    }

    func setDocument(body: String, baseURL: URL?, appearance: PreviewAppearance) {
        guard let webView else { return }

        if !pageLoaded || loadedBaseURL != baseURL {
            pageLoaded = false
            loadedBaseURL = baseURL
            pendingBody = body
            pendingAppearance = appearance
            lastBody = body
            needsScrollRestore = true
            webView.loadHTMLString(Self.pageTemplate, baseURL: baseURL)
            return
        }

        applyAppearance(appearance)
        guard body != lastBody else { return }
        lastBody = body
        apply(body: body)
        restoreScrollIfNeeded()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        applyAppearance(pendingAppearance)
        if let body = pendingBody {
            pendingBody = nil
            apply(body: body)
        }
        restoreScrollIfNeeded()
        if let line = pendingScrollLine {
            pendingScrollLine = nil
            webView.evaluateJavaScript(
                "setTimeout(function () { window.scrollToSourceLine(\(line)); }, 120)"
            )
        }
    }

    private func restoreScrollIfNeeded() {
        guard needsScrollRestore, let documentKey else { return }
        needsScrollRestore = false
        let saved = UserDefaults.standard.double(
            forKey: scrollDefaultsKey(documentKey)
        )
        guard saved > 0.001 else { return }
        webView?.evaluateJavaScript(
            "setTimeout(function () { window.restoreScroll(\(saved)); }, 250)"
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            if url.scheme == "inkdown-wiki" {
                let name = String(url.absoluteString.dropFirst("inkdown-wiki:".count))
                    .removingPercentEncoding ?? ""
                if !name.isEmpty {
                    onWikiLink?(name)
                }
                return
            }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            return
        }
        decisionHandler(.allow)
    }

    func scrollToLine(_ line: Int) {
        if pageLoaded {
            webView?.evaluateJavaScript("window.scrollToSourceLine(\(line))")
        } else {
            pendingScrollLine = line
        }
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

    private func applyAppearance(_ appearance: PreviewAppearance) {
        pendingAppearance = appearance
        let dict: [String: Any] = [
            "size": appearance.fontSize,
            "family": appearance.fontFamily,
            "bg": appearance.pageBackground,
            "fg": appearance.pageForeground,
            "width": appearance.maxWidth,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.setAppearance(\(json))")
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
        let mathJS = (try? String(
            contentsOf: bundle.url(forResource: "mathjax-tex-svg", withExtension: "js")!,
            encoding: .utf8
        )) ?? ""
        let mermaidJS = (try? String(
            contentsOf: bundle.url(forResource: "mermaid.min", withExtension: "js")!,
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
          max-width: var(--max-width, 760px);
          font-family: var(--body-font, -apple-system, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", sans-serif);
          font-size: var(--base-size);
          line-height: 1.65;
          color: var(--page-fg, #1f2328);
          background: var(--page-bg, transparent);
          -webkit-text-size-adjust: 100%;
          word-wrap: break-word;
        }
        a.wiki { border-bottom: 1px dashed rgba(9,105,218,0.5); }
        div.mermaid { text-align: center; margin: 0 0 0.9em; }
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
          background: #f6f8fa;
        }
        pre code, pre code.hljs { background: transparent; padding: 0; font-size: 0.85em; line-height: 1.55; }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(140,140,140,0.35); padding: 6px 12px; }
        th { background: rgba(140,140,140,0.12); }
        mark {
          background: #ffec9e;
          color: #1f2328;
          border-radius: 3px;
          padding: 0.05em 0.15em;
        }
        u { text-underline-offset: 0.2em; }
        #seltoolbar {
          position: fixed;
          display: none;
          z-index: 99;
          align-items: center;
          gap: 5px;
          padding: 6px 10px;
          border-radius: 10px;
          background: rgba(252,252,252,0.98);
          box-shadow: 0 4px 18px rgba(0,0,0,0.18);
          border: 1px solid rgba(0,0,0,0.08);
          -webkit-user-select: none;
          user-select: none;
        }
        #seltoolbar .dot {
          width: 15px;
          height: 15px;
          border-radius: 50%;
          cursor: pointer;
          border: 1px solid rgba(0,0,0,0.18);
        }
        #seltoolbar button {
          border: none;
          background: none;
          font-family: inherit;
          font-size: 13px;
          cursor: pointer;
          padding: 2px 7px;
          border-radius: 6px;
          color: #1f2328;
        }
        #seltoolbar button:hover, #seltoolbar .dot:hover { background: rgba(0,0,0,0.08); }
        #seltoolbar .sep { width: 1px; height: 16px; background: rgba(0,0,0,0.14); }
        #seltoolbar button[data-action="bold"] { font-weight: 700; }
        #seltoolbar button[data-action="underline"] { text-decoration: underline; }
        #seltoolbar button[data-action="strikethrough"] { text-decoration: line-through; }
        @media (prefers-color-scheme: dark) {
          #seltoolbar {
            background: rgba(44,44,46,0.98);
            border-color: rgba(255,255,255,0.12);
          }
          #seltoolbar button { color: #e6e6e6; }
          #seltoolbar button:hover, #seltoolbar .dot:hover { background: rgba(255,255,255,0.12); }
          #seltoolbar .sep { background: rgba(255,255,255,0.18); }
        }
        section.footnotes {
          margin-top: 2em;
          font-size: 0.88em;
          color: #59636e;
        }
        section.footnotes p { margin-bottom: 0.4em; }
        sup a { font-weight: 600; }
        \(lightCSS)
        .hljs { background: transparent; padding: 0; }
        @media (prefers-color-scheme: dark) {
          body { color: var(--page-fg, #e6e6e6); }
          a { color: #4da3ff; }
          blockquote { color: #a0a8b0; }
          code { background: rgba(200,200,200,0.14); }
          \(darkCSS)
          pre { background: #161b22; }
          pre code, .hljs { background: transparent; padding: 0; }
        }
        </style>
        <script>\(js)</script>
        <script>
        window.MathJax = {
          tex: {
            inlineMath: [["$", "$"], ["\\\\(", "\\\\)"]],
            displayMath: [["$$", "$$"]]
          },
          svg: { fontCache: "global" },
          startup: { typeset: false }
        };
        </script>
        <script>\(mathJS)</script>
        <script>\(mermaidJS)</script>
        </head>
        <body>
        <div id="content"></div>
        <div id="seltoolbar">
          <span class="dot" data-action="highlight" data-color="yellow" style="background:#ffec9e"></span>
          <span class="dot" data-action="highlight" data-color="green" style="background:#c3edc0"></span>
          <span class="dot" data-action="highlight" data-color="blue" style="background:#bcd8ff"></span>
          <span class="dot" data-action="highlight" data-color="pink" style="background:#ffcfe1"></span>
          <span class="dot" data-action="highlight" data-color="orange" style="background:#ffd8a8"></span>
          <span class="sep"></span>
          <button data-action="bold">B</button>
          <button data-action="underline">U</button>
          <button data-action="strikethrough">S</button>
          <span class="sep"></span>
          <button data-action="note">Note</button>
          <button data-action="translate">Translate</button>
          <button id="selclear" data-action="clear">Clear</button>
        </div>
        <script>
        try {
          mermaid.initialize({
            startOnLoad: false,
            theme: window.matchMedia("(prefers-color-scheme: dark)").matches
              ? "dark" : "default"
          });
        } catch (e) {}
        window.setDoc = function (html) {
          var y = window.scrollY;
          document.getElementById("content").innerHTML = html;
          document.querySelectorAll("pre code").forEach(function (el) {
            try { hljs.highlightElement(el); } catch (e) {}
          });
          document.querySelectorAll("pre code.language-mermaid").forEach(function (el) {
            var div = document.createElement("div");
            div.className = "mermaid";
            div.textContent = el.textContent;
            el.parentElement.replaceWith(div);
          });
          try { mermaid.run({ querySelector: ".mermaid" }); } catch (e) {}
          if (window.MathJax && MathJax.typesetPromise) {
            try {
              MathJax.typesetClear();
              MathJax.typesetPromise([document.getElementById("content")])
                .catch(function () {});
            } catch (e) {}
          }
          window.scrollTo(0, y);
        };
        window.setAppearance = function (a) {
          var s = document.documentElement.style;
          s.setProperty("--base-size", a.size + "px");
          s.setProperty("--max-width", a.width + "px");
          if (a.family) { s.setProperty("--body-font", a.family); }
          else { s.removeProperty("--body-font"); }
          if (a.bg) { s.setProperty("--page-bg", a.bg); }
          else { s.removeProperty("--page-bg"); }
          if (a.fg) { s.setProperty("--page-fg", a.fg); }
          else { s.removeProperty("--page-fg"); }
        };
        window.restoreScroll = function (ratio) {
          var h = document.body.scrollHeight - window.innerHeight;
          if (h > 0) { window.scrollTo(0, ratio * h); }
        };
        var scrollReportTimer = null;
        window.addEventListener("scroll", function () {
          clearTimeout(scrollReportTimer);
          scrollReportTimer = setTimeout(function () {
            var h = document.body.scrollHeight - window.innerHeight;
            var ratio = h > 0 ? window.scrollY / h : 0;
            try {
              window.webkit.messageHandlers.scrollChanged.postMessage(ratio);
            } catch (e) {}
          }, 250);
        });
        window.scrollToSourceLine = function (line) {
          var els = document.querySelectorAll("[data-sourcepos]");
          var best = null;
          var bestLine = -1;
          els.forEach(function (el) {
            var start = parseInt(el.getAttribute("data-sourcepos"));
            if (!isNaN(start) && start <= line && start > bestLine) {
              best = el;
              bestLine = start;
            }
          });
          if (best) { best.scrollIntoView({ behavior: "smooth", block: "start" }); }
        };
        function selectionInfo() {
          var sel = window.getSelection();
          if (!sel || sel.isCollapsed || !sel.toString().trim()) { return null; }
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
          return { text: sel.toString(), pos: pos, markText: mark ? mark.textContent : null };
        }
        window.getSelectionInfo = function () {
          var info = selectionInfo();
          if (!info) { return JSON.stringify({ ok: false }); }
          return JSON.stringify({
            ok: true, text: info.text, pos: info.pos, markText: info.markText
          });
        };

        var seltoolbar = document.getElementById("seltoolbar");
        var seltoolbarTimer = null;
        seltoolbar.addEventListener("mousedown", function (e) { e.preventDefault(); });
        seltoolbar.addEventListener("click", function (e) {
          var target = e.target.closest("[data-action]");
          if (!target) { return; }
          var info = selectionInfo();
          if (!info) { seltoolbar.style.display = "none"; return; }
          window.webkit.messageHandlers.selectionAction.postMessage({
            action: target.getAttribute("data-action"),
            color: target.getAttribute("data-color"),
            text: info.text,
            pos: info.pos,
            markText: info.markText
          });
          seltoolbar.style.display = "none";
        });
        function updateSelToolbar() {
          var info = selectionInfo();
          if (!info) { seltoolbar.style.display = "none"; return; }
          document.getElementById("selclear").style.display = info.markText ? "" : "none";
          var rect = window.getSelection().getRangeAt(0).getBoundingClientRect();
          seltoolbar.style.display = "flex";
          var w = seltoolbar.offsetWidth;
          var h = seltoolbar.offsetHeight;
          var left = Math.min(
            Math.max(rect.left + rect.width / 2 - w / 2, 8),
            window.innerWidth - w - 8
          );
          var top = rect.top - h - 10;
          if (top < 8) { top = rect.bottom + 10; }
          seltoolbar.style.left = left + "px";
          seltoolbar.style.top = top + "px";
        }
        function scheduleSelToolbar() {
          clearTimeout(seltoolbarTimer);
          seltoolbarTimer = setTimeout(updateSelToolbar, 180);
        }
        document.addEventListener("selectionchange", scheduleSelToolbar);
        window.addEventListener("scroll", scheduleSelToolbar);
        </script>
        </body>
        </html>
        """
    }()
}

extension PreviewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "scrollChanged" {
            guard let ratio = message.body as? Double, let documentKey else { return }
            UserDefaults.standard.set(ratio, forKey: scrollDefaultsKey(documentKey))
            return
        }
        guard message.name == "selectionAction",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let text = body["text"] as? String
        else { return }
        let selection = PreviewSelection(
            text: text,
            sourcePos: body["pos"] as? String,
            markText: body["markText"] as? String
        )
        onSelectionAction?(action, body["color"] as? String, selection)
    }
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
