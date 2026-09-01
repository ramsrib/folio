#if os(macOS)
import SwiftUI
import AppKit
import os

/// Reading mode on macOS: parses the note into blocks and hands them to
/// `NoteTextView`, which lays the whole thing out as one selectable text stream.
///
/// The parse plumbing mirrors the block-per-view reader it replaced (same memo,
/// same freeze-while-hidden rule) — what changed is everything downstream of it.
struct NoteReader: View {
    @ObservedObject var find: FindModel
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings

    @State private var blocks: [Block] = []
    @State private var renderKey = ""

    /// Parsed-block memo across tab switches, keyed by content identity.
    @MainActor private static var parseCache: [String: [Block]] = [:]

    /// Constant while hidden behind the editor, so keystrokes never re-fire the
    /// parse; flips to the content's identity when reading returns.
    private var parseTaskID: String {
        guard ui.mode == .read else { return "" }
        return contentKey
    }

    private var contentKey: String {
        "\(vault.content.count)|\(vault.content.hashValue)|\(settings.lineBreaks.rawValue)"
    }

    var body: some View {
        NoteTextView(
            blocks: blocks,
            renderKey: renderKey,
            bodySize: settings.bodyFontSize,
            family: settings.readingFont,
            readableWidth: settings.columnWidth,
            background: settings.nsPaneBackground,
            selectionHighlight: settings.nsSelectionHighlight,
            textColor: settings.nsTextColor,
            secondaryTextColor: settings.nsSecondaryTextColor,
            findMatch: settings.findMatch,
            findCurrentMatch: settings.findCurrentMatch,
            noteID: vault.selection,
            isActive: ui.mode == .read,
            find: find,
            scrollRequest: ui.mode == .read ? vault.scrollRequest : nil,
            loadImage: { source in
                NoteImageLoader.load(source, noteURL: vault.selection, vaultURL: vault.vaultURL)
            },
            onToggleTask: { vault.toggleTask(atContentIndex: $0) },
            onOpenLink: openLink,
            onConsumedScrollRequest: { vault.scrollRequest = nil }
        )
        .task(id: parseTaskID) {
            guard ui.mode == .read else { return }
            let t0 = ContinuousClock.now
            let key = contentKey
            if let hit = Self.parseCache[key] {
                blocks = hit
            } else {
                let parsed = MarkdownParser.parse(vault.content,
                                                  lineBreaks: settings.lineBreaks)
                if Self.parseCache.count > 24 { Self.parseCache.removeAll(keepingCapacity: true) }
                Self.parseCache[key] = parsed
                blocks = parsed
            }
            renderKey = key
            let us = (ContinuousClock.now - t0).components.attoseconds / 1_000_000_000_000
            Logger(subsystem: "com.sriramb.folio", category: "perf")
                .debug("reading parse: \(us)µs (\(blocks.count) blocks)")
        }
    }

    /// Wikilinks, external URLs, and relative note links. ⌘-click opens in a new
    /// tab, matching the editor and the sidebar.
    private func openLink(_ url: URL) -> Bool {
        if url.scheme == "folio", url.host == "wikilink" {
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "target" })?.value ?? ""
            let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            vault.openWikilink(target, inNewTab: newTab)
            return true
        }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            return true
        }
        if url.scheme == nil || url.isFileURL {
            vault.openLocalLink(url.isFileURL ? url.path : url.absoluteString)
            return true
        }
        return false
    }
}
#endif
