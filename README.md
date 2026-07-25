<div align="center">

<img src="docs/icon.png" width="110" alt="Inkdown icon">

# Inkdown

**Read calmly. Annotate permanently.**

A lightweight, native Markdown reader and annotator.
Every highlight, format, and note is written back into the `.md` file itself.

English | [简体中文](README.zh-CN.md)

[![Release](https://img.shields.io/github/v/release/lytreallynb/markreader-ios?label=release&color=1f9e93)](../../releases)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%C2%B7%20iOS%20%C2%B7%20Windows%20%C2%B7%20Linux-1f2933)
![Size](https://img.shields.io/badge/app%20size-~9%20MB-ffd84d)
![Offline](https://img.shields.io/badge/network-100%25%20offline-2a63d9)

<img src="docs/reading.png" width="820" alt="Reading view">

</div>

---

## Why Inkdown

Most Markdown apps are either heavyweight editors or read-only previewers. Inkdown is built around the **reading loop**: open a folder, read comfortably, mark what matters, review it all later. No database, no lock-in — the Markdown files are the single source of truth.

- **Annotations that last** — highlights in five colors, bold, underline, strikethrough, and footnote notes, all written into the source as `==marks==`, `<mark>` tags, and `[^n]` footnotes
- **Everything renders offline** — GFM, TeX math, mermaid diagrams, syntax-highlighted code
- **Fast to move around** — quick open, folder-wide search, auto-expanding outline, `[[wiki links]]` with backlinks
- **Genuinely lightweight** — about 9 MB of native code; no Electron anywhere

<div align="center">
<table>
<tr>
<td width="50%"><img src="docs/annotations.png" alt="Annotations"><br><p align="center"><sub>Five-color highlights, formatting, and footnote notes</sub></p></td>
<td width="50%"><img src="docs/math-diagrams.png" alt="Math and diagrams"><br><p align="center"><sub>TeX math and mermaid, bundled and offline</sub></p></td>
</tr>
<tr>
<td width="50%"><img src="docs/editing.png" alt="Editing"><br><p align="center"><sub>Source editor one keystroke away, with autosave</sub></p></td>
<td width="50%"><p align="center"><br><br><b>Review everything at once</b><br><br><sub>Cmd+Shift+H collects every highlight and note<br>across the folder, grouped by file.<br>Your own private Readwise.</sub></p></td>
</tr>
</table>
</div>

## Download

| Platform | Get it | Notes |
| --- | --- | --- |
| Windows | [Setup .exe](../../releases/latest) · [.msi](../../releases/latest) | SmartScreen: More info, then Run anyway |
| Linux | [.deb](../../releases/latest) · [.rpm](../../releases/latest) · [.AppImage](../../releases/latest) | AppImage: `chmod +x` first |
| macOS (native) | [Inkdown-1.0.dmg](../../releases/tag/v1.0.0) | Signed and notarized; drag to Applications and open |
| iOS | Build from source | App Store planned |

## Features in detail

<details>
<summary><b>Reading</b></summary>

- GitHub-flavored rendering: tables, task lists, footnotes, syntax-highlighted code
- TeX math (MathJax) and mermaid diagrams, fully offline
- Three themes (Default, Serif, Sepia), text size from 10 to 24 pt, three page widths
- Reading position remembered per file; built-in PDF viewer
- Presentation mode: slides split at `#` / `##` headings, arrow-key navigation

</details>

<details>
<summary><b>Annotating</b></summary>

- Select text in the rendered page; a floating toolbar appears
- Highlights in five colors, bold, underline, strikethrough, one-click removal
- Notes stored as standard Markdown footnotes, portable to Obsidian and GitHub
- All Highlights (Cmd+Shift+H): a folder-wide review of every mark and note

</details>

<details>
<summary><b>Navigating</b></summary>

- Sidebar: lazy Home browser, focused folder tree, recents
- Heading outline auto-expands under the open file
- Quick open (Cmd+P) and folder-wide full-text search (Cmd+Shift+F)
- `[[wiki links]]` resolve inside the folder; Backlinks lists reverse links

</details>

<details>
<summary><b>Translation and AI (macOS / iOS)</b></summary>

- On-device translation between English and Chinese that never touches code, file names, paths, or URLs, yet still translates comments inside code blocks
- Select text to translate instantly, or Explain / Summarize with Apple Intelligence, fully on-device

</details>

<details>
<summary><b>Editing</b></summary>

- Preview-first: the source editor stays hidden until Cmd+E
- Syntax-colored editor with debounced autosave
- Create, rename, and trash files from the sidebar; open-in-place from Finder

</details>

## Build from source

**macOS / iOS** (Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
git clone https://github.com/lytreallynb/markreader-ios.git
cd markreader-ios
xcodegen generate
open MarkReader.xcodeproj      # schemes: MarkReaderMac, MarkReader (iOS)
```

**Windows / Linux** (Node 20+, Rust):

```bash
cd desktop
npm install
npm run dev
```

Every `desktop-v*` tag makes CI build Windows, Linux, and macOS artifacts into [Releases](../../releases). `bash scripts/release.sh` produces the signed native macOS DMG.

## Keyboard shortcuts

| Shortcut | Action | | Shortcut | Action |
| --- | --- | --- | --- | --- |
| Cmd+P | Quick open | | Cmd+E | Toggle source editor |
| Cmd+Shift+F | Search in folder | | Cmd+Plus / Minus | Text size |
| Cmd+Shift+H | All highlights | | Cmd+S | Save now |

<div align="center">
<sub>

SwiftUI · cmark-gfm · WKWebView · highlight.js · MathJax · mermaid · PDFKit · Translation · FoundationModels · Tauri

Sample documents in [`demo/`](demo/) · Made by [Coldice](https://yutonglv.com)

</sub>
</div>
