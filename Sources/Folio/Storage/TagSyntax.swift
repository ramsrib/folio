import Foundation

/// What counts as a `#tag`, in one place.
///
/// The index (`VaultStore`) and the editor highlighter both need this rule, and
/// they used to carry their own copy of the regex. They drifted: the highlighter
/// accepted a leading `-` or `/` that the index rejected, so the editor could
/// colour a token the tag list refused to file. One definition, two callers.
///
/// **A tag must contain a letter or underscore, and cannot end on a separator.**
/// Numbered prose is not a tag. "ship post #1", "issue #218", and reference runs
/// like "#1-#10" or "#1303/#1305/#1332" are pointers at something else, and
/// indexing them buried the real tags under a wall of numbers — 78 of 147
/// entries in one real vault.
///
/// "At least one non-digit" — Obsidian's rule — is too weak to catch those: in
/// `#1-#10` the `-` is a non-digit, so the reference run qualifies and comes
/// back as the tag `1-`. Requiring a *letter* is what actually separates a tag
/// from a number, and trimming trailing separators stops `#1/` from swallowing
/// the slash that only ever joined it to the next reference.
///
/// Kept: `#1a`, `#v2`, `#2026-review`, `#_draft`, `#café`, `#日本語`, `#log/2026`.
/// Rejected: `#1`, `#218`, `#1/2`, `#20260427-014521`.
enum TagSyntax {
    /// Capture group 1 is the tag without its `#`; the whole match is `#` plus
    /// that capture, which is what the highlighter colours.
    ///
    /// `(?<!\S)` keeps the `#` at a word boundary, so `example.com#frag` and
    /// `word#1` are left alone. The lookahead demands a letter or underscore
    /// somewhere in the run; the body then stops before any trailing `-` or `/`.
    ///
    /// The classes are Unicode (`\p{L}`, `\p{N}`), not `[A-Za-z0-9]`: a vault
    /// written in Spanish or Japanese has real tags, and an ASCII rule truncated
    /// them mid-word — `#café` indexed as `caf`, `#日本語` not at all.
    ///
    /// Marks are admitted only as part of the character they belong to (`mark`
    /// applies to a preceding base), not as free-standing syntax. A *decomposed*
    /// `é` (`e` + U+0301) has to survive, and Devanagari needs its spacing
    /// marks — but a mark loose in the class let `#a\u{FE0F}` (a plus an
    /// invisible variation selector) become a picker entry indistinguishable
    /// from `#a`, let `#a1\u{FE0F}\u{20E3}` ("a1️⃣") swallow a keycap emoji, and
    /// let an accent attach to a `/` or `-` it was never part of.
    private static let mark = "[\\p{Mn}\\p{Mc}--[\\x{FE00}-\\x{FE0F}\\x{E0100}-\\x{E01EF}]]"
    private static let atom = "[\\p{L}\\p{N}_]" + mark + "*"

    static let pattern =
        "(?<!\\S)#(?=[\\p{L}\\p{N}\\p{M}_/-]*[\\p{L}_])"
        + "(" + atom + "(?:(?:" + atom + "|[/-])*" + atom + ")?)"

    static let regex = try! NSRegularExpression(pattern: pattern)

    /// Every distinct inline tag in `text`, without the leading `#`.
    static func tags(in text: String) -> Set<String> {
        let ns = text as NSString
        var found = Set<String>()
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            found.insert(ns.substring(with: m.range(at: 1)))
        }
        return found
    }

    /// Whether a tag written *without* a `#` is a real tag — frontmatter's
    /// `tags:` list reaches the index by its own path and never meets the regex,
    /// so the same rule has to be reachable on its own.
    ///
    /// Deliberately answered *by* the regex rather than by re-deriving the rule
    /// in Swift. The re-derived version used `Character.isLetter`, which is
    /// Unicode-aware, against an ASCII pattern — so `café` was a valid tag in
    /// frontmatter and `caf` inline, and one tag became two picker entries. Two
    /// implementations of one rule will drift; this way there is only one.
    ///
    /// Requiring the match to span the *whole* probe is the point: `trail-`
    /// yields a match (`trail`) but is not itself a tag.
    static func isValid(_ tag: String) -> Bool {
        let probe = "#" + tag
        let full = NSRange(location: 0, length: (probe as NSString).length)
        guard let m = regex.firstMatch(in: probe, range: full) else { return false }
        return m.range == full
    }
}
