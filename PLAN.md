# Slate — a file-backed, Obsidian-replacing notes app

> Working codename: **Slate**. Rename later (folder, bundle id, product name).
> Feature & behavior reference (the *what* we're building toward): [`SPEC.md`](SPEC.md).
> Status: **M0–M2 done; M3 in progress.** Mac app builds & packages; opens a vault as a folder tree,
> watches it (FSEvents), creates/renames/trashes notes, and edits with an Obsidian-style **Live
> Preview** editor (TextKit) that styles Markdown in place, losslessly. **Links layer done:**
> `[[wikilink]]` resolution + `[[` autocomplete, click-to-open, create-on-click for unresolved,
> rename-updates-links across the vault, **quick switcher (⌘O)** and **command palette (⌘P)**.
> **Notion-style UX pass done:** centered reading column, editable page title, hover-reveal floating
> outline + inline collapsible backlinks (no side panels), translucent rounded palettes, clickable
> task checkboxes, `==highlight==`, completed-task styling. **Reading mode done:** a fully-rendered,
> Notion-style read view (⌘E) — headings, lists, real checkboxes, callout boxes, code blocks, tables,
> dividers, images, no syntax symbols. **Reading is the default**; double-click the page (or ⌘E)
> to write; navigation always opens in reading. **File search on ⌘K.**
> Last updated 2026-06-25.

A native, UX-first Markdown notes app that edits your **existing `.md` files in place** — built to
replace Obsidian, starting on macOS.

---

## 1. What changed from v1 of this plan (read this first)

The original plan assumed a self-contained notes store (SwiftData + CloudKit as source of truth).
The real requirement is different and better: **open the user's existing Markdown files directly from
their project directories, edit them, write them back — and eventually retire Obsidian.** That single
requirement drives three reversals:

| Decision | v1 (wrong) | v2 (this plan) | Why |
|---|---|---|---|
| Source of truth | SwiftData + CloudKit | **Files on disk** (a "vault" = a folder you point at) | The files already exist; they are the truth. A DB would just fight them. |
| Editing model | True WYSIWYG via `AttributedString` round-trip | **Obsidian-style "Live Preview"** (literal Markdown buffer, syntax styled/concealed) | A rich-text round-trip silently reformats and *drops constructs it doesn't understand* (frontmatter, `[[wikilinks]]`, `#tags`, callouts, embeds). Unacceptable on your real files. |
| Sync | CloudKit | **Wherever the files live** (iCloud Drive folder / git / Dropbox) | Files-based sync is what Obsidian users already do; nothing to build. |

The "WYSIWYG feel" you want is still the goal — Live Preview *looks* WYSIWYG (hides `**`, renders
headings big, etc.) but is lossless because the buffer is always the literal file text.

## 2. Goals & principles

- **UX is the product.** Smooth, fast, modern, native. The writing experience is the whole point.
- **Edit existing files in place, losslessly.** Never reformat or drop content the user didn't touch.
- **Obsidian-compatible.** Read a folder of `.md`, preserve frontmatter / wikilinks / tags / callouts
  / embeds / attachments. Goal: become the user's daily driver over Obsidian.
- **Apple-native, latest-only.** macOS 26 / iOS 26. No back-compat tax.
- **Local-first.** No server, no account. Sync = the folder's location.
- **Automated & reproducible build.** SPM + scripts, no manual Xcode steps on macOS.

## 3. Stack & project shape (macOS phase — locked)

This machine: macOS **26.4.1**, Xcode **26.5**, Swift **6.3.2**.

| Layer | Choice | Notes |
|---|---|---|
| Language / UI | Swift 6.3 + SwiftUI | + AppKit (`NSViewRepresentable`) for the real editor |
| Project | **SwiftPM executable** (`Package.swift`, tools 6.2, `.macOS(.v26)`) | Mirrors your `recall-app`; fully scriptable, **zero manual steps**. `make build/run/app/install`, `scripts/package-app.sh` bundles & ad-hoc-signs `Slate.app`. |
| Storage | **The file system** | `VaultStore` enumerates `*.md` under the chosen folder; reads/writes UTF-8. |
| Search index (later) | SQLite FTS5 (throwaway, rebuilt from disk) | Truth stays on disk; index is a cache. |
| Sync | None built — folder location provides it | macOS reads `~/Projects/...` directly. |

**Why SPM, not Xcode/xcodegen (for now):** your files are on the Mac, so a Mac app is an immediate
Obsidian replacement, and SPM builds it with no wizard and no signing ceremony. We bring in
xcodegen/Xcode only when iOS lands (§7), because an iOS bundle can't be expressed in plain SwiftPM.

## 4. The editor — the heart of the app

Both stages edit the **same literal-Markdown text buffer** (so they're swappable and always lossless).

### Stage 1 — Plain text  ✅ done (MVP)
`SwiftUI TextEditor` bound to the file's `String`. Monospaced, byte-for-byte lossless, autosaves
(debounced) back to disk. Ugly but *correct* — it validates the file/open/edit/save loop and proves we
never corrupt files. **This is what's built today.**

### Stage 2 — Live Preview (the real editor)  ✅ done (v1)
`NSTextView` (TextKit) wrapped via `NSViewRepresentable` (`Editors/LivePreviewEditor.swift`). The
buffer stays literal Markdown; `MarkdownHighlighter` sets attributes in place, so the file is never
rewritten. Built:
- styled `# H1`–`###### H6`, `**bold**`, `*italic*`, `` `code` ``, ~~strike~~, fenced code blocks,
  blockquotes, ordered/unordered list markers, `[links](…)`, `[[wikilinks]]`, `#tags`;
- syntax markers **dimmed** when the cursor is on another line and **revealed** (normal color) when
  the cursor is on their line — Obsidian's reveal-on-edit behaviour;
- smart-quote/dash substitution disabled so typing never mutates the file;
- anything not styled (frontmatter, callouts, dataview, embeds) stays as plain text — preserved
  automatically because it's just text.

**Refinements still open:** true *zero-width concealment* of markers (today they're dimmed, not
hidden — fully hiding glyphs needs custom TextKit 2 layout); re-highlight only the edited paragraph
(today re-styles the whole doc per change — fine for normal notes, optimize for very large files);
inline image/attachment rendering; `_underscore_` emphasis.

### Explicitly rejected: true WYSIWYG (`AttributedString` round-trip)
Great for a greenfield store, wrong for editing real files — it reformats and drops unknown syntax.
Kept only as a possible *separate* "rich compose" mode far down the line, never the default.

## 5. Architecture (as built)

```
Sources/Slate/
  SlateApp.swift            @main App + AppDelegate; ⇧⌘O open vault, ⇧⌘R reload
  Models/MarkdownFile.swift file identity = its URL (no DB row)
  Storage/VaultStore.swift  @MainActor: vault URL, file list, open note text, debounced lossless save
  Views/ContentView.swift   NavigationSplitView: file-list sidebar │ editor; empty-states
  Editors/EditorPane.swift  Stage-1 plain-text editor (Stage-2 Live Preview slots in here)
```
Design rule: **views talk to a Markdown `String` + the file list, never to a specific editor engine.**
Swapping Stage 1 → Stage 2 touches only `EditorPane`/`Editors/`, nothing else.

## 6. Roadmap

- **M0 — Bootstrap.** ✅ SPM project, `make`/packaging, app builds & runs. *(done)*
- **M1 — Vault MVP.** ✅ open a folder, recursive `.md` list, open/edit/lossless autosave. *(done)*
  - **M1.1 — Vault basics.** ✅ folder **tree** sidebar (`OutlineGroup`), **FSEvents** external-change
    watching (`VaultWatcher`, live list refresh, ignores our own writes), **new/rename/trash** notes
    (`Rename…` / `Reveal in Finder` / `Move to Trash` context menu), atomic lossless writes. *(done)*
    - *Still open:* live-reload the open note's **content** when it changes on disk (today we refresh
      the file list only, to avoid clobbering unsaved edits); folder-level new-note placement UI.
- **M2 — Live Preview editor.** ✅ TextKit `NSTextView` with in-place Markdown styling + cursor-reveal.
  The marquee UX milestone. *(done — see §4 Stage 2 for built scope & open refinements)*
- **M3 — Obsidian surface.** *(in progress)*
  - ✅ **Links:** `[[wikilink]]` resolution (basename + path), resolved/unresolved styling, `[[`
    autocomplete of note names (auto-closes `]]`), click-to-open, create-on-click for unresolved
    links, **rename-updates-links** across the vault (open note reloaded if its links changed).
  - ✅ **Outline** (Notion-style hover-reveal floating TOC, right edge; click scrolls editor) and
    **Backlinks** (Notion-style inline collapsible section at the note's bottom). No side panels.
  - ✅ **Quick switcher** (⌘O fuzzy open) + **command palette** (⌘P), as translucent rounded palettes.
  - ✅ **UX pass:** centered reading column, editable page title (renames the file), `.sidebar` list
    style, smooth animations, rounded continuous corners, material backgrounds.
  - ✅ **Richer rendering:** clickable task checkboxes (toggle + completed strike/dim), `==highlight==`.
  - ✅ **Reading mode (⌘E):** fully-rendered, Notion-style read view (`Reading/`) — headings,
    nested lists, real checkboxes (tappable), blockquotes, callout boxes, fenced code, tables,
    dividers, local/remote images; inline via Foundation Markdown + wikilink rewrite; outline-click
    scroll; clickable links. Parser stress-tested standalone.
    - **Reading is the default**; every navigation (sidebar, ⌘K search, wikilink) opens in reading
      mode. **Double-click the page** (or the toolbar Edit button / ⌘E) switches to writing. New
      notes and create-on-unresolved-link open straight in edit mode.
  - ✅ **File-name search (⌘K)** — fuzzy quick-open by name/path (the renamed quick switcher).
  - *Still open:* in-editor true concealment (always-WYSIWYG), frontmatter/properties UI, `#tags`
    pane, embeds/transclusion in editor, aliases & heading/block links, unlinked mentions, graph
    view, hover link preview, syntax highlighting in code blocks.
- **M4 — Wrap up macOS v1** (the shippable finish line):
  - [ ] **Live-reload the open note** when it changes on disk (cloud sync / another app / the iOS
        app) without clobbering unsaved edits. *(directly enables the synced dual-app story)*
  - [ ] **Reopen state:** restore last vault + last open note + mode on launch.
  - [ ] **Settings:** recent vaults / switch vault; appearance (theme, font size, readable width).
  - [ ] **App icon**, about, polished first-run empty state.
  - [~] **Robustness:** ✅ ignore dependency/build dirs on scan (`node_modules`, `vendor`, `Pods`,
        `build`, `dist`, `target`, … ; hidden dirs already skipped) so a code-project folder doesn't
        crawl/index package READMEs. Still: large-vault incremental link index, accessibility pass,
        optional user-configurable `.slateignore`/settings.
  - [ ] *(stretch)* syntax highlighting in code blocks; hover link preview; frontmatter/properties;
        `#tags` pane; always-WYSIWYG concealment.
- **M5 — Go multiplatform** (one-time restructure, kept ready by M4): xcodegen project with macOS +
  iOS targets sharing `Sources/`; factor a `#if`-bridged platform layer (color/font/image, file
  pick, watcher) so the shared core compiles on both. macOS behavior unchanged.
- **M6 — iOS reader (+ optional write).** See §7.
- **M7 — Ship both (day 1).** Signing, icons, TestFlight/store prep for macOS + iOS together.

## 7. The two apps — macOS + iOS (ship together on day 1)

**Hard requirement: both apps exist at launch.** macOS is the full editor (current focus); **iOS is a
reader-first companion** to the *same* vaults, with optional write. iOS does **not** need to browse
the local filesystem.

### iOS scope
- **Cloud-synced vaults only.** The vault lives in **iCloud Drive** (recommended) or another
  Files-provider/synced folder. iOS opens it once via `UIDocumentPickerViewController` and keeps a
  **security-scoped bookmark** — no general local-FS browsing.
- **Reader-first:** the Reading view (already cross-platform SwiftUI) is the primary iOS surface —
  browse the vault, follow `[[links]]`, search by name, see backlinks/outline.
- **Optional write:** tap-to-edit with the iOS editor (UITextView port) + an on-screen formatting
  toolbar; lossless writes back to the synced file.
- **Sync = iCloud.** Same files on Mac and iPhone; both apps reconcile external changes to an open
  note (the macOS M4 live-reload item; iOS via `NSFilePresenter`/`NSMetadataQuery`).

### Shared vs iOS-specific
Shared (most of the app): `MarkdownParser`, `InlineMarkdown`, `ReadingView`, `VaultStore` logic,
links/outline/backlinks, palettes, and the `NavigationSplitView` shell (collapses to a drill-down
stack on iPhone automatically). iOS twins needed: editor (`NSTextView`→`UITextView` + custom `[[`
autocomplete), file pick (`NSOpenPanel`→`UIDocumentPicker`), watcher (FSEvents→`NSFilePresenter`/
`NSMetadataQuery`), a `#if`-bridged color/font/image layer, and dropping mac-only bits (menu bar,
Reveal in Finder, `.onHover`, Esc/`onExitCommand`).

### Sequencing (this is what delivers "both day 1")
Wrap up macOS v1 (M4) → one-time multiplatform restructure (M5) → build iOS reader (M6) → ship both
(M7). The restructure happens at the M4/M5 boundary (not mid-feature) so the working `make` flow
isn't disrupted; meanwhile macOS code is kept portable.

## 8. Try it now

```bash
cd ~/Projects/scratch/slate
make run                      # dev loop (launches the app)
# or:  make open              # build + package Slate.app and launch it
# or:  make install           # build + install to /Applications
```
In the app: **⇧⌘O** → pick any folder of Markdown (e.g. an Obsidian vault or a `~/Projects/*/docs`
dir). Files list in the sidebar; click one to edit; changes autosave to disk after ~0.5s.

## 9. Open decisions

- [ ] iOS sync-location: **iCloud Drive vault** (recommended, Obsidian-standard) vs git vs Dropbox. §7.
- [ ] Multiple vaults at once, or one-at-a-time (Obsidian is one-at-a-time per window)?
- [ ] Frontmatter: edit raw, or a structured properties UI (Obsidian Properties)?
- [ ] Product name (Slate is a placeholder).
- [ ] When to sandbox (needed for any future Mac App Store; changes file-access to bookmarks).
