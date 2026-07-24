/* Inkdown Desktop: Tauri + system webview port of the macOS app. */
"use strict";

const T = window.__TAURI__ || {};
const dialog = T.dialog;
const fs = T.fs;
const pathApi = T.path;

const el = (id) => document.getElementById(id);
const contentEl = el("content");
const scrollEl = el("content-scroll");
const editorEl = el("editor");
const treeEl = el("tree");
const recentsEl = el("recents");
const titleEl = el("doc-title");
const seltoolbar = el("seltoolbar");

let SEP = "/";
let rootDir = null;
let flatFiles = [];
let currentPath = null;
let sourceText = "";
let renderTimer = null;
let saveTimer = null;
let mathStore = [];

/* ---------- markdown-it setup ---------- */
const md = window
  .markdownit({
    html: true,
    linkify: true,
    highlight(str, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try { return hljs.highlight(str, { language: lang }).value; } catch (e) {}
      }
      return "";
    },
  })
  .use(window.markdownitFootnote)
  .use(window.markdownitMark)
  .use(window.markdownitTaskLists);

md.core.ruler.push("sourcepos", (state) => {
  for (const token of state.tokens) {
    if (token.map && (token.type.endsWith("_open") || token.type === "fence" || token.type === "html_block")) {
      token.attrSet("data-sourcepos", `${token.map[0] + 1}:1-${token.map[1]}:1`);
    }
  }
});

/* ---------- fence-aware preprocessing (math masking, wiki links) ---------- */
function mathToken(i) { return `⟦MJ${i}⟧`; }
function htmlEscape(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

function walkOutsideFences(text, transform) {
  const out = [];
  let buf = [];
  let inFence = false;
  let marker = "";
  const flush = () => { if (buf.length) { out.push(transform(buf.join("\n"))); buf = []; } };
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (inFence) {
      out.push(line);
      if (t.startsWith(marker)) inFence = false;
      continue;
    }
    if (t.startsWith("```") || t.startsWith("~~~")) {
      flush();
      inFence = true;
      marker = t.slice(0, 3);
      out.push(line);
      continue;
    }
    buf.push(line);
  }
  flush();
  return out.join("\n");
}

function preprocess(text) {
  mathStore = [];
  return walkOutsideFences(text, (seg) => {
    seg = seg.replace(/\$\$([\s\S]+?)\$\$/g, (m) => { mathStore.push(m); return mathToken(mathStore.length - 1); });
    seg = seg.replace(/(?<![\\$])\$(?![\s$])([^$\n]+?)(?<![\s\\])\$(?!\d)/g, (m) => { mathStore.push(m); return mathToken(mathStore.length - 1); });
    seg = seg.replace(/\[\[([^\]|\n]+?)(?:\|([^\]\n]+?))?\]\]/g, (m, target, alias) =>
      `<a class="wiki" data-wiki="${htmlEscape(target)}">${htmlEscape(alias || target)}</a>`);
    return seg;
  });
}

