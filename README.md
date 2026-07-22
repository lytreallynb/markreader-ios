# MarkReader

A minimal iOS Markdown reader. Open .md files from iCloud Drive or the Files app and read them with clean GitHub-style rendering. No editing, no accounts, no sync service.

## Features

- Open any Markdown file via the system file picker, or "Open in MarkReader" from the Files app
- GitHub Flavored Markdown rendering: tables, task lists, fenced code blocks, blockquotes
- Recent files list backed by security-scoped bookmarks
- Adjustable text size, dark mode, text selection
- Works with files that live in iCloud Drive (downloads on demand)

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open MarkReader.xcodeproj
```

Select your team under Signing & Capabilities, then build to a simulator or device.
