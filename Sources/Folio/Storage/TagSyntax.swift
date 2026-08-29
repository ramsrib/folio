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
/// indexing them buried the real tags under a wall of numbers — 177 of 220
/// entries in one real vault.
///
/// "At least one non-digit" — Obsidian's rule — is too weak to catch those: in
/// `#1-#10` the `-` is a non-digit, so the reference run qualifies and comes
/// back as the tag `1-`. Requiring a *letter* is what actually separates a tag
/// from a number, and trimming trailing separators stops `#1/` from swallowing
/// the slash that only ever joined it to the next reference.
///
/// Kept: `#1a`, `#v2`, `#2026-review`, `#_draft`, nested `#log/2026`.
/// Rejected: `#1`, `#218`, `#1/2`, `#20260427-014521`.
enum TagSyntax {
    /// Capture group 1 is the tag without its `#`.
    ///
    /// `(?<!\S)` keeps the `#` at a word boundary, so `example.com#frag` and
    /// `word#1` are left alone. The lookahead demands a letter or underscore
    /// somewhere in the run; the body then stops before any trailing `-` or `/`.
    static let pattern = "(?<!\\S)#(?=[A-Za-z0-9_/-]*[A-Za-z_])([A-Za-z0-9_](?:[A-Za-z0-9_/-]*[A-Za-z0-9_])?)"

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
    /// `tags:` list reaches the index by its own path and never meets the
    /// regex, so the same rule has to be reachable on its own.
    static func isValid(_ tag: String) -> Bool {
        guard let first = tag.first, let last = tag.last else { return false }
        guard first.isLetter || first.isNumber || first == "_" else { return false }
        guard last.isLetter || last.isNumber || last == "_" else { return false }
        guard tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "/" }) else { return false }
        return tag.contains { $0.isLetter || $0 == "_" }
    }
}
