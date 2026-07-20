import SwiftUI
import AppKit

/// Per-note scroll memory for Reading mode (VS Code / Obsidian behavior): the
/// scroll view is one reused instance, so without intervention the next note
/// inherits the previous note's offset — and a bare reset-to-top forgets where
/// you were when you come back. This records each note's offset continuously
/// (clip-view bounds notifications) and restores it when the note returns;
/// never-visited notes start at the top.
///
/// Installed inside the reading ScrollView's content (the KeyboardScroller
/// pattern) so `enclosingScrollView` resolves to the real NSScrollView backing
/// SwiftUI's ScrollView.
struct ScrollMemory: NSViewRepresentable {
    /// The note currently displayed. A change triggers save-suppression + restore.
    var noteID: URL?
    /// When true at restore time, something else owns the scroll position for
    /// this switch (a find jump, an outline/heading scroll) — skip the restore.
    var positionOwnedElsewhere: () -> Bool

    /// Session-scoped offsets. Static so the memory survives the view being
    /// remounted (mode toggles), keyed by note URL.
    @MainActor private static var offsets: [URL: CGPoint] = [:]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.positionOwnedElsewhere = positionOwnedElsewhere
        DispatchQueue.main.async {
            coordinator.attach(to: view.enclosingScrollView)
            coordinator.noteChanged(to: noteID)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.positionOwnedElsewhere = positionOwnedElsewhere
        if coordinator.scrollView == nil {
            DispatchQueue.main.async { coordinator.attach(to: nsView.enclosingScrollView) }
        }
        if coordinator.currentKey != noteID {
            coordinator.noteChanged(to: noteID)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        weak var scrollView: NSScrollView?
        var currentKey: URL?
        var positionOwnedElsewhere: () -> Bool = { false }
        /// Suppress recording while a switch is in flight: the content swap and
        /// the restore itself both move the clip view, and recording those would
        /// overwrite the note's real remembered offset.
        private var suppressSaves = false
        private var observer: NSObjectProtocol?

        func attach(to scroll: NSScrollView?) {
            guard let scroll, scrollView !== scroll else { return }
            detach()
            scrollView = scroll
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordOffset() }
            }
        }

        private func recordOffset() {
            guard !suppressSaves, let key = currentKey, let scroll = scrollView else { return }
            ScrollMemory.offsets[key] = scroll.contentView.bounds.origin
        }

        func noteChanged(to url: URL?) {
            suppressSaves = true
            currentKey = url
            // Restore on the next runloop turn (after SwiftUI swapped and laid out
            // the new content), then once more a beat later to correct clamping if
            // the lazy stack's estimated height settled — both writes idempotent.
            DispatchQueue.main.async { [weak self] in
                self?.restore()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.restore()
                    self?.suppressSaves = false
                }
            }
        }

        private func restore() {
            guard let scroll = scrollView else { return }
            guard !positionOwnedElsewhere() else { return }   // find/outline jump wins
            let clip = scroll.contentView
            var target = currentKey.flatMap { ScrollMemory.offsets[$0] } ?? .zero
            let doc = scroll.documentView?.frame.size ?? .zero
            target.y = min(max(0, target.y), max(0, doc.height - clip.bounds.height))
            target.x = 0
            clip.scroll(to: target)
            scroll.reflectScrolledClipView(clip)
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            scrollView = nil
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
