import Foundation

/// One coalesced file-system change reported by the watcher: the affected path
/// and its raw FSEvents flags. `VaultStore` uses these to re-index just the
/// changed notes instead of rescanning the whole vault per event.
struct VaultEvent: Sendable {
    let path: String
    let flags: UInt32
}

#if os(macOS)
import CoreServices

extension VaultEvent {
    /// The event names a plain file (as opposed to a directory or symlink).
    var isFile: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 }
    /// The vault's *structure* may have changed in ways a per-file patch can't
    /// capture: directory events, coalescing overflow (MustScanSubDirs), the
    /// root moving, or volume (un)mounts.
    var isStructural: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemIsDir
            | kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount) != 0
    }
}

/// Watches a vault directory (recursively) and reports which files changed on
/// disk — so edits from git, Obsidian, or any other app show up live.
/// `IgnoreSelf` skips events from our own writes.
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([VaultEvent]) -> Void

    init?(path: String, onChange: @escaping ([VaultEvent]) -> Void) {
        self.onChange = onChange

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info, count > 0 else { return }
            // UseCFTypes → eventPaths is a CFArray of CFString.
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let flags = UnsafeBufferPointer(start: eventFlags, count: count)
            let events = (0..<min(paths.count, count)).map { VaultEvent(path: paths[$0], flags: flags[$0]) }
            Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().fire(events)
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagIgnoreSelf
            | kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, flags)
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func fire(_ events: [VaultEvent]) {
        MainActor.assumeIsolated { onChange(events) }   // dispatched on the main queue
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

#else

extension VaultEvent {
    // iOS has no FSEvents; the stub watcher never fires, so these are inert.
    var isFile: Bool { false }
    var isStructural: Bool { true }
}

/// iOS has no FSEvents; live external-change watching is a no-op for now. The
/// type stays available so `VaultStore` compiles unchanged (rely on manual
/// refresh / file coordination later).
final class VaultWatcher {
    init?(path: String, onChange: @escaping ([VaultEvent]) -> Void) { nil }
    func stop() {}
}

#endif
