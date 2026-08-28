import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Resolves a Markdown image reference against the note, then the vault root,
/// then the raw path — and memoizes the decode by mtime.
///
/// The memo matters because callers hit this from view bodies: an uncached decode
/// would touch the disk on every render of every image.
@MainActor
enum NoteImageLoader {
    private static var cache: [String: (mtime: Date, image: PlatformImage)] = [:]

    static func load(_ source: String, noteURL: URL?, vaultURL: URL?) -> PlatformImage? {
        guard let noteURL else { return nil }
        let candidates = [
            noteURL.deletingLastPathComponent().appendingPathComponent(source),
            vaultURL?.appendingPathComponent(source),
            URL(fileURLWithPath: source),
        ].compactMap { $0 }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if let hit = cache[url.path], hit.mtime == mtime { return hit.image }
            if let image = PlatformImage.load(contentsOf: url) {
                if cache.count > 64 { cache.removeAll(keepingCapacity: true) }
                cache[url.path] = (mtime, image)
                return image
            }
        }
        return nil
    }
}
