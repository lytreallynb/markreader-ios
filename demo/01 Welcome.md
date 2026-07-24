# Welcome to Inkdown

Inkdown is a lightweight Markdown reader and annotator for macOS and iOS. It renders your notes beautifully, and everything you mark up is written back into the file itself, so your annotations travel with your notes.

轻量、原生、离线。整个应用不到 10 MB。

## What it renders

| Feature | Syntax | Status |
| --- | --- | --- |
| Tables | GFM | Ready |
| Task lists | `- [x]` | Ready |
| Code blocks | fenced | Ready |
| Math | TeX | Ready |
| Diagrams | mermaid | Ready |

- [x] Open files from Finder, iCloud Drive, or the sidebar tree
- [x] Remember your reading position in every file
- [ ] Your next great note

## Code, with colors

```swift
// Load a note and render it
let note = try String(contentsOf: url, encoding: .utf8)
let html = MarkdownHTMLRenderer.renderBody(from: note)
```

> Reading should feel calm. The source is there when you need it, one keystroke away, and out of sight when you do not.

See [[02 Annotations]] for highlighting, and [[03 Math and Diagrams]] for TeX and mermaid.
