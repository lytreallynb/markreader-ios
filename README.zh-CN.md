<div align="center">

<img src="docs/icon.png" width="96" alt="Inkdown 图标">

# Inkdown

**安静地读，永久地标注。**

轻量原生的 macOS / iOS Markdown 阅读与标注工具。
所有高亮、格式和笔记都直接写回 `.md` 文件本身，标注永远跟着笔记走。

[English](README.md) | 简体中文

`应用仅 8.8 MB` · `完全离线` · `macOS 14+ / iOS 17+`

</div>

![阅读视图](docs/reading.png)

## 为什么做 Inkdown

多数 Markdown 应用要么是笨重的编辑器，要么是只读的预览器。Inkdown 围绕"阅读闭环"设计：打开文件夹、舒适地读、随手标注、事后复盘。没有私有数据库、没有锁定，Markdown 文件就是唯一的数据源。

## 功能

### 阅读

- GitHub 风格渲染：表格、任务列表、脚注、代码语法高亮
- TeX 数学公式（MathJax）与 mermaid 图表，全部内置、完全离线
- 三套主题（默认 / 衬线 / 纸色），字号 10 到 24 pt，三档行宽
- 每个文件记住阅读位置；PDF 内置阅读器直接打开
- 演示模式：按 `#` 和 `##` 标题切分幻灯片，方向键翻页

### 标注

![标注](docs/annotations.png)

- 在渲染页面选中文字，浮动工具条即刻出现
- 五色高亮、加粗、下划线、删除线，一键清除
- 笔记以标准 Markdown 脚注存储
- 所有标注写入源文件本身：`==高亮==`、`<mark>` 标签、`[^n]` 脚注
- **划线汇总**（Cmd+Shift+H）：整个文件夹的高亮与笔记按文件分组一页看完

### 导航

- 侧栏三层结构：Home 懒加载浏览区、当前专注的文件夹树、最近文件
- 打开的文件下方自动展开标题大纲，点击跳转
- 快速打开（Cmd+P）、文件夹全文搜索（Cmd+Shift+F）
- `[[双链]]` 跳转同名笔记，反链区列出谁链到了当前笔记

### 翻译与 AI

- 端侧文档翻译（中英互译）：代码、文件名、路径、URL 永不误翻，代码里的注释照常翻译
- 选中即译；配合 Apple Intelligence 可对选中文字"解释"、对全文"摘要"，全程本地运行

### 编辑

![编辑](docs/editing.png)

- 默认纯阅读视图，Cmd+E 才展开源码编辑器
- 语法着色编辑器，停笔自动保存
- 侧栏内直接新建、重命名、移入废纸篓；支持 Finder 双击打开

## 公式与图表

![公式与图表](docs/math-diagrams.png)

## Windows 与 Linux

桌面移植版位于 [`desktop/`](desktop/)，基于 Tauri 2 与系统自带 WebView 构建，同样保持轻量。它复用同一套渲染管线（MathJax、mermaid、highlight.js、双链），标注闭环一致：高亮、格式、脚注笔记写回文件，另有快速打开、全文搜索、主题与阅读位置记忆。每次打 `desktop-v*` 标签，CI 会自动产出 Windows（`.msi`）、Linux（`.deb` / `.AppImage`）与 macOS 构建，见 [Releases](../../releases)。

```bash
cd desktop
npm install
npm run dev     # 需要 Rust
```

## 安装（macOS / iOS 原生版）

**下载**：签名公证的 DMG 即将提供；目前请从源码构建。

**从源码构建**（需要 Xcode 16+ 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)）：

```bash
git clone https://github.com/lytreallynb/markreader-ios.git
cd markreader-ios
xcodegen generate
open MarkReader.xcodeproj
```

macOS 构建 `MarkReaderMac` scheme，iOS 构建 `MarkReader`。运行 `bash scripts/release.sh` 可在 `dist/` 产出 DMG。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| Cmd+P | 按文件名快速打开 |
| Cmd+Shift+F | 文件夹全文搜索 |
| Cmd+Shift+H | 划线汇总 |
| Cmd+E | 展开 / 收起源码编辑器 |
| Cmd+加号 / Cmd+减号 | 调整字号 |
| Cmd+S | 立即保存（默认已自动保存） |

## 技术栈

SwiftUI · cmark-gfm · WKWebView · highlight.js · MathJax · mermaid · PDFKit · Translation · FoundationModels

示例文档见 [`demo/`](demo/)。
