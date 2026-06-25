# Slate

A UX-first Markdown notes app for **macOS** (iOS later) that edits your **existing `.md` files in
place** — built to replace Obsidian. Native Swift / SwiftUI, files-on-disk as the source of truth.

- **Feature & behavior reference:** [`SPEC.md`](SPEC.md) — the canonical *what Slate does* (the
  Obsidian-grade north star we build toward). No implementation or timeline.
- **The plan:** [`PLAN.md`](PLAN.md) — architecture, the editor strategy, roadmap, open decisions
  (the *how* and *when*).
- **Status:** M0–M2 done. The Mac app opens a folder ("vault") as a **folder tree**, watches it for
  external changes, supports **new / rename / trash**, and edits notes in an Obsidian-style
  **Live Preview** editor (styled Markdown, cursor-reveal of syntax) with lossless autosave to disk.

## Run it

```bash
make run        # dev loop (launches the app via SwiftPM)
make open       # build + package Slate.app and launch it
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
manual setup. Source under `Sources/Slate/` (`Models/`, `Storage/`, `Views/`, `Editors/`).
