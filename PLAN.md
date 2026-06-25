# Slate — a file-backed, Obsidian-replacing notes app

> Working codename: **Slate**. Rename later (folder, bundle id, product name).
> Feature & behavior reference (the *what* we're building toward): [`SPEC.md`](SPEC.md).
> Status: **M0–M2 done** — Mac app builds & packages; opens a vault as a folder tree, watches the
> folder for external changes (FSEvents), creates/renames/trashes notes, and edits with an
> Obsidian-style **Live Preview** editor (TextKit) that styles Markdown in place, losslessly.
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
- **M3 — Obsidian surface.** Frontmatter handling, `[[wikilink]]` resolution + autocomplete, `#tags`,
  backlinks panel, image/attachment rendering (relative paths), callouts.
- **M4 — Search & navigation.** SQLite FTS5 index, quick-open (⌘O fuzzy), global search, recents/pins.
- **M5 — UX depth.** Multi-pane/tabs, command palette, themes/typography, keyboard-first flows.
- **M6 — iOS.** See §7 — gated on the sync-location decision; introduces xcodegen/Xcode.
- **M7 — Hardening.** Large-vault performance, accessibility, app icon, polish.

## 7. iOS — the plan, and the one real blocker

iOS can't reach `~/Projects`. To edit the *same* notes on iPhone/iPad, the vault must live somewhere
iOS can read — practically **iCloud Drive** (most common for Obsidian) or a **git-synced** folder.
So iOS is sequenced after we choose that, and it brings:
- an **Xcode/xcodegen** project (SwiftPM can't build an iOS `.app`); the macOS target moves under it,
- **security-scoped bookmarks** + `UIDocumentPicker` for folder access,
- `NSFileCoordinator`/`NSFilePresenter` for safe concurrent (iCloud) access.

Most of `VaultStore`/editor code carries over; it's the project file + file-access layer that changes.

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
