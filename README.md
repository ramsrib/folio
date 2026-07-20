# Folio

A **read-optimized** Markdown app for **macOS** that opens your **existing `.md` files in place**.
Think Obsidian, but tuned for *reading* a project's docs rather than authoring them. Native
Swift / SwiftUI, files-on-disk as the source of truth.

**The use case it's built for:** agents (Claude Code & friends) author, write, and edit most of the
docs in a project; Folio is the fast, calm **reader** you use to browse and absorb all of them
efficiently. Writing is supported — but reading is the default, the most polished path, and what
every interaction is optimized around.

> **Status: early.** macOS is the built target and is genuinely usable day to day. iOS exists but is
> a partial reader. There is **no test suite** and no release build. See
> [Limitations](#limitations) before you point it at anything you can't afford to lose.

## Built for read-heavy use

- **Reading is the default.** Opening a note, following a link, or switching tabs always lands you in
  the fully-rendered Reading view. Writing is opt-in — the Read | Write switch in the title bar or
  ⌘E — and Esc always returns you to reading. There is deliberately no double-click-to-edit, so
  selecting text can never flip the mode.
- **Optimized for scanning many docs.** A fuzzy quick switcher, vault-wide content search,
  back/forward history, tabs with session restore, a `#tags` browser, backlinks, and a hover
  outline — built to move through a whole project's notes quickly, not to sit in one document.
- **Calm, low-chrome rendering.** Centered reading column, frontmatter as a typed Properties panel,
  thin auto-hiding scrollbars, no syntax symbols — so the docs, not the editor, are what you look at.

## What works today (macOS)

Everything in this list is implemented. Anything not in it, assume it isn't.

**Reading**
- Fully-rendered Reading mode: headings, **bold**/*italic*/~~strike~~/`==highlight==`, nested lists,
  clickable task checkboxes (toggling writes back to the file), blockquotes, titled/colored callouts
  (`> [!note]`, `> [!warning]`, …), fenced code with syntax highlighting, tables, dividers, and
  local + remote images.
- YAML frontmatter renders as a **read-only** Properties card, with per-key icons, formatted dates,
  and tag chips — **collapsed by default** to a one-line "Properties · N" row, so opening a note
  lands you on the content; click to expand.
- Vim-style scrolling: `j`/`k`/`h`/`l`, `d`/`u`, `gg`/`G`, space / ⇧space.
- Text selection flows across consecutive paragraphs (not across headings, lists, or code blocks —
  see Limitations).

**Navigating & search**
- **⌘O / ⌘K** — quick switcher. **Fuzzy** name/path matching with highlighted hits, spaces as word
  separators, recency-weighted ranking, recently-opened notes on an empty query, **⇧↵** to create a
  note from the query, **⌘↵** to open in a new tab, and a `#` prefix to jump to a heading in the
  current note.
- **⇧⌘F** — **vault-wide content search.** Case-insensitive literal matching (no regex, no
  operators), live results grouped per file with snippets; ↵ opens the note with the find bar on
  that occurrence.
- **⌘[ / ⌘]** (or ⌘⌥←/→, or a **two-finger swipe** left/right) — **back/forward history** through
  visited notes, with title-bar chevrons.
- **⌘P** — command palette: every app action, fuzzy-matched, including Switch Vault and Set Theme.
- **⇧⌘Y** — tag browser: all inline `#tags` and frontmatter `tags:` with counts; click through to notes.
- **⌘F** — find in page, in *both* reading and writing modes, with case toggle and ⌘G / ⇧⌘G.
- Hover-reveal **outline** at the right edge; click a heading to scroll to it.
- Collapsible **backlinks** at the bottom of a note, each with a line of context.
- **⌘/** — a cheat sheet of every shortcut. It is the authoritative list.

**Vault & files**
- **⇧⌘O** opens any folder of Markdown as a vault (an Obsidian vault works). Recent vaults in the
  File menu; **⇧⌘R** reloads.
- Collapsible folder tree in a resizable sidebar (**⌃⌘S** to toggle). Skips hidden dirs and
  `node_modules`, `build`, `dist`, `target`, etc. The tree **reveals** the current note (expands and
  scrolls to it), remembers folder expansion per vault, and has a **filter field** — every
  space-separated word must appear in the file name.
- Live external-change watching via FSEvents — edits from git, Obsidian, or an agent show up without
  a manual reload, and the open note reloads in place (as long as you have no unsaved local edit
  pending).
- New note (**⌘N**), rename, Move to Trash, Reveal in Finder. Right-click a file for Open in New
  Tab, **Copy Relative / Absolute Path**, **Copy Wikilink**, and **Copy Folio Link**; right-click a
  folder for New Note in Folder and the path copies.
- Open a `.md` from **Finder** ("Open With → Folio") or the terminal (`open -a Folio note.md`): if
  the file is inside the current vault or a recent one Folio switches to it, otherwise it opens the
  file's parent folder as a vault. **`folio://open?vault=…&file=…`** deep links (what **Copy Folio
  Link** puts on the clipboard) jump straight to a note from another app or an agent.
- Right-click the **Dock icon** for recent notes and recent vaults.

**Links**
- `[[wikilinks]]` resolve by basename or path, render resolved vs unresolved, click to open, and
  create the note on click when unresolved.
- Typing `[[` autocompletes **note names**.
- Renaming a note rewrites `[[old]]`, `[[old|alias]]`, and `[[old#heading]]` across the vault.
- Hovering a wikilink in the editor previews the target note.

**Tabs**
- Navigation **reuses the current tab** (Obsidian-style); **⌘-click** a note or wikilink — or **⌘↵**
  in a palette — to open a new tab. **Double-click** a sidebar file to keep both: the note you were
  reading keeps its tab and the new one opens beside it (VS Code's double-click-to-keep-open).
  Creating a note, or opening one **from outside** (Finder, CLI, a `folio://` link), always gets its
  own tab — an external open never evicts what you're reading.
- Open/close (**⌘W**), drag to reorder, reopen closed (**⇧⌘T**), cycle (**⌃⇥** / **⌃⇧⇥**),
  **⌘1–⌘8** to jump to a tab and **⌘9** to the last, close-others / close-tabs-to-the-right / close-all, and a right-click menu with the same copy actions (relative/absolute path, wikilink) as the explorer. Open tabs and the
  active note are **restored per vault** on relaunch.

**Writing**
- A Live Preview editor (TextKit `NSTextView`) that styles the literal Markdown buffer in place, so
  the file stays byte-for-byte lossless. Syntax markers are **dimmed**, and revealed at full contrast
  on the cursor's line — they are not concealed. Smart quotes, dashes, and text replacement are
  disabled so typing can never mutate the file.
- Autosave, debounced ~500 ms, written atomically.
- The page title is editable and renames the file on commit (when the inline title is enabled in ⌘,).

**Appearance (⌘,)**
- Themes: System, Light, Dark, Paper (warm), Frosted (glass).
- Reading font (System / Serif / Mono), body font size (**⌘+ / ⌘− / ⌘0** work anywhere, or
  **pinch** on the trackpad), readable
  line width (default ~70 chars/line), an optional **inline title**, and a **text rendering** choice
  (Crisp / Smooth / Smoother — browser-style stem darkening; applies on relaunch). All applied live
  except text rendering.

## iOS

An iOS target exists and builds, but it is a **partial reader**, not a peer of the Mac app.

- Opens a **cloud-synced folder** (practically iCloud Drive) through the system folder picker and
  remembers it with a security-scoped bookmark. It does not browse the local filesystem.
- Folder browser with note-name search, the shared Reading view, a tag browser, and appearance
  settings.
- Editing is a plain `TextEditor`, saving through the same lossless debounced write.

**Not on iOS:** the Live Preview editor, external-change watching (pull to refresh instead),
find-in-page, backlinks, outline, tabs, and the command palette.

## Build & run

Requires **macOS 26+** and a Swift **6.2+** toolchain (Xcode 26). The macOS app is a plain SwiftPM
executable — no Xcode project, no signing ceremony.

```bash
make build      # swift build
make run        # dev loop — run straight from SwiftPM
make app        # package build/Folio.app (ad-hoc signed)
make open       # package, then launch it
make install    # package and install to /Applications
make clean
```

Then **⇧⌘O** to open a folder of `.md` files.

Note that `make install` **force-quits any running Folio** and replaces `/Applications/Folio.app`.
A locally packaged app falls back to **ad-hoc signing** when no Developer ID certificate is in the
keychain. Proper releases (signed, notarized, published to GitHub Releases and the
[Homebrew tap](https://github.com/ramsrib/homebrew-tap)) are cut with `make release` — see
[`RELEASE.md`](RELEASE.md).

### iOS

The iOS app can't be expressed in plain SwiftPM, so it needs
[XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`:

```bash
brew install xcodegen
xcodegen generate          # writes FolioiOS.xcodeproj (gitignored)
open FolioiOS.xcodeproj
```

Build to an **iOS 26** simulator. Code signing is disabled in `project.yml`, so running on a physical
device means setting your own team and identity first.

## Limitations

Stated plainly, because the alternative is you finding out later:

- **Search is literal.** ⇧⌘F matches exact (case-insensitive) text — no regex, no operators
  (`tag:`, `path:`), no boolean queries. In Reading mode, jumping to a hit can land on a
  *neighboring* occurrence in notes with heavy frontmatter/tables before the match (exact in
  writing mode).
- **Text selection in Reading mode stops at rich blocks.** Selection flows across paragraphs, but
  cannot cross a heading, list, code block, table, or callout — each is a separate SwiftUI view,
  and macOS can't extend a selection across them. A TextKit-backed reading view is the eventual
  fix.
- **No test suite.** Nothing is committed — no unit tests, no parser tests, no test target. File
  writes are lightly exercised by hand only. **Keep backups.**
- **No Source mode**, and Live Preview *dims* Markdown syntax rather than hiding it.
- **File management is thin:** no folder create/rename/delete, no move, no drag-and-drop, no delete
  confirmation. Explorer sorting is by name only.
- **Rename-updates-links has edges:** it rewrites plain wikilinks only. Path-qualified links
  (`[[folder/Note]]`) and Markdown-style links are *not* updated, and you aren't told what changed.
- **Properties are read-only**, and parsed by a line-based heuristic rather than a real YAML parser —
  multiline values, quoting, and nested mappings won't render faithfully.
- **Markdown gaps:** no math, footnotes, Mermaid, comments (`%% %%`), custom checkbox states, heading
  folding, or note/section/block embeds. `![[thing]]` is treated as an image, not a transclusion.
- **Not built at all:** graph view, bookmarks, daily notes, templates, split panes, attachment
  management, export/print.
- **No conflict resolution.** If the same note is edited on two devices at once, Folio will not
  arbitrate — a local save can overwrite an external change that lands mid-debounce.
- **Reading mode fetches remote images** (`![](https://…)`) over the network, which discloses your IP
  to that host. Not currently opt-in.
- macOS 26 / iOS 26 only. UTF-8 Markdown only.

## Why files-on-disk (not a database)

The point is to read and edit notes you *already have*, so the file system is the source of truth —
no SwiftData/CloudKit store, no import/export step. Sync is whatever the folder already uses (iCloud
Drive, git, Dropbox). The editor keeps the literal Markdown buffer and only ever sets *attributes* on
it, so it can look styled while remaining byte-for-byte lossless — it never reformats your files or
drops syntax it doesn't understand.

## Where it's going

[`VISION.md`](VISION.md) is the **aspirational north star** — a design brief for the app Folio is
being built toward. **It is not a feature reference:** most of what it describes is deliberately not
implemented yet, and it says so section by section. This README is the accurate account of what
works.

## Layout

A SwiftPM executable, not an Xcode project — fully scriptable, no manual setup.

```
Sources/Folio/
  Models/    file identity, vault tree, link index
  Storage/   vault store, FSEvents watcher, settings, UI state, platform bridge
  Reading/   Markdown parser, reading view, code + inline highlighters, find
  Editors/   Live Preview editor (TextKit), Markdown highlighter, theme
  Views/     macOS UI — sidebar, tabs, palettes, outline, backlinks, settings
iOS/         iOS-only UI (shares Models/, Storage/, Reading/)
```

Sibling projects using the same shape: [recall-cli](https://github.com/ramsrib/recall-cli),
[recall-app](https://github.com/ramsrib/recall-app), [raven](https://github.com/ramsrib/raven).

## License

MIT — see [LICENSE](LICENSE).
