<div align="center">

<img src="docs/icon.png" width="110" alt="Inkdown 图标">

# Inkdown

**安静地读，永久地标注。**

轻量原生的 Markdown 阅读与标注工具。
每一处高亮、格式和笔记都直接写回 `.md` 文件本身。

[English](README.md) | 简体中文

[![Release](https://img.shields.io/github/v/release/lytreallynb/markreader-ios?label=release&color=1f9e93)](../../releases)
![Platforms](https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-macOS%20%C2%B7%20iOS%20%C2%B7%20Windows%20%C2%B7%20Linux-1f2933)
![Size](https://img.shields.io/badge/%E5%BA%94%E7%94%A8%E4%BD%93%E7%A7%AF-~9%20MB-ffd84d)
![Offline](https://img.shields.io/badge/%E7%BD%91%E7%BB%9C-%E5%AE%8C%E5%85%A8%E7%A6%BB%E7%BA%BF-2a63d9)

<img src="docs/reading.png" width="820" alt="阅读视图">

</div>

---

## 为什么做 Inkdown

多数 Markdown 应用要么是笨重的编辑器，要么是只读的预览器。Inkdown 围绕**阅读闭环**设计：打开文件夹、舒适地读、随手标注、事后复盘。没有私有数据库、没有锁定，Markdown 文件就是唯一的数据源。

- **标注永不丢失** — 五色高亮、加粗、下划线、删除线、脚注笔记，全部以 `==高亮==`、`<mark>` 标签、`[^n]` 脚注写入源文件
- **一切离线渲染** — GFM、TeX 公式、mermaid 图表、代码语法高亮
- **移动飞快** — 快速打开、全文搜索、自动展开的大纲、`[[双链]]` 与反链
- **真正的轻量** — 约 9 MB 原生代码，没有一丝 Electron

<div align="center">
<table>
<tr>
<td width="50%"><img src="docs/annotations.png" alt="标注"><br><p align="center"><sub>五色高亮、格式与脚注笔记</sub></p></td>
<td width="50%"><img src="docs/math-diagrams.png" alt="公式与图表"><br><p align="center"><sub>TeX 公式与 mermaid，内置且离线</sub></p></td>
</tr>
<tr>
<td width="50%"><img src="docs/editing.png" alt="编辑"><br><p align="center"><sub>源码编辑一键展开，停笔自动保存</sub></p></td>
<td width="50%"><p align="center"><br><br><b>划线一页复盘</b><br><br><sub>Cmd+Shift+H 汇总整个文件夹的高亮与笔记，<br>按文件分组。<br>你自己的私人 Readwise。</sub></p></td>
</tr>
</table>
</div>

## 下载

| 平台 | 获取 | 说明 |
| --- | --- | --- |
| Windows | [安装器 .exe](../../releases/latest) · [.msi](../../releases/latest) | SmartScreen 提示时：更多信息 → 仍要运行 |
| Linux | [.deb](../../releases/latest) · [.rpm](../../releases/latest) · [.AppImage](../../releases/latest) | AppImage 需先 `chmod +x` |
| macOS（原生版） | [Inkdown-1.0.dmg](../../releases/tag/v1.0.0) | 已签名公证，拖进应用程序直接打开 |
| iOS | 从源码构建 | 计划上架 App Store |

## 功能细览

<details>
<summary><b>阅读</b></summary>

- GitHub 风格渲染：表格、任务列表、脚注、代码语法高亮
- TeX 公式（MathJax）与 mermaid 图表，完全离线
- 三套主题（默认 / 衬线 / 纸色），字号 10 到 24 pt，三档行宽
- 每个文件记住阅读位置；内置 PDF 阅读器
- 演示模式：按 `#` / `##` 标题切分幻灯片，方向键翻页

</details>

<details>
<summary><b>标注</b></summary>

- 在渲染页面选中文字，浮动工具条即刻出现
- 五色高亮、加粗、下划线、删除线，一键清除
- 笔记以标准 Markdown 脚注存储，Obsidian 与 GitHub 通用
- 划线汇总（Cmd+Shift+H）：整个文件夹的标注一页复盘

</details>

<details>
<summary><b>导航</b></summary>

- 侧栏三层：Home 懒加载浏览区、专注文件夹树、最近文件
- 打开的文件下方自动展开标题大纲
- 快速打开（Cmd+P）、文件夹全文搜索（Cmd+Shift+F）
- `[[双链]]` 在文件夹内跳转，反链区列出反向链接

</details>

<details>
<summary><b>翻译与 AI（macOS / iOS）</b></summary>

- 端侧中英互译：代码、文件名、路径、URL 永不误翻，代码内注释照常翻译
- 选中即译；配合 Apple Intelligence 对选中"解释"、对全文"摘要"，全程本地

</details>

<details>
<summary><b>编辑</b></summary>

- 默认纯阅读，Cmd+E 才展开源码编辑器
- 语法着色编辑器，停笔自动保存
- 侧栏内新建、重命名、移入废纸篓；支持 Finder 双击打开

</details>

## 从源码构建

**macOS / iOS**（Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)）：

```bash
git clone https://github.com/lytreallynb/markreader-ios.git
cd markreader-ios
xcodegen generate
open MarkReader.xcodeproj      # scheme：MarkReaderMac、MarkReader（iOS）
```

**Windows / Linux**（Node 20+、Rust）：

```bash
cd desktop
npm install
npm run dev
```

每次打 `desktop-v*` 标签，CI 自动构建三平台安装包到 [Releases](../../releases)。`bash scripts/release.sh` 产出签名的原生 macOS DMG。

## 快捷键

| 快捷键 | 功能 | | 快捷键 | 功能 |
| --- | --- | --- | --- | --- |
| Cmd+P | 快速打开 | | Cmd+E | 源码编辑器 |
| Cmd+Shift+F | 全文搜索 | | Cmd+加号 / 减号 | 字号 |
| Cmd+Shift+H | 划线汇总 | | Cmd+S | 立即保存 |

<div align="center">
<sub>

SwiftUI · cmark-gfm · WKWebView · highlight.js · MathJax · mermaid · PDFKit · Translation · FoundationModels · Tauri

示例文档见 [`demo/`](demo/) · Made by [Coldice](https://yutonglv.com)

</sub>
</div>
