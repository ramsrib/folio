# Folio — architecture notes & engineering decisions

> How the interesting parts work and **why they're built that way** — the design
> reasoning that doesn't fit in code comments. Audience: future contributors
> (human or agent) about to change one of these areas. [`README.md`](README.md)
> says *what works*; [`VISION.md`](VISION.md) says *where it's going*; this file
> says *why it is the way it is*.

## The stores

Everything hangs off two `@MainActor` observable objects, both owned by the app
scene and injected everywhere:

- **`VaultStore`** — the vault: file tree + flat list, the open note's text
  (disk is always the source of truth; saves are debounced, atomic, lossless),
  tabs + navigation history + recents, and the link/tag indexes.
- **`UIState`** — window-level UI: palette flags, view mode, cross-view pulses
  (`escapePulse`, `sidebarFilterFocus`, `pendingFind`).

`VaultStore` and `UIState` are **per window**; `AppSettings` is app-wide
(appearance belongs to the person, not the window). `VaultStore.init` is
deliberately cheap and `start()` does the scanning: scanning inside a view's
`StateObject` construction mutates `@Published` state mid-view-update, re-enters
SwiftUI's update cycle, and hangs before the window ever appears.

## Windows: one vault each

`WindowCoordinator` owns window identity — the pending-vault queue, the
store↔`NSWindow` registry, the session, and `open(_:)` as the single focus-or-open
entry point. SwiftUI's scene is a plain `WindowGroup(id:)` whose only job is
"materialize one more window when asked".

Four things here are load-bearing, each learned the hard way:

- **`.handlesExternalEvents(matching: [])`.** A `WindowGroup` handles Finder/CLI
  opens *itself*, materializing a scene per event — on top of AppKit delivering
  the same event to `application(_:open:)`. That minted a ghost, vault-less
  window per external open (and drained a pending claim). The delegate is now the
  only external-open path. Consequence: a launch *caused by* a document open then
  presents zero windows, so `applicationDidFinishLaunching` summons one when
  `NSApp.windows.isEmpty`.
- **A value-typed `WindowGroup(for:)` cannot express this lifecycle.** Windows
  acquire their vault *after* creation (launch, ⌘N, an external open landing in
  the launch window), so they stay tagged `nil` and `openWindow(value:)` never
  matches them. Identity lives in the coordinator instead.
- **`.restorationBehavior(.disabled)`.** Otherwise AppKit restores one window per
  saved window record *and* `VaultSession` restores its own — two systems racing
  over how many windows exist. This is also why a bundle id that once quit with N
  windows kept relaunching to N.
- **`@FocusedObject`, not `@FocusedValue`,** for the menu commands. Focused
  *values* only re-evaluate when which object is focused changes, not when its
  `@Published` properties do — so `canGoBack` goes stale, and since disabled state
  gates key equivalents, ⌘[ / ⌘] silently stop working.

A window never swaps its vault (`VaultStore.adopt` asserts it): opening another
vault opens a window. On macOS a window with no vault stays empty rather than
reopening the last one — that fallback made every stray window masquerade as a
real one.

**Measuring windows:** use CoreGraphics (`CGWindowListCopyWindowInfo`, layer 0).
`System Events` both over- and under-counts this app. And always test under a
**fresh bundle identifier** — a reused one carries restoration state that silently
changes the window count.

## Search: scan, don't index

`⇧⌘F` content search (`ContentSearchModel`) is a **brute-force scan at query
time** — deliberately not an index.

- **Why no index:** an index's cost isn't building it, it's *maintenance* —
  staying correct through renames, external writes (our files are edited by
  agents and git constantly), and crashes mid-update. A stale index returns
  wrong answers silently. A scan is O(vault bytes) per query; string scanning
  runs at GB/s; a few-MB vault scans in single-digit milliseconds. VS Code
  reached the same conclusion (ripgrep at query time, no index, any size).
- **What makes it feel indexed:** an mtime-keyed content cache
  `[URL: (mtime, text)]`. Every query walks all files, but only *changed* files
  are re-read from disk. The cache lives in the palette's model, so it exists
  **only while the palette is open** — search sessions are fast, and the app
  doesn't hold the vault's full text at rest.
