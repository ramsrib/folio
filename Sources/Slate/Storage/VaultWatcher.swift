import Foundation

#if os(macOS)
import CoreServices

/// Watches a vault directory (recursively) and fires `onChange` when files are
/// added/removed/renamed/modified on disk — so edits from git, Obsidian, or any
/// other app show up live. `IgnoreSelf` skips events from our own writes.
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(path: String, onChange: @escaping () -> Void) {
        self.onChange = onChange

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf)

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

    private func fire() {
        MainActor.assumeIsolated { onChange() }   // dispatched on the main queue
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

/// iOS has no FSEvents; live external-change watching is a no-op for now. The
/// type stays available so `VaultStore` compiles unchanged (rely on manual
/// refresh / file coordination later).
final class VaultWatcher {
    init?(path: String, onChange: @escaping () -> Void) { nil }
    func stop() {}
}

#endif
