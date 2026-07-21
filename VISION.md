# Folio — Vision

> ## ⚠️ This is the north star, not the product.
>
> **Nothing in this document should be read as a description of what Folio currently does.**
> It describes the app Folio is being *built toward* — the intended end state, most of which is
> **not implemented**. Whole sections here (graph view, transclusion, daily notes, templates,
> bookmarks, split panes, math, plugins) have **no code behind them at all**.
>
> For an accurate, verified account of what actually works today — and what doesn't — see the
> [README](README.md). Where the README and this document disagree, **the README is right** and this
> document is describing an aspiration.
>
> Read this as a design brief: it explains what Folio is *for* and what "done" would look like, so
> that individual features can be judged against a coherent whole.

> **Scope:** features and behaviors only — no implementation details, no timelines, no milestones.
>
> Reference point: Obsidian's experience, adapted to Folio's principles (files-on-disk, UX-first,
> native macOS + iOS). Where Folio intentionally differs from Obsidian, it is called out.

---

## 1. Product principles

These are the commitments the rest of the document is written against — the things Folio should never
trade away as it grows. They are design constraints on future work, not claims about current
behavior.

- **Read-first.** Folio is optimized for *reading* a project's docs, not authoring them. The working
  assumption is that agents and tools write and edit most notes; Folio is the fast, low-friction
  reader used to browse and absorb them. Reading mode is the default and the most polished path;
  writing is fully supported but secondary. Every interaction should make scanning and reading across
  many documents efficient and calm.
- **Find, search, navigate — fast and everywhere.** Locating content and moving through it is the
  core value, not a side feature. In-page find, cross-note/vault search, and keyboard navigation are
  first-class in every view and must stay fast and keyboard-driven. When in doubt, invest here first.
- **Your files are the truth.** A vault is an ordinary folder of `.md` files. Folio reads and writes
  those files in place; there is no hidden database that can drift from disk or lock you in.
- **Lossless, always.** Opening, editing, and saving a note never reformats, normalizes, or drops
  content the user didn't explicitly change — including YAML frontmatter, unusual whitespace, and any
  Markdown/Obsidian syntax Folio doesn't yet understand. Smart-quote/dash/auto-replace substitutions
  never silently alter file bytes.
- **Plain Markdown, portable.** Notes remain readable and editable in any other Markdown app
  (including Obsidian) with no conversion step. Folio-specific features degrade gracefully to plain
  text elsewhere.
- **Local-first.** Fully functional offline, with no account and no required cloud service. Sync is
  whatever the vault folder already uses.
- **Fast and native.** Typing is never laggy. The app feels like a first-class macOS/iOS citizen
  (native controls, gestures, shortcuts, dark mode, Dynamic Type) — not a web page in a wrapper.
- **Private by default.** No telemetry, no analytics, no content leaves the device unless the user's
  own sync/export does it.
- **Keyboard-first, mouse-friendly.** Every common action is reachable by keyboard; nothing requires
  the mouse. Touch is first-class on iOS.

## 2. Vaults

- A **vault** is a user-chosen folder. Opening a vault shows all Markdown notes within it, at any
  nesting depth.
- **Open / switch vaults:** the user can open a vault, switch between recently opened vaults, and see
  a list of recent vaults. The current vault's name is always visible.
- **Multiple vaults:** each open vault window is independent. Switching vaults never mixes notes,
  links, or search across vaults.
- **Reopen state:** relaunching restores the last vault and, ideally, the open notes, pane layout,
  and scroll/cursor positions.
- **Attachments & non-Markdown files:** images, PDFs, and other files inside the vault are part of it
  (for embedding and management) even though they aren't notes.
