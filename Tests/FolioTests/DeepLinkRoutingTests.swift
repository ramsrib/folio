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
@MainActor
@Suite("Deep link routing")
struct DeepLinkRoutingTests {

    @Test("A vault-less file link yields the file to route by")
    func fileOnlyLinkResolves() {
        let url = URL(string: "folio://open?file=/notes/vault/a.md")!
        #expect(VaultResolver.destination(for: url) == nil)
        #expect(VaultResolver.fileTarget(for: url)?.path == "/notes/vault/a.md")
    }

    @Test("Percent-encoded paths decode")
    func encodedPathDecodes() {
        let url = URL(string: "folio://open?file=%2Fnotes%2Fmy%20vault%2Fa%20b.md")!
        #expect(VaultResolver.fileTarget(for: url)?.path == "/notes/my vault/a b.md")
    }

    @Test("A vault-qualified link is not a file-only link")
    func vaultQualifiedIgnored() {
        let url = URL(string: "folio://open?vault=/notes/vault&file=a.md")!
        #expect(VaultResolver.fileTarget(for: url) == nil)
        #expect(VaultResolver.destination(for: url)?.file?.path == "/notes/vault/a.md")
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

    @Test("Non-folio schemes are refused")
    func otherSchemesRefused() {
        #expect(VaultResolver.fileTarget(for: URL(string: "file:///notes/a.md")!) == nil)
        #expect(VaultResolver.fileTarget(for: URL(string: "https://x/?file=/a.md")!) == nil)
    }
}