- **Semantics:** space-separated words **AND** together (all must appear in a
  file, anywhere — matching every search tool's expectation); a quoted query is
  one exact phrase. Case-insensitive, literal (the matcher is Foundation's
  ICU-backed `String.range(of:options:)` — the "engine" is already a library;
  our ~150 lines are AND-gating, snippets, and occurrence bookkeeping, which no
  library provides because they're coupled to our UX).
- **Jump plumbing:** each snippet records its first-hit term and that term's
  occurrence index within the file. ↵ passes `(term, occurrence)` through
  `UIState.pendingFind`; the note pane opens the find bar on that query and
  focuses that occurrence. Known approximation: reading mode counts occurrences
  over *rendered* blocks, so heavy frontmatter/tables before the hit can land
  on a neighbor (exact in writing mode).
- **Freshness:** a debounce (150 ms), a generation counter (stale in-flight
  scans are discarded; scans check cancellation between files), and a re-run
  when `VaultStore.revision` bumps (any watcher-observed change).
- **When this answer changes:** ~10k+ notes or vault text in the hundreds of
  MB. The upgrade is SQLite FTS5 (in the OS, no dependency), treated as a
  disposable cache rebuilt from disk. All matching is isolated in one `scan()`
  function precisely so that swap doesn't touch the palette/jump plumbing.
  Regex, `tag:`/`path:` operators, and OR/negation belong to that same future.

## The indexes that DO exist (and why they're fine)

`VaultStore` maintains three small derived structures: `noteByName` (wikilink
resolution), `backlinkMap`, and `tagsIndex`. These are cheap to keep correct
because they're **patched per-file**: the FSEvents watcher reports *which paths*
changed, and content-only changes to known notes re-extract just that note's
links/tags and splice the maps (an `mtime`-keyed `linkCache` skips unchanged
files even on full rescans). Structural events — creates, deletes, renames,
directory changes, event-queue overflow, or batches >16 notes — fall back to a
full rescan, so correctness never depends on the fast path. Watcher events are
debounced (400 ms) because agents and `git pull` write in bursts; the perf log
(`log stream --level debug --predicate 'subsystem == "com.sriramb.folio"'`)
records what every refresh and reindex cost.

## Memory model

Disk is the store; memory holds what's active. Everything below is a
disposable cache — emptying any of them loses nothing.

| Resident | What | Bound |
|---|---|---|
| always | file list (names/paths), open note text, link/tag indexes | ~vault metadata |
| while search palette open | full text of all notes (mtime-keyed) | vault text size |
| app lifetime, bounded | parsed blocks (~24 docs), rendered lines (~4096), highlighted code (~512), decoded images (~64, mtime-keyed) | crude reset on overflow |
| session | per-note scroll offsets, navigation history (~100), recently closed tabs (~20) | small |

## Reading pipeline

macOS reading mode is **one TextKit 2 text view** holding the whole note
(`NoteReader` → `NoteTextView`, built by `NoteTextRenderer` from
`MarkdownParser`'s blocks). One text stream is what makes selection, ⌘A, copy,
Look Up, drag-out and real accessibility work — the note is a single
`AXTextArea`. It also means both modes lay text out with the same engine from
the same `Typography` constants, so ⌘E can't reflow the page.

This replaced a block-per-view SwiftUI stack whose selection could never cross
a block, because macOS cannot extend a selection across separate views. That
design also forced a trade between fast tab switching, pixel-exact scroll
restore, and selection ("the layout triangle") — one text view dissolves it.
**iOS still runs the block reader** (`ReadingView`, `#if !os(macOS)`) until it
gets the same treatment.

What is *not* text:

- **Tables and the properties card** are SwiftUI, hosted via
  `NSTextAttachmentViewProvider`. An attachment is one character in the same
  stream, so a selection runs straight through them, and copy substitutes each
  block's Markdown source (`.folioSource`).
- A hosted block must be measured with its **width pinned inside SwiftUI**
  (`rootView.frame(width:)`). `NSHostingView`'s intrinsic size reports the
  *ideal* layout, and for a wide table the height that comes back with it is
  near zero — TextKit reads zero height as "no view" and draws the generic
  document icon in place of the block.

TextKit has no block backgrounds, so code cards, callout fills, quote bars and
rules are **drawn** from laid-out fragment geometry in `drawBackground`. That
is bounded to the viewport: measuring a range lays it out, so walking every
decoration would lay out the whole document on each draw pass.

Intra-block line breaks use **U+2028**, not `\n`. TextKit treats `\n` as a
paragraph terminator, so a hard-wrapped paragraph would fire `paragraphSpacing`
after every wrapped source line. Copy converts them back.

Per-note scroll memory is AppKit-level (`ScrollMemory`: clip-view bounds
notifications record offsets continuously; restore is suppressed while a
switch is in flight and skipped when a find/outline jump owns the position).

## Typography

Everything derives from the user's body size via `Typography`, so ⌘+/⌘− scales
the whole note rather than just its prose, and one line-height constant governs
both modes. Writing mode reads the same values (`Theme` is built from
`AppSettings`), which is what keeps ⌘E from reflowing the text.

Both text views **own their container width** (`applyReadableInset`). With
`widthTracksTextView`, AppKit resizes the container from the stale inset on
every `setFrameSize`, re-wrapping the text twice per frame while a pane
animates. Setting the width ourselves means a sidebar slide moves the column
instead of reflowing it.

`LineBreakMode.auto` (the default) decides per paragraph whether a newline is a
wrap artifact or deliberate: wrapped runs have non-final lines that are all
full *and* continuations that mostly start lowercase. Length alone cannot
separate "Overall: 4/10 / Recording: …" from wrapped prose; the capital can.

## SwiftUI/AppKit traps we paid for (don't re-learn these)

1. **Never put `.onTapGesture(count: 2)` over a single-click target.** The
   recognizer holds *every* click for the double-click interval to
   disambiguate — it read as ~1s of UI lag on tabs and sidebar rows. Fire the
   single action immediately and detect doubles manually by timestamp
   (`NSEvent.doubleClickInterval`), designing the double action to *upgrade*
   an already-fired single (see `openInOwnTab`). Re-learned the hard way: the
   sidebar title bar kept its count-2 zoom gesture, so the vault-name button
   added inside it inherited a half-second delay before the switcher appeared.
   `sidebarTitleArea` now detects the double by timestamp.
2. **`@Published` fires on same-value writes.** An unconditional
   `ui.mode = .read` on every selection change re-rendered the entire window
   twice per tab switch. Guard hot-path writes: `if x != v { x = v }`.
3. **Don't mutate AppKit per SwiftUI update.** `updateNSView` runs on *every*
   content update; unconditionally re-setting `NSWindow` styleMask/background
   or walking the view tree re-setting scroller styles invalidates window-wide
   layout each interaction. Cache what was applied; make every setter
   conditional; coalesce walks to one per runloop turn.
4. **The field editor will betray you.** NSTextField (and SwiftUI TextField)
   edits through a shared, lazily-created field editor whose first session
   flashes untamed chrome — including a prediction panel in its *own window*,
   unreachable by any SwiftUI styling or opacity. Post-focus taming and
   pre-warming both fail (AppKit re-applies attributes when editing begins).
   The fix was to not use it: palette fields are a plain NSTextView
   (`PaletteTextField`) with predictions dead before first draw. Corollary:
   an always-mounted TextField also steals first-responder at launch and races
   palettes for focus — the sidebar filter is collapsed behind ⇧⌘K partly for
   this reason.
5. **Unhandled keys beep.** Reading mode often has no first responder, so any
   key nothing claims reaches the window and AppKit plays the alert funk. Esc
   is consumed at a window-level monitor: dismiss palettes → close find bar →
   swallow.
6. **`isMovableByWindowBackground` + gestures don't mix.** AppKit arbitrates
   window-move vs. event-delivery by the hit view's `mouseDownCanMoveWindow`;
   SwiftUI gestures never get a vote. The sidebar resize handle is a real
   NSView returning `false`; the window moves only by the title-bar strip
   (`WindowDragGesture`), which is also the native document-app convention.
7. **`.swipe`/`.magnify`/key monitors must be window-scoped and palette-gated**,
   and swipe's `deltaX` sign is the opposite of the naive reading (SDK header:
   −1 = rightward = Back, matching Safari).
8. **WindowGroup autosave names derive from the root view's type.** Every
   added modifier changed the type, silently resetting saved window frames.
   The named `Window("Folio", id: "main")` scene gives a stable frame key.

## External surface (for agents and tools)

- `open -a Folio note.md` — 3-tier vault resolution: current vault → deepest
  matching recent vault → the file's parent directory as a new vault
  (symlink-resolved comparisons so aliased paths don't spawn duplicate vaults).
- `folio://open?vault=…&file=…` — deep links; "Copy Folio Link" emits them.
  External opens always get their **own tab** — never evict what's being read.
- Relative markdown links resolve in-app (note's folder, then vault root):
  `.md` navigates like a wikilink; in-vault folders reveal in the sidebar;
  out-of-vault folders are ignored (a doc link never bounces to Finder).
