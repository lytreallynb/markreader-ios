# Inkdown

Native Markdown editor and reader for iOS and macOS. The app is named Inkdown (bundle id com.yutonglv.inkdown, product name Inkdown); the repo and the Xcode target/scheme names remain MarkReader / MarkReaderMac. Release DMGs are built into dist/ (gitignored): build Release, then hdiutil create with the app plus an /Applications symlink. It opens files from iCloud Drive or the Files app, provides a highlighted source editor with live rendering, saves in place, and offers optional on-device Chinese and English translation on supported systems.

## Stack

- Swift 5.9, SwiftUI, iOS 17.0+ and macOS 14.0+ deployment targets
- Two targets share `MarkReader/Sources`: `MarkReader` (iOS) and `MarkReaderMac` (macOS). Platform differences are handled with postfix `#if os(iOS)` on view modifiers, keep it that way instead of forking views.
- Preview rendering: cmark-gfm (swiftlang/swift-cmark, products `cmark-gfm` + `cmark-gfm-extensions`) generates HTML with `data-sourcepos`, shown in a WKWebView with bundled highlight.js (`MarkReader/Resources`). The sourcepos attributes are load-bearing: they map preview selections back to source lines for the highlighter.
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) is still used to render the translation pane only.
- Project generated with XcodeGen from `project.yml`. The `.xcodeproj` is committed for convenience; after editing `project.yml`, run `xcodegen generate` and commit the regenerated project.

## Commands

```bash
xcodegen generate                          # regenerate MarkReader.xcodeproj from project.yml
xcodebuild -project MarkReader.xcodeproj -scheme MarkReader \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project MarkReader.xcodeproj -scheme MarkReaderMac \
  -destination 'platform=macOS,arch=arm64' build
open MarkReader.xcodeproj                  # open in Xcode for device install
```

## Architecture

- `MarkReaderApp.swift`: app entry, injects `RecentFilesStore` and `FileTreeStore`. On macOS an `NSApplicationDelegate` routes Finder file opens through `OpenFileRouter`.
- `HomeView.swift`: macOS uses `NavigationSplitView` with a sidebar (folder tree via `OutlineGroup` + recents, no timestamps) and an actions menu including Set as Default Markdown App (`NSWorkspace.setDefaultApplication`). Opening a file auto-loads its parent folder into the tree; the open file's row expands to show its headings (from `OutlineContext`), which jump the preview. iOS keeps a `NavigationStack` with recents.
- `FileTreeStore.swift`: persisted security-scoped folder bookmark; builds a tree of Markdown-bearing folders and .md files, folders before files.
- `ReaderView.swift`: preview-first layout. The source editor is hidden by default and toggled with the `</>` toolbar button (Cmd+E, `reader.showsSource`); iPhone keeps segmented Write / Preview / Translate modes. Live render is debounced 120 ms; autosave is debounced 900 ms plus save-on-disappear. Selecting text in the preview shows a floating toolbar (highlight colors, bold, underline, strikethrough, note, translate, clear); the same actions exist in the top toolbar for editor selections. Publishes headings into `OutlineContext` for the sidebar.
- `MarkdownHTMLRenderer.swift`: cmark-gfm to HTML with sourcepos + unsafe (raw `<mark>` passthrough); expands `==text==` outside code to `<mark>`.
- `PreviewWebView.swift`: WKWebView wrapper; self-contained page template with inlined CSS and highlight.js, incremental `setDoc` updates that keep scroll position, selection queries for the highlighter, external links open in the browser.
- `MarkdownHighlighter.swift`: applies and removes `<mark>`/`==` highlights in the source, searching near the cmark sourcepos window first.
- `MarkdownSourceEditor.swift`: shared TextKit editor (`UITextView`/`NSTextView`) with source syntax coloring and a selection binding for the highlighter.
- `TranslationPane.swift`: Apple Translation (iOS 18 / macOS 15+). Segments the document so only prose and code comments are translated: code bodies, inline code, file names, paths, URLs, link targets, and images are protected tokens that never reach the translator; each failed segment falls back to its original text. Requests are batched (32) with hard timeouts so the pane cannot hang; a Download Language Support button calls `prepareTranslation`.
- `CodeBlockHighlighter.swift`: code coloring for the MarkdownUI-rendered translation pane.
- `RecentFilesStore.swift`: recent files as security-scoped bookmarks in `UserDefaults`, refreshes stale bookmarks on resolve; refuses and purges directories.
- `FolderScanner.swift`: shared off-main-thread scans powering Cmd+Shift+F content search, the Cmd+Shift+H highlights digest, and sidebar backlinks.
- `CommandPalette.swift` (macOS): Cmd+P fuzzy open and content search palette; `HighlightsDigestView`.
- `PDFViewer.swift`: PDFKit pane for .pdf files (viewer only, markdown toolbar hidden).
- `AIAssist.swift`: on-device FoundationModels explain/summarize with `InsightCard`; gated on Apple Intelligence availability.
- `PresentationView.swift`: slides split at H1/H2, rendered via the preview pipeline.
- Preview extras: per-file scroll memory (ratio in UserDefaults), themes and page width via CSS variables, bundled MathJax (math masked around cmark) and mermaid, `[[wiki links]]` via the `inkdown-wiki:` scheme resolved in `HomeView`.

## Deploy notes

- No Vercel / web deploy: this is a native app.
- Install on device: open in Xcode, set your personal team under Signing & Capabilities, build to phone. Free Apple ID provisioning expires every 7 days; rebuild to re-sign.
- Info.plist declares `LSSupportsOpeningDocumentsInPlace` and Markdown document types, so "Open in MarkReader" works from the Files app share sheet.

## Conventions

- No emojis in code or commit messages. No em dashes in comments or docs.
- Explicit, simple code over clever abstractions.
