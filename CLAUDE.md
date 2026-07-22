# MarkReader

Markdown reader for iOS and macOS. Read-only by design: no editing, no sync service, just clean rendering of files from iCloud Drive / the Files app.

## Stack

- Swift 5.9, SwiftUI, iOS 17.0+ and macOS 14.0+ deployment targets
- Two targets share `MarkReader/Sources`: `MarkReader` (iOS) and `MarkReaderMac` (macOS). Platform differences are handled with postfix `#if os(iOS)` on view modifiers, keep it that way instead of forking views.
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) 2.4+ for GFM rendering (tables, task lists, code blocks)
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

- `MarkReader/Sources/MarkReaderApp.swift`: app entry, injects `RecentFilesStore`.
- `HomeView.swift`: recents list + `fileImporter` picker + `onOpenURL` (open-in-place from Files app). Navigation pushes a `URL` onto a `NavigationStack` path.
- `ReaderView.swift`: loads file content via `NSFileCoordinator` (handles undownloaded iCloud files) inside a security-scoped access block, renders with MarkdownUI's GitHub theme. Text size steps through `DynamicTypeSize`, persisted in `@AppStorage`.
- `RecentFilesStore.swift`: recent files as security-scoped bookmarks in `UserDefaults`, refreshes stale bookmarks on resolve.

## Deploy notes

- No Vercel / web deploy: this is a native app.
- Install on device: open in Xcode, set your personal team under Signing & Capabilities, build to phone. Free Apple ID provisioning expires every 7 days; rebuild to re-sign.
- Info.plist declares `LSSupportsOpeningDocumentsInPlace` and Markdown document types, so "Open in MarkReader" works from the Files app share sheet.

## Conventions

- No emojis in code or commit messages. No em dashes in comments or docs.
- Explicit, simple code over clever abstractions.
