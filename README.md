# Folio

A **read-optimized** Markdown app for **macOS** (iOS later) that opens your **existing `.md` files in
place**. Think Obsidian, but tuned for *reading* a project's docs rather than authoring them. Native
Swift / SwiftUI, files-on-disk as the source of truth.

**The use case it's built for:** agents (Claude Code & friends) author, write, and edit most of the
docs in a project; Folio is the fast, calm **reader** you use to browse and absorb all of them
efficiently. Writing and editing are fully supported — but reading is the default, the most polished
path, and what every interaction is optimized around.

## Built for read-heavy use

- **Reading is the default.** Opening a note, following a link, or switching tabs always lands you in
  the fully-rendered Reading view; writing is one keystroke away (⌘E / double-click) but opt-in.
- **Optimized for scanning many docs.** Tabs with session restore, quick switcher (⌘O), file search
  (⌘K), `#tags` browser, backlinks, and a hover outline — built to move through a whole project's
  notes quickly, not to sit in one document.
- **Calm, low-chrome rendering.** Notion-style reading column, frontmatter shown as a typed
  Properties panel, thin auto-hiding scrollbars, no syntax noise — so the docs, not the editor, are
  what you look at.

- **Feature & behavior reference:** [`SPEC.md`](SPEC.md) — the canonical *what Folio does* (the
  Obsidian-grade north star we build toward). No implementation or timeline.
- **The plan:** [`PLAN.md`](PLAN.md) — architecture, the editor strategy, roadmap, open decisions
  (the *how* and *when*).
- **Status:** M0–M2 done, M3 in progress. The Mac app opens a folder ("vault") as a **folder tree**,
  watches it for external changes, supports **new / rename / trash**, and edits notes in an
  Obsidian-style **Live Preview** editor (styled Markdown, cursor-reveal of syntax, clickable task
  checkboxes, `==highlight==`) with lossless autosave. **Links work:** `[[wikilinks]]` with
  autocomplete, click-to-open, create-on-click, rename-updates-links, plus a **quick switcher (⌘O)** /
  **command palette (⌘P)**, and **file-name search (⌘K)**. **Notion-style UI:** centered reading
  column, editable page title, hover-reveal floating outline, inline collapsible backlinks,
  translucent rounded surfaces, and a fully-rendered **Reading mode** — headings, real checkboxes,
  callout boxes, code, tables, dividers, images, frontmatter as a Properties panel, no syntax symbols.
  **Reading is the default**; double-click the page (or ⌘E) to write; navigation always opens in
  reading. **Tabs** (open/close, ⌘W, drag-to-reorder, ⌘⇧T reopen, ⌘⇧[ / ⌘⇧] cycle) with **session
  restore** — reopen a vault and your open notes come back, Obsidian-style. **Appearance settings (⌘,):**
  theme (System/Light/Dark/Paper), reading font (System/Serif/Mono), font size, line width — applied
  live. The file-name search shortcut is **⌘K**.

## Run it

```bash
make run        # dev loop (launches the app via SwiftPM)
make open       # build + package Folio.app and launch it
make install    # build + install to /Applications
```

Then **⇧⌘O** to open any folder of `.md` files (e.g. an Obsidian vault).

## Why files-on-disk (not a database)

The whole point is to edit notes you *already have*, so the file system is the source of truth — no
SwiftData/CloudKit store, no import/export. Sync is whatever the folder already uses (iCloud Drive,
git, …). The editor keeps the literal Markdown buffer so it never reformats or drops your content;
the upcoming Obsidian-style "Live Preview" layer styles that buffer to *look* WYSIWYG while staying
byte-for-byte lossless. See `PLAN.md` for the full rationale.

## Layout

SwiftPM executable (mirrors the `recall-app` pattern), not an Xcode project — fully scriptable, no
manual setup. Source under `Sources/Folio/` (`Models/`, `Storage/`, `Views/`, `Editors/`).
