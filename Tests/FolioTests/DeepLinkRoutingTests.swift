import Foundation
import Testing
@testable import Folio

/// How a `folio://` link is *placed* before any window sees it.
///
/// The regression these pin: the `folio <file>` shell shim emits
/// `folio://open?file=/abs/path` with no `vault=`. `destination` returns nil for
/// that (it needs a vault to name a window), and the router used to beep and drop
/// the link — so opening a note from the CLI silently did nothing, even with the
/// containing vault already open.
///
/// The rejections matter as much as the accept: the router acts on what comes
/// back, and acting on a link the store will only beep at can conjure a window
/// for a vault with nothing to show.
@MainActor
@Suite("Deep link routing")
struct DeepLinkRoutingTests {

    /// A real note on disk — `fileTarget` refuses to route what cannot be opened,
    /// so these cannot be imaginary paths.
    static func makeNote(_ name: String = "a.md") -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folio-links-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try! "# note".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    static func link(file: String, vault: String? = nil, host: String = "open") -> URL {
        var comps = URLComponents()
        comps.scheme = "folio"
        comps.host = host
        comps.queryItems = (vault.map { [URLQueryItem(name: "vault", value: $0)] } ?? [])
            + [URLQueryItem(name: "file", value: file)]
        return comps.url!
    }

    @Test("A vault-less file link yields the file to route by")
    func fileOnlyLinkResolves() {
        let note = Self.makeNote()
        let url = Self.link(file: note.path)
        #expect(VaultResolver.destination(for: url) == nil)   // no vault to name a window
        #expect(VaultResolver.fileTarget(for: url)?.path == note.path)
    }

    /// The shim percent-encodes with `urllib.parse.quote(safe="")`, so every note
    /// with a space or `#` in its name arrives encoded.
    @Test("Percent-encoded paths decode")
    func encodedPathDecodes() {
        let note = Self.makeNote("a b #1.md")
        let raw = "folio://open?file=" + note.path
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(VaultResolver.fileTarget(for: URL(string: raw)!)?.path == note.path)
    }

    @Test("A vault-qualified link is not a file-only link")
    func vaultQualifiedIgnored() {
        let note = Self.makeNote()
        let vault = note.deletingLastPathComponent()
        let url = Self.link(file: "a.md", vault: vault.path)
        #expect(VaultResolver.fileTarget(for: url) == nil)
        #expect(VaultResolver.destination(for: url)?.file?.path == note.path)
    }

    /// Folio's cwd is "/" under Launch Services, so a relative path would address
    /// the wrong file. The shim always sends an absolute one.
    @Test("Relative and empty paths are refused", arguments: [
        "folio://open?file=notes/a.md", "folio://open?file=", "folio://open",
        "folio://open?vault=&file=a.md",
    ])
    func nonAbsoluteRefused(_ raw: String) {
        #expect(VaultResolver.fileTarget(for: URL(string: raw)!) == nil)
    }

    /// `parseFolioLink` — which the store re-parses the routed URL with — requires
    /// host `open`. Routing a link it will reject would strand a window on a vault
    /// it never gets to show.
    @Test("A host the store will reject is not routed")
    func wrongHostRefused() {
        let note = Self.makeNote()
        #expect(VaultResolver.fileTarget(for: Self.link(file: note.path, host: "wrong")) == nil)
        #expect(VaultResolver.fileTarget(for: URL(string: "folio:/open?file=\(note.path)")!) == nil)
    }

    /// Same reason: `openExternalFile` opens only existing Markdown, so a `.txt`
    /// (which the shim happily passes) or a deleted note must not summon a window.
    @Test("Non-Markdown and missing files are not routed")
    func unopenableRefused() {
        let note = Self.makeNote()
        let text = note.deletingLastPathComponent().appendingPathComponent("readme.txt")
        try! "hi".write(to: text, atomically: true, encoding: .utf8)
        #expect(VaultResolver.fileTarget(for: Self.link(file: text.path)) == nil)
        let missing = note.deletingLastPathComponent().appendingPathComponent("gone.md")
        #expect(VaultResolver.fileTarget(for: Self.link(file: missing.path)) == nil)
    }

    @Test("Non-folio schemes are refused")
    func otherSchemesRefused() {
        let note = Self.makeNote()
        #expect(VaultResolver.fileTarget(for: note) == nil)                       // a file: URL
        #expect(VaultResolver.fileTarget(for: URL(string: "https://x/open?file=\(note.path)")!) == nil)
    }
}