function renderMarkdown() {
  let html = md.render(preprocess(sourceText));
  mathStore.forEach((raw, i) => { html = html.split(mathToken(i)).join(htmlEscape(raw)); });
  contentEl.innerHTML = html;

  contentEl.querySelectorAll("pre code.language-mermaid").forEach((code) => {
    const div = document.createElement("div");
    div.className = "mermaid";
    div.textContent = code.textContent;
    code.parentElement.replaceWith(div);
  });
  try {
    mermaid.initialize({ startOnLoad: false, theme: matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default" });
    mermaid.run({ querySelector: "#content .mermaid" });
  } catch (e) {}
  if (window.MathJax && MathJax.typesetPromise) {
    try { MathJax.typesetClear(); MathJax.typesetPromise([contentEl]).catch(() => {}); } catch (e) {}
  }
  renderOutline();
}

/* ---------- headings / outline ---------- */
function parseHeadings(text) {
  const result = [];
  let inFence = false;
  let marker = "";
  text.split("\n").forEach((line, i) => {
    const t = line.trim();
    if (inFence) { if (t.startsWith(marker)) inFence = false; return; }
    if (t.startsWith("```") || t.startsWith("~~~")) { inFence = true; marker = t.slice(0, 3); return; }
    const m = t.match(/^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$/);
    if (m) result.push({ level: m[1].length, title: m[2].replace(/[*_`~]|==|<[^>]+>/g, "").trim(), line: i + 1 });
  });
  return result;
}

function scrollToLine(line) {
  let best = null;
  let bestLine = -1;
  contentEl.querySelectorAll("[data-sourcepos]").forEach((node) => {
    const start = parseInt(node.getAttribute("data-sourcepos"));
    if (!isNaN(start) && start <= line && start > bestLine) { best = node; bestLine = start; }
  });
  if (best) best.scrollIntoView({ behavior: "smooth", block: "start" });
}

function renderOutline() {
  document.querySelectorAll(".outline-holder").forEach((n) => n.remove());
  const active = treeEl.querySelector(".file-row.active");
  if (!active || !currentPath) return;
  const holder = document.createElement("div");
  holder.className = "outline-holder";
  for (const h of parseHeadings(sourceText)) {
    const row = document.createElement("button");
    row.className = "outline-row";
    row.style.paddingLeft = `${14 + (h.level - 1) * 10}px`;
    row.textContent = h.title;
    row.onclick = () => scrollToLine(h.line);
    holder.appendChild(row);
  }
  active.after(holder);
}

/* ---------- folder tree ---------- */
async function buildTree(dir, depth) {
  if (depth > 8) return [];
  let entries;
  try { entries = await fs.readDir(dir); } catch (e) { return []; }
  const skip = new Set(["node_modules", "Pods", "DerivedData", "__pycache__", "venv", "target"]);
  const folders = [];
  const files = [];
  for (const entry of entries) {
    if (!entry.name || entry.name.startsWith(".")) continue;
    const full = dir + SEP + entry.name;
    if (entry.isDirectory) {
      if (skip.has(entry.name)) continue;
      const children = await buildTree(full, depth + 1);
      if (children.length) folders.push({ name: entry.name, path: full, dir: true, children });
    } else if (/\.(md|markdown)$/i.test(entry.name)) {
      files.push({ name: entry.name, path: full, dir: false });
    }
  }
  const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true });
  return folders.sort(byName).concat(files.sort(byName));
}

function renderTree(nodes, container) {
  for (const node of nodes) {
    if (node.dir) {
      const details = document.createElement("details");
      const summary = document.createElement("summary");
      summary.textContent = node.name;
      details.appendChild(summary);
      renderTree(node.children, details);
      container.appendChild(details);
    } else {
      const row = document.createElement("button");
      row.className = "file-row";
      row.textContent = node.name.replace(/\.(md|markdown)$/i, "");
      row.dataset.path = node.path;
      row.onclick = () => openFile(node.path);
      container.appendChild(row);
      flatFiles.push(node.path);
    }
  }
}

async function openFolder(dir) {
  rootDir = dir;
  localStorage.setItem("lastFolder", dir);
  flatFiles = [];
  treeEl.innerHTML = "";
  const title = document.createElement("div");
  title.className = "section-title";
  title.textContent = dir.split(SEP).pop() || dir;
  treeEl.appendChild(title);
  renderTree(await buildTree(dir, 0), treeEl);
  markActive();
}

function markActive() {
  treeEl.querySelectorAll(".file-row").forEach((row) => {
    row.classList.toggle("active", row.dataset.path === currentPath);
  });
  renderOutline();
}

/* ---------- open / save ---------- */
async function openFile(path) {
  await flushSave();
  try { sourceText = await fs.readTextFile(path); } catch (e) { alert("Could not open file: " + e); return; }
  currentPath = path;
  titleEl.textContent = path.split(SEP).pop().replace(/\.(md|markdown)$/i, "");
  editorEl.value = sourceText;
  renderMarkdown();
  markActive();
  addRecent(path);
  const saved = parseFloat(localStorage.getItem("scroll." + path) || "0");
  requestAnimationFrame(() => {
    setTimeout(() => {
      const h = scrollEl.scrollHeight - scrollEl.clientHeight;
      scrollEl.scrollTop = saved > 0.001 && h > 0 ? saved * h : 0;
    }, 200);
  });
}

function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flushSave, 800);
}
async function flushSave() {
  clearTimeout(saveTimer);
  if (!currentPath) return;
  try { await fs.writeTextFile(currentPath, sourceText); } catch (e) {}
}
function setSource(next) {
  sourceText = next;
  if (editorEl.value !== next) editorEl.value = next;
  clearTimeout(renderTimer);
  renderTimer = setTimeout(renderMarkdown, 200);
  scheduleSave();
}

/* ---------- recents ---------- */
function loadRecents() { try { return JSON.parse(localStorage.getItem("recents") || "[]"); } catch (e) { return []; } }
function addRecent(path) {
  const recents = loadRecents().filter((p) => p !== path);
  recents.unshift(path);
  localStorage.setItem("recents", JSON.stringify(recents.slice(0, 10)));
  renderRecents();
}
function renderRecents() {
  recentsEl.innerHTML = "";
  for (const path of loadRecents()) {
    const row = document.createElement("button");
    row.className = "recent-row";
    row.textContent = path.split(SEP).pop().replace(/\.(md|markdown)$/i, "");
    row.title = path;
    row.onclick = () => openFile(path);
    recentsEl.appendChild(row);
  }
}

/* ---------- annotations ---------- */
function normalize(s) { return s.replace(/ /g, " ").trim(); }
function escapeRegExp(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

function windowFor(sourcePos) {
  if (!sourcePos) return null;
  const start = parseInt(sourcePos.split("-")[0]);
  const end = parseInt(sourcePos.split("-")[1]) || start;
  if (isNaN(start)) return null;
  const lines = sourceText.split("\n");
  const a = Math.max(0, start - 2);
  const b = Math.min(lines.length, end + 1);
  let offset = 0;
  for (let i = 0; i < a; i++) offset += lines[i].length + 1;
  let length = 0;
  for (let i = a; i < b; i++) length += lines[i].length + 1;
  return { offset, length };
}

function wrapSelection(needle, sourcePos, prefix, suffix) {
  const clean = normalize(needle);
  if (!clean) return false;
  const win = windowFor(sourcePos);
  const ranges = win ? [[win.offset, win.length], [0, sourceText.length]] : [[0, sourceText.length]];
  for (const [off, len] of ranges) {
    const idx = sourceText.slice(off, off + len).indexOf(clean);
    if (idx >= 0) {
      const at = off + idx;
      setSource(sourceText.slice(0, at) + prefix + clean + suffix + sourceText.slice(at + clean.length));
      return true;
    }
  }
  return false;
}

function removeHighlight(markText, sourcePos) {
  const esc = escapeRegExp(normalize(markText));
  const patterns = [new RegExp(`<mark[^>]*>${esc}</mark>`), new RegExp(`==${esc}==`)];
  const win = windowFor(sourcePos);
  const ranges = win ? [[win.offset, win.length], [0, sourceText.length]] : [[0, sourceText.length]];
  for (const re of patterns) {
    for (const [off, len] of ranges) {
      const seg = sourceText.slice(off, off + len);
      const m = seg.match(re);
      if (m) {
        const at = off + m.index;
        setSource(sourceText.slice(0, at) + normalize(markText) + sourceText.slice(at + m[0].length));
        return true;
      }
    }
  }
  return false;
}

function selectionInfo() {
  const sel = getSelection();
  if (!sel || sel.isCollapsed || !sel.toString().trim()) return null;
  let node = sel.anchorNode;
  if (node && node.nodeType === Node.TEXT_NODE) node = node.parentElement;
  if (!node || !contentEl.contains(node)) return null;
  let mark = null;
  let pos = null;
  for (let cur = node; cur && cur !== contentEl; cur = cur.parentElement) {
    if (!mark && cur.tagName === "MARK") mark = cur;
    if (!pos && cur.hasAttribute && cur.hasAttribute("data-sourcepos")) pos = cur.getAttribute("data-sourcepos");
  }
  return { text: sel.toString(), pos, markText: mark ? mark.textContent : null };
}

let toolbarTimer = null;
document.addEventListener("selectionchange", () => {
  clearTimeout(toolbarTimer);
  toolbarTimer = setTimeout(() => {
    const info = selectionInfo();
    if (!info) { seltoolbar.classList.add("hidden"); return; }
    el("selclear").style.display = info.markText ? "" : "none";
    const rect = getSelection().getRangeAt(0).getBoundingClientRect();
    seltoolbar.classList.remove("hidden");
    const w = seltoolbar.offsetWidth;
    const left = Math.min(Math.max(rect.left + rect.width / 2 - w / 2, 8), innerWidth - w - 8);
    let top = rect.top - seltoolbar.offsetHeight - 10;
    if (top < 8) top = rect.bottom + 10;
    seltoolbar.style.left = left + "px";
    seltoolbar.style.top = top + "px";
  }, 180);
});
seltoolbar.addEventListener("mousedown", (e) => e.preventDefault());
seltoolbar.addEventListener("click", (e) => {
  const target = e.target.closest("[data-action]");
  const info = selectionInfo();
  seltoolbar.classList.add("hidden");
  if (!target || !info) return;
  const action = target.dataset.action;
  let ok = true;
  if (action === "highlight") {
    const color = target.dataset.color;
    ok = color === "#ffec9e"
      ? wrapSelection(info.text, info.pos, "<mark>", "</mark>")
      : wrapSelection(info.text, info.pos, `<mark style="background:${color}">`, "</mark>");
  } else if (action === "bold") ok = wrapSelection(info.text, info.pos, "**", "**");
  else if (action === "underline") ok = wrapSelection(info.text, info.pos, "<u>", "</u>");
  else if (action === "strikethrough") ok = wrapSelection(info.text, info.pos, "~~", "~~");
  else if (action === "clear" && info.markText) ok = removeHighlight(info.markText, info.pos);
  else if (action === "note") {
    const note = prompt("Note text:");
    if (note && note.trim()) {
      let n = 1;
      for (const m of sourceText.matchAll(/\[\^n(\d+)\]/g)) n = Math.max(n, parseInt(m[1]) + 1);
      if (wrapSelection(info.text, info.pos, "", `[^n${n}]`)) {
        const base = sourceText.endsWith("\n") ? sourceText : sourceText + "\n";
        setSource(base + `\n[^n${n}]: ${note.trim().replace(/\n/g, " ")}\n`);
      } else ok = false;
    }
  }
  if (!ok) alert("Could not match the selection in the source. Try selecting text without inline formatting.");
});

contentEl.addEventListener("click", (e) => {
  const wiki = e.target.closest("a.wiki");
  if (wiki) {
    e.preventDefault();
    const name = wiki.dataset.wiki.toLowerCase();
    const hit = flatFiles.find((p) => p.split(SEP).pop().replace(/\.(md|markdown)$/i, "").toLowerCase() === name);
    if (hit) openFile(hit);
    else alert(`Note "${wiki.dataset.wiki}" was not found in the open folder.`);
    return;
  }
  const link = e.target.closest("a[href]");
  if (link && /^https?:/.test(link.getAttribute("href"))) {
    e.preventDefault();
    window.__TAURI__.opener ? window.__TAURI__.opener.openUrl(link.href) : open(link.href);
  }
});

/* ---------- scroll memory ---------- */
let scrollSaveTimer = null;
scrollEl.addEventListener("scroll", () => {
  clearTimeout(scrollSaveTimer);
  scrollSaveTimer = setTimeout(() => {
    if (!currentPath) return;
    const h = scrollEl.scrollHeight - scrollEl.clientHeight;
    localStorage.setItem("scroll." + currentPath, h > 0 ? String(scrollEl.scrollTop / h) : "0");
  }, 250);
});

/* ---------- appearance ---------- */
const SIZES = [10, 11, 12, 13, 14, 16, 18, 21, 24];
function applyAppearance() {
  const size = parseInt(localStorage.getItem("fontSize") || "16");
  const theme = localStorage.getItem("theme") || "default";
  document.documentElement.style.setProperty("--base-size", size + "px");
  const serif = 'Georgia, Palatino, "Songti SC", "Noto Serif CJK SC", serif';
  document.documentElement.style.setProperty("--body-font", theme === "default" ? "inherit" : serif);
  scrollEl.classList.toggle("sepia", theme === "sepia");
  el("theme-select").value = theme;
}
el("theme-select").onchange = (e) => { localStorage.setItem("theme", e.target.value); applyAppearance(); };
el("size-minus").onclick = () => stepSize(-1);
el("size-plus").onclick = () => stepSize(1);
function stepSize(dir) {
  const size = parseInt(localStorage.getItem("fontSize") || "16");
  const i = Math.max(0, Math.min(SIZES.length - 1, SIZES.indexOf(size) + dir));
  localStorage.setItem("fontSize", String(SIZES[i] || 16));
  applyAppearance();
}

/* ---------- palette (quick open + content search) ---------- */
let paletteMode = "files";
let searchToken = 0;
function showPalette(mode) {
  paletteMode = mode;
  el("palette-input").value = "";
  el("palette-input").placeholder = mode === "files" ? "Type a file name" : "Search text in folder";
  el("palette-results").innerHTML = "";
  el("palette-overlay").classList.remove("hidden");
  el("palette-input").focus();
  if (mode === "files") runPalette("");
}
function hidePalette() { el("palette-overlay").classList.add("hidden"); }
el("palette-overlay").addEventListener("click", (e) => { if (e.target.id === "palette-overlay") hidePalette(); });
el("palette-input").addEventListener("input", (e) => runPalette(e.target.value));
el("palette-input").addEventListener("keydown", (e) => {
  if (e.key === "Escape") hidePalette();
  if (e.key === "Enter") { const first = el("palette-results").querySelector(".palette-row"); if (first) first.click(); }
});

async function runPalette(query) {
  const results = el("palette-results");
  if (paletteMode === "files") {
    const q = query.toLowerCase();
    const hits = flatFiles
      .filter((p) => p.split(SEP).pop().toLowerCase().includes(q))
      .slice(0, 30);
    results.innerHTML = "";
    for (const p of hits) addPaletteRow(results, p.split(SEP).pop(), p.replace(rootDir + SEP, ""), () => { hidePalette(); openFile(p); });
    return;
  }
  if (query.length < 2) { results.innerHTML = ""; return; }
  const token = ++searchToken;
  const q = query.toLowerCase();
  results.innerHTML = "";
  let count = 0;
  for (const p of flatFiles.slice(0, 400)) {
    if (token !== searchToken || count >= 100) break;
    let text;
    try { text = await fs.readTextFile(p); } catch (e) { continue; }
    const lines = text.split("\n");
    for (let i = 0; i < lines.length && count < 100; i++) {
      if (lines[i].toLowerCase().includes(q)) {
        count++;
        const line = i + 1;
        addPaletteRow(results, lines[i].trim().slice(0, 90), `${p.split(SEP).pop()} · line ${line}`, () => {
          hidePalette();
          openFile(p).then(() => setTimeout(() => scrollToLine(line), 350));
        });
      }
    }
  }
}
function addPaletteRow(container, main, sub, action) {
  const row = document.createElement("div");
  row.className = "palette-row";
  row.innerHTML = `<div>${htmlEscape(main)}</div><div class="sub">${htmlEscape(sub)}</div>`;
  row.onclick = action;
  container.appendChild(row);
}

/* ---------- wiring ---------- */
el("open-folder").onclick = async () => {
  const dir = await dialog.open({ directory: true });
  if (dir) await openFolder(dir);
};
el("toggle-editor").onclick = () => editorEl.classList.toggle("hidden");
editorEl.addEventListener("input", () => setSource(editorEl.value));
el("open-help").onclick = () => el("help-overlay").classList.remove("hidden");
el("help-close").onclick = () => el("help-overlay").classList.add("hidden");

window.addEventListener("keydown", (e) => {
  const mod = e.metaKey || e.ctrlKey;
  if (!mod) { if (e.key === "Escape") { hidePalette(); el("help-overlay").classList.add("hidden"); } return; }
  const k = e.key.toLowerCase();
  if (k === "p" && !e.shiftKey) { e.preventDefault(); showPalette("files"); }
  else if (k === "f" && e.shiftKey) { e.preventDefault(); showPalette("content"); }
  else if (k === "e") { e.preventDefault(); editorEl.classList.toggle("hidden"); }
  else if (k === "s") { e.preventDefault(); flushSave(); }
  else if (e.key === "-") { e.preventDefault(); stepSize(-1); }
  else if (e.key === "=" || e.key === "+") { e.preventDefault(); stepSize(1); }
});

window.addEventListener("beforeunload", flushSave);

(async function init() {
  try {
    const s = pathApi && pathApi.sep;
    SEP = typeof s === "function" ? await s() : (s || "/");
  } catch (e) {
    SEP = "/";
  }
  applyAppearance();
  renderRecents();
  if (!fs || !dialog) {
    el("empty").textContent = "Tauri APIs unavailable: check withGlobalTauri and plugin registration.";
    return;
  }
  if (!localStorage.getItem("helpShown")) {
    localStorage.setItem("helpShown", "1");
    el("help-overlay").classList.remove("hidden");
  }
  const last = localStorage.getItem("lastFolder");
  if (last) { try { await openFolder(last); } catch (e) {} }
})();