- **Live external changes:** if files are added, edited, renamed, moved, or deleted outside Folio
  (git pull, Obsidian, Finder, another device's sync), the vault reflects it without a manual reload.

> **Today:** open a folder, recent-vaults menu, and live external-change detection (FSEvents)
> all work on macOS. You can also open a `.md` from Finder / `open -a Folio` (it finds or opens a
> vault around the file), follow `folio://open?vault=…&file=…` deep links, and pick recent notes or
> vaults from the Dock menu. **Not built:** independent multi-vault windows, and restoration of pane layout
> or scroll/cursor position (only open tabs and the active note are restored). Non-Markdown files
> are not surfaced. On iOS there is no watcher — pull to refresh.

## 3. File explorer & file management

- **Folder tree:** notes and folders shown as a collapsible tree mirroring the folder structure on
  disk. Folders can be expanded/collapsed; expansion state persists.
- **Sorting:** by name, created date, or modified date; ascending/descending; folders grouped first.
- **Create:** new note (in a chosen/contextual folder) and new folder. New notes open immediately,
  ready to type, with the title editable.
- **Rename:** rename notes and folders inline. Renaming a note **updates all links that point to it**
  across the vault (see §7).
- **Move:** drag-and-drop notes/folders within the tree; moving updates links accordingly.
- **Delete:** notes/folders go to the system Trash (recoverable), with an optional confirmation for
  destructive deletes. Never a silent permanent delete.
- **Reveal in Finder/Files** and **copy path** for any item.
- **Context menu** on every item with the relevant actions (new, rename, move, delete, reveal, copy
  link, etc.).
- **Filtering:** quickly filter the explorer by typed text.
- Optional: show non-Markdown files; show/hide file extensions; show/hide hidden files.

> **Today:** collapsible folder tree, name sort (folders first), new note, rename (updates wikilinks),
> Move to Trash, Reveal in Finder, a context menu (Open in New Tab, Copy Relative / Absolute Path,
> Copy Wikilink, New Note in Folder), a **filter field** (word-wise name match), auto-reveal of the
> current note, and folder expansion **persisted per vault**. **Not built:** folder
> create/rename/delete, drag-and-drop move, delete confirmation, sort options, and
> hidden/non-Markdown display toggles.

## 4. The editor — modes

Three ways to view/edit the same note. Switching modes should be instant and never alter file
content.

- **Live Preview:** a WYSIWYG-feel editor over the literal Markdown. Formatting renders in
  place (headings large, **bold** bold, lists with bullets, etc.); the syntax markers for the element
  the cursor is on are revealed for editing and concealed elsewhere.
- **Source mode:** shows raw Markdown with light syntax styling, nothing concealed — for precise
  control and for users who think in Markdown.
- **Reading mode:** a fully rendered, read-only view (like a published page) with no editing
  affordances.
- **Per-note and global defaults:** the user can set a default mode and toggle the current note's
  mode with a shortcut/control. New notes can default to a chosen mode.

> **Today:** only two modes exist — Reading (the default) and a Live Preview writing mode, toggled
> with ⌘E. Live Preview *dims* syntax markers rather than concealing them (true zero-width
> concealment needs custom TextKit 2 layout). There is no Source mode and no configurable default
> mode.

## 5. Markdown elements (rendering & editing catalog)

The catalog Folio aims to understand and render. In Live Preview each should render visually while
the underlying text stays plain Markdown.

> **Today:** Reading mode renders headings, emphasis, strikethrough, `==highlight==`, nested lists,
> standard `- [ ]`/`- [x]` tasks, blockquotes, callouts, fenced code (with a language-agnostic
> highlighter), tables, rules, Markdown links, wikilinks, and local/remote images. Everything below
> that isn't in that list — folding, custom checkbox states, collapsible callouts, copy-code,
> assisted table editing, transclusion, footnotes, math, comments, emoji shortcodes, Mermaid — is
> **not implemented**.

- **Headings** `#`–`######`, with size hierarchy; foldable (collapse a heading's section).
- **Emphasis:** bold, italic, bold-italic, ~~strikethrough~~, ==highlight==.
- **Lists:** bulleted, numbered, and nested; mixed nesting; automatic continuation and renumbering.
- **Task lists / checkboxes:** `- [ ]` / `- [x]`, toggle by clicking the box; optional custom states
  (e.g. `- [/]`, `- [-]`) rendered distinctly.
- **Blockquotes**, including nested quotes.
- **Callouts / admonitions:** `> [!note]`, `> [!warning]`, `> [!tip]`, etc., rendered as titled,
  colored, collapsible boxes; custom titles supported.
- **Code:** inline `` `code` `` and fenced blocks with language-aware syntax highlighting; copy-code
  affordance in reading view.
- **Tables:** rendered as real tables; ideally an assisted editing experience (tab between cells,
  add/remove rows/columns) while keeping valid Markdown pipes on disk.
- **Horizontal rules** (`---`, `***`).
- **Links:** external URLs, internal links, and autolinks (see §7).
- **Images & embeds:** local and remote images; transclusions of notes/sections/blocks (see §8).
- **Footnotes:** `[^1]` references with hover/return-to behavior.
- **Math:** inline `$…$` and block `$$…$$` LaTeX rendering.
- **Frontmatter / properties:** YAML block at the top of a note (see §10).
- **Comments:** `%% … %%` shown while editing, hidden in reading mode.
- **Emoji** shortcodes and Unicode.
- **Mermaid / diagram code blocks** rendered as diagrams (aspirational, behind code fences).

## 6. Writing & editing behaviors

- **Smart list handling:** Enter continues the list; Enter on an empty item ends/outdents it; Tab /
  Shift-Tab indent/outdent; numbered lists renumber automatically.
- **Auto-pairing:** typing `(`, `[`, `` ` ``, `"`, `*`, `$`, `[[` auto-closes; wrapping a selection
  with a pair wraps instead of replacing; deleting an opening pair deletes its partner when empty.
- **Markdown shortcuts while typing:** `# ` → heading, `- ` / `* ` → bullet, `1. ` → numbered,
  `> ` → quote, ``` ``` ``` → code block, `[] ` → checkbox.
- **Formatting commands** with standard shortcuts: bold ⌘B, italic ⌘I, etc.; toggling applies/removes
  cleanly around the selection or word.
- **Paste behaviors:** pasting a URL onto a text selection makes it a link; pasting an image saves it
  as an attachment and inserts an embed; pasting rich text converts to clean Markdown; "paste as
  plain text" available.
- **Multiple cursors / multi-selection** for simultaneous edits.
- **Find & replace in note:** literal and regex, case sensitivity, replace one/all.
- **Drag-to-move** selected text; **duplicate line**, **move line up/down**, **delete line** commands.
- **Spellcheck** with the system dictionary; per-language; ignore/learn words.
- **Undo/redo** with sensible granularity; never loses content across mode switches.
- **Word/character/reading-time count** for the note or selection.

> **Today:** the editor gives you undo, standard system text behavior, `[[` note-name autocomplete,
> and lossless saves (smart quotes/dashes/auto-replace are disabled so typing never mutates the
> file). **Essentially none of the rest of this section is implemented** — no smart list continuation,
> no auto-pairing, no Markdown typing transforms, no ⌘B/⌘I formatting commands, no paste behaviors,
> no multiple cursors, no find-and-replace or regex, no line commands, no word count.

## 7. Links & references

The connective tissue — must feel effortless and stay correct.

- **Internal links:** `[[Note Name]]`. Typing `[[` opens an autocomplete of notes (and headings/
  blocks); fuzzy-matched; Enter inserts.
- **Aliases:** `[[Note|shown text]]` renders the alias; alias autocomplete from a note's `aliases`
  property.
- **Heading links:** `[[Note#Heading]]`; **block links:** `[[Note#^blockId]]` with block-reference
  creation on demand.
- **Link rendering:** internal links styled distinctly; clicking navigates; modifier-click opens in a
  new pane/tab.
- **Unresolved links:** links to non-existent notes are styled as "unresolved"; clicking offers to
  create the note (in a sensible default folder).
- **Rename-safe links:** renaming or moving a note **updates every link to it** across the vault; the
  user is informed of how many links changed.
- **External links** open in the default browser; optional confirmation for untrusted URLs.
- **Copy link to note / heading / block** from context menus.

> **Today:** `[[wikilinks]]` resolve (by basename or path), render as resolved/unresolved, click to
> open, create-on-click when unresolved, and `[[` autocompletes **note names**. Renaming a note
> rewrites `[[old]]`, `[[old|alias]]`, and `[[old#heading]]` across the vault. **Caveats:** the rename
> updater does *not* fix path-qualified wikilinks (`[[folder/Note]]`) or Markdown-style links, and
> reports no count. `[[Note#Heading]]` navigates to the note but does **not** scroll to the heading.
> **Not built:** block links, alias resolution from frontmatter, heading/block autocomplete,
> modifier-click-to-new-pane, create confirmation, copy-link commands.

## 8. Embeds & transclusion — *not implemented*

- **Embed a note:** `![[Note]]` renders that note's content inline.
- **Embed a section or block:** `![[Note#Heading]]`, `![[Note#^blockId]]`.
- **Embed an image / PDF / audio / video** by path; images respect size syntax (e.g. `![[img|300]]`).
- Embeds render in Live Preview and Reading mode; an embed is clickable to open the source; circular
  embeds are handled gracefully (no infinite loop).

## 9. Tags

- **Inline tags:** `#tag`, including **nested tags** `#area/subarea`.
- **Tag autocomplete** when typing `#`.
- **Tags in properties:** a `tags` frontmatter property is treated equivalently.
- **Tag pane:** browse all tags with counts; click a tag to see all notes using it; nested tags shown
  hierarchically.
- **Rename a tag** across the vault.
- Tags are searchable and usable as filters everywhere.

> **Today:** inline `#tags` and frontmatter `tags:` are indexed into a browsable tag pane (⇧⌘Y) with
> counts; click a tag to see its notes. **Not built:** tag autocomplete, hierarchical display of
> nested tags, tag rename, and tag filters elsewhere in the app.

## 10. Properties / frontmatter

- **YAML frontmatter** at the top of a note is recognized and editable as **properties**: typed
  key/value pairs (text, number, date, datetime, checkbox, list, tags).
- **Properties editor:** a structured UI to view/add/edit/remove properties without hand-writing YAML
  — while still writing valid YAML to disk and preserving unknown keys.
- **Common properties** with first-class behavior: `aliases`, `tags`, `cssclass`/appearance hints.
- Properties are searchable and usable in filters/queries; a vault-wide view of a property's values
  is possible.
- Frontmatter the user hand-writes is never reordered or stripped.

> **Today:** YAML frontmatter renders as a **read-only** Properties card in Reading mode, with an
> icon and formatting inferred per key (dates, tag chips, links). It is parsed by a small line-based
> heuristic, **not a real YAML parser** — multiline values, quoting, comments, and nested mappings are
> not faithfully represented. **Not built:** editing properties, property search/queries, vault-wide
> property views.

## 11. Backlinks & outgoing links

- **Backlinks panel:** for the current note, all notes that link to it ("linked mentions"), with a
  snippet of context around each link, grouped by source note.
- **Unlinked mentions:** other notes that mention this note's name/aliases without linking, with a
  one-click "link" action.
- **Outgoing links panel:** all links the current note points to, including unresolved ones.
- Counts surface at a glance (e.g., a backlink count on the note).

> **Today:** a collapsible backlinks section at the bottom of a note lists inbound links with a line
> of context. **Not built:** unlinked mentions and the outgoing-links panel.

## 12. Graph view — *not implemented*

- **Global graph:** notes as nodes, links as edges; pan/zoom; click a node to open it.
- **Local graph:** the neighborhood around the current note to a chosen depth.
- **Controls:** filter by tag/path/search, toggle attachments/tags/unresolved, adjust forces, color
  groups by rules.
- Graph reflects the vault live as links change.

## 13. Search

- **Global search** across the vault: full-text, fast, with live results and match highlighting.
- **Operators:** scope by `path:`, `file:`, `tag:`, `line:`, content, property values; boolean
  `AND`/`OR`/`-` negation; quoted phrases; **regex**.
- **Search results** show context snippets; clicking jumps to the match; results can be expanded
  per file.
- **In-note find** (see §6) distinct from global search.
- **Saved searches / bookmarks** of queries (see §15).
- Search is case-insensitive by default with an option for case sensitivity.

> **Today:** in-note find (⌘F) works in both Reading and Writing mode, with case sensitivity and
> next/previous. In Reading mode it searches headings, paragraphs, lists, tasks, quotes, and code —
> it does **not** search callouts, tables, properties, or image alt text.
>
> **Vault-wide content search exists (⇧⌘F):** live, case-insensitive search across every note —
> space-separated words AND together, quotes give an exact phrase — results grouped per file with
> snippets, and ↵ jumps to the occurrence. **Not built:** operators (`path:`, `tag:`, …), OR /
> negation, regex, and saved searches.

## 14. Navigation

- **Quick switcher:** fuzzy "open note by name" with keyboard; create-on-miss; recent-weighted.
- **Command palette:** fuzzy search and run any command; shows current shortcuts.
- **Navigation history:** back/forward through visited notes (buttons + shortcuts + gestures).
- **Outline panel:** the current note's heading hierarchy; click to jump; reflects edits live.
- **Breadcrumbs / title bar** showing the note's location.
- **Go to heading/block** within a note; **scroll to top/bottom**.
- **"Open random note"** and **"open today's daily note"** quick actions.

> **Today:** the quick switcher (⌘O/⌘K) is **fuzzy** with recency weighting, create-on-miss (⇧↵),
> and a `#` prefix that jumps to a heading in the current note; **back/forward history** works
> (⌘[ / ⌘], ⌘⌥←→, a two-finger trackpad swipe, title-bar chevrons); ⌘P runs a fuzzy command
> palette over the app's actions; a
> hover-reveal outline of the current note's headings scrolls on click; and Reading mode has
> vim-style scrolling (j/k/h/l, d/u, gg/G, space). **Not built:** breadcrumbs, block-level go-to,
> random note, daily note.

## 15. Bookmarks — *not implemented*

- **Bookmark** notes, folders, headings, blocks, searches, and graph states.
- **Bookmarks panel** to organize them (groups/folders), reorder, rename.
- Quick keyboard access to bookmarked items.

## 16. Workspace: tabs, panes, sidebars

- **Tabs:** multiple notes open as tabs in a pane; reorder, pin, close, close-others; recently closed
  reopen.
- **Splits:** split the workspace into multiple panes horizontally/vertically; each pane has its own
  tabs; drag a tab/note to create or move between splits.
- **Linked panes:** link two panes so one follows the other (e.g., editor + reading, or note +
  backlinks/outline).
- **Stacked tabs** option for a column of peeking tabs.
- **Sidebars:** left and right sidebars hold panels (explorer, search, tags, bookmarks, outline,
  backlinks, graph, etc.); panels are rearrangeable and collapsible; sidebars toggle/hide.
- **Pop-out windows:** tear a note/pane into its own window (macOS).
- **Workspace memory:** layout persists across launches; optional named/saved layouts.

> **Today:** tabs work — navigation reuses the current tab (⌘-click / ⌘↵ for a new one), open,
> close (⌘W), drag-reorder, close-others/all, reopen closed (⇧⌘T), cycle (⌃⇥ / ⌃⇧⇥), ⌘1–9 direct
> access — and are restored per vault on relaunch. There is one resizable, collapsible sidebar
> (⌃⌘S). **Not built:** pinned tabs, split panes, linked panes, stacked tabs, rearrangeable panels,
> pop-out windows, saved workspaces, scroll/cursor restoration.

## 17. Reading & preview behaviors

- **Reading mode** renders the note fully (see §4/§5).
- **Hover preview:** hovering (or a key-modifier hover) over an internal link shows a live preview
  popover of the target note/section.
- **Clickable everything:** links, tags, checkboxes, footnotes, embeds, headings (for permalinks).
- **Image behaviors:** click to zoom; respect width/alignment hints; lazy/comfortable loading.

> **Today:** Reading mode renders the note; links, tags, and checkboxes are clickable. Hover preview
> of a wikilink exists **only in the writing editor**, not in Reading mode. **Not built:** image zoom,
> width/alignment hints, footnote and heading-permalink behaviors.

## 18. Daily notes & templates — *not implemented*

- **Daily notes:** one-key "open/create today's note" using a configured folder and filename date
  format; navigation to previous/next day's note.
- **Templates:** insert a template into a note; templates support variables (date/time, title, cursor
  position, prompts); a configured templates folder.
- **New-note templates:** optionally apply a template automatically to new notes (globally or by
  folder).
- (Aspirational) periodic notes: weekly/monthly/yearly equivalents.

## 19. Attachments & media — *not implemented*

- **Attachment handling:** pasting/dragging an image or file into a note stores it in a configured
  attachments location and inserts the appropriate embed/link.
- **Configurable attachment folder** (vault root, a subfolder, or alongside the note).
- **Image embeds** render inline with optional sizing; **PDF/audio/video** embeds render with native
  controls.
- **Manage attachments:** find unused attachments; renaming/moving keeps embeds valid.

## 20. Appearance & theming

- **Light / dark / follow system.**
- **Accent color** selection.
- **Typography:** configurable editor font, monospace font, and font size; comfortable line height.
- **Readable line length** toggle (centered, capped measure) for long-form writing.
- **Theme support:** a way to change the overall look (themes/appearance presets), and ideally custom
  styling for advanced users.
- **Focus/typewriter/zen** writing modes (dim non-active lines, center the active line, hide chrome).
- Per-note appearance hints honored from properties (e.g., width, reading styles).

> **Today:** five themes (System, Light, Dark, Paper, Frosted), reading-font choice (System/Serif/
> Mono), body font size, and readable line width — all applied live. **Not built:** accent color,
> configurable editor/monospace fonts, custom themes or CSS snippets, focus/typewriter/zen modes,
> per-note appearance hints.

## 21. Command system & keyboard

- **Every action is a command** discoverable in the command palette.
- **Customizable hotkeys:** view, add, change, and reset keyboard shortcuts; detect conflicts.
- **Native menu bar** (macOS) mirrors key commands; standard system shortcuts behave as expected.
- Common defaults align with platform conventions and, where sensible, with Obsidian's muscle memory.

> **Today:** a native menu bar, a ⌘/ shortcut cheat sheet, and a fuzzy command palette covering the
> app's actions (vault switching, themes, tabs, navigation, search). **Not built:**
> customizable/rebindable hotkeys.

## 22. Settings / preferences

Organized, searchable preferences covering at least:

- **Editor:** default mode, typing aids, spellcheck, line length, auto-pairing, list behavior.
- **Files & links:** default new-note location, attachment location, link format (wikilink vs
  Markdown), whether to update links on rename, default extension.
- **Appearance:** theme, accent, fonts, sizes.
- **Hotkeys:** as above.
- **Daily notes / templates:** folders and formats.
- **About / data:** vault location, storage info, no-account confirmation.

> **Today:** Settings (⌘,) covers **Appearance only** — theme, reading font, font size, line width.
> None of the other settings groups listed above exist.

## 23. Sync & multi-device

- **Folder-based sync:** because the vault is just files, it syncs through whatever the folder uses
  (iCloud Drive, git, Dropbox, etc.). Folio adds no proprietary sync requirement.
- **macOS** can open a vault anywhere on disk. **iOS** works with **cloud-synced vaults** —
  practically iCloud Drive — opened via the system document picker and remembered with a
  security-scoped bookmark; iOS does not browse the local filesystem.
- **Cross-device consistency:** the same vault opened on macOS and iOS shows the same notes, links,
  tags, and structure.
- **Conflict behavior:** concurrent edits should never silently lose data; conflicting versions
  should be preserved and surfaced for the user to resolve.
- **External edits mid-session** should be detected and reconciled without clobbering unsaved local
  edits — including edits made by the other Folio app over iCloud.

> **Today:** the iOS security-scoped bookmark works, and macOS reloads an open note when it changes
> on disk (unless a local save is pending). **There is no conflict-resolution system of any kind** —
> no version preservation, no conflict UI, no file coordination (`NSFilePresenter`/`NSMetadataQuery`).
> A local save can still overwrite an external change that landed during the debounce window. Do not
> rely on Folio to arbitrate simultaneous edits from two devices.

## 24. Platform behaviors

Folio ships as **two apps that launch together**: a full macOS editor and an iOS companion. Data and
behavior are consistent across both; only interaction style and editing depth differ.

- **macOS (full editor):** menu bar, full keyboard control, multiple/pop-out windows, drag-and-drop
  with Finder, vaults anywhere on disk, window/state restoration.
- **iOS / iPadOS (reader-first, optional write):** the primary surface is the **rendered Reading
  view** — browse the vault, follow `[[links]]`, search by name, see backlinks/outline — over a
  **cloud-synced (iCloud Drive) vault** chosen through the document picker. Editing is optional:
  tap-to-edit with a touch editor + on-screen formatting toolbar, lossless writes back to the synced
  file. Touch-first interactions, swipe actions, share-sheet "send to Folio," hardware-keyboard
  shortcuts on iPad, split view / Stage Manager friendliness; `NavigationSplitView` collapses to a
  drill-down stack on iPhone.

## 25. Performance & reliability

- **Responsiveness:** opening notes, typing, search, and switching should be instant on large vaults
  (thousands of notes) and large notes; no perceptible lag while typing.
- **Crash safety:** in-progress edits should not be lost to a crash; autosave should be continuous
  and invisible.
- **Integrity:** no operation should corrupt a file; writes are atomic; partial writes can't leave a
  note truncated.
- **Graceful degradation:** unknown/large/binary content is handled without freezing or breaking.

> **Today:** writes go through `write(to:atomically:)`, so a note is never left half-written.
> But autosave is **debounced by 500 ms**, so the last half-second of typing can be lost to a crash
> — "never lost" is a goal, not a current property. There are no benchmarks behind the performance
> targets, no test suite, and filesystem errors are largely swallowed rather than surfaced. Treat
> the numbers above as targets and keep backups.

## 26. Import & export — *not implemented*

- **Export** a note (or selection) to PDF, HTML, and clean Markdown; print.
- **Copy as** Markdown/HTML/plain text.
- **Import:** open existing Markdown vaults (notably Obsidian vaults) with zero conversion; reasonable
  import from other note formats where feasible.

## 27. Accessibility

- Full **VoiceOver** support with meaningful labels and navigation order.
- **Dynamic Type** / adjustable text size; respects system contrast and reduce-motion settings.
- **Keyboard-only** operation for everything; visible focus.
- Sufficient color contrast in all themes; never color as the only signal.

> **Today:** icon-only controls carry accessibility labels, and most of the app is keyboard-driven.
> No VoiceOver audit, Dynamic Type verification, reduce-motion handling, or contrast audit has been
> done. This section is entirely aspirational.

## 28. Privacy & data ownership

- **No account, no telemetry, no tracking.** Folio does not transmit anything about the user's notes.
- **Total data ownership:** notes are the user's files in the user's folder; uninstalling Folio leaves
  every note intact and usable elsewhere.
- Any future optional online feature is strictly opt-in and clearly disclosed.

> **Today:** true — there is no telemetry, no analytics, and no account, and Folio makes no network
> requests of its own. **One caveat:** Reading mode renders remote images (`![](https://…)`) with
> `AsyncImage`, so a note containing a remote image URL causes a request to that host, disclosing
> your IP and the requested URL. Notes you author yourself won't do this unless you put a remote
> image in them, but it is not currently opt-in.

## 29. Extensibility — *not implemented*

- **Custom styling/snippets** for advanced visual tweaks.
- **A plugin/automation surface** so power users can extend behavior, with clear sandboxing and the
  same privacy guarantees.
- This section is a direction, not a commitment; it must never compromise §1.

## 30. Non-goals

To keep Folio focused, it explicitly does **not** aim to:

- Store notes in a proprietary or binary format, or require import/export to interoperate.
- Require an account, subscription, or cloud service to function.
- Be a true rich-text/word-processor with formatting that can't round-trip to Markdown.
- Reformat, "clean up," or reorganize the user's files without an explicit, opted-in action.
- Collect analytics or send note content anywhere.
