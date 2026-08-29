import Foundation

/// The little bit of YAML frontmatter Folio actually reads.
///
/// Not a YAML parser and not trying to be — it recognises the `tags:` key in
/// the three shapes people write by hand, and ignores everything else:
///
/// ```yaml
/// ---
/// tags: solo            # scalar
/// tags: [a, b]          # flow list
/// tags:                 # block list
///   - a
///   - b
/// ---
/// ```
///
/// Lifted out of `VaultStore` so it can be tested: it is pure text in, strings
/// out, with no vault, no file system, and no main-actor isolation.
enum Frontmatter {
    /// Raw `tags:` values, in document order, before any validation.
    ///
    /// Returns what the document *claims* are tags. Filtering them through
    /// `TagSyntax.isValid` is the caller's job, kept separate so the parser's
    /// behaviour and the tag rule can be tested apart from each other.
    static func rawTags(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return [] }
        var out: [String] = []
        var inTags = false
        var i = 1
        while i < lines.count, lines[i] != "---" {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            if inTags {
                if t.hasPrefix("-") { out.append(t.dropFirst().trimmingCharacters(in: .whitespaces)) }
                else if !(raw.first == " " || raw.first == "\t") { inTags = false }
            }
            if t.hasPrefix("tags:") {
                let val = t.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("[") {
                    out.append(contentsOf: val.dropFirst().dropLast()
                        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                } else if val.isEmpty { inTags = true }
                else { out.append(val) }
            }
            i += 1
        }
        return out
    }

    /// Frontmatter tags that are real tags.
    ///
    /// The same rule the inline regex applies — this path never meets the
    /// regex, so it has to reach the rule on its own. Without it a note could
    /// declare `tags: [218]` and put a bare number in the picker that no inline
    /// `#218` could ever produce.
    static func tags(in text: String) -> [String] {
        rawTags(in: text).filter(TagSyntax.isValid)
    }
}
