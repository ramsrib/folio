import Foundation

/// Case-insensitive fuzzy subsequence matcher used by the quick switcher, heading
/// jump, and command palette. Pure and side-effect-free so it's trivially testable.
///
/// The query must appear as an in-order subsequence of the candidate (every query
/// character found, left to right). Scoring rewards the matches that *feel* right:
/// a hit at the very start, hits at word boundaries (after a separator or a
/// camelCase bump), and consecutive runs; it lightly penalizes spread-out matches
/// so "ad" prefers "Architecture Decisions" over "a…d…" scattered across a name.
enum FuzzyMatch {
    struct Result: Equatable {
        let score: Int
        /// Indices into the *candidate* string of the matched characters (for
        /// highlighting). Valid only against the exact string passed to `match`.
        let matchedIndices: [String.Index]
    }

    // Bonus/penalty weights. Tuned so a start match dominates a boundary match,
    // which dominates a consecutive run, which dominates a plain in-order hit.
    private static let startBonus = 16
    private static let boundaryBonus = 8
    private static let consecutiveBonus = 5
    private static let baseBonus = 1
    private static let maxGapPenalty = 3

    /// Match `query` against `candidate`. Returns `nil` if not all query characters
    /// are present in order. An empty query matches everything with score 0.
    /// Whitespace in the query is ignored — it's a word separator, not a required
    /// character — so "migration strategy" matches "migration-strategy" and
    /// "MigrationStrategy" as well as "Migration Strategy".
    static func match(query: String, in candidate: String) -> Result? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return Result(score: 0, matchedIndices: []) }
        let chars = Array(candidate)
        let lower = Array(candidate.lowercased())

        var indices: [Int] = []
        var score = 0
        var qi = 0
        var prevMatch = -2           // candidate offset of the previously matched char

        // `lowercased()` can (rarely) change the grapheme count (e.g. "İ"); bound
        // the walk by both arrays so a mismatch can't index out of range.
        var i = 0
        while i < chars.count, i < lower.count, qi < q.count {
            if lower[i] == q[qi] {
                var bonus = baseBonus
                if i == 0 {
                    bonus += startBonus
                } else if isBoundary(prev: chars[i - 1], cur: chars[i]) {
                    bonus += boundaryBonus
                }
                if prevMatch == i - 1 {
                    bonus += consecutiveBonus
                } else if prevMatch >= 0 {
                    bonus -= min(i - prevMatch - 1, maxGapPenalty)   // gap penalty
                }
                score += bonus
                indices.append(i)
                prevMatch = i
                qi += 1
            }
            i += 1
        }
        guard qi == q.count else { return nil }

        // Map candidate offsets back to String.Index for the caller's highlighting.
        let mapped = indices.map { candidate.index(candidate.startIndex, offsetBy: $0) }
        return Result(score: score, matchedIndices: mapped)
    }

    /// A character is a "word start" if it follows a separator or is a lower→upper
    /// camelCase bump — the spots humans mentally anchor an abbreviation to.
    private static func isBoundary(prev: Character, cur: Character) -> Bool {
        if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." { return true }
        if prev.isLowercase && cur.isUppercase { return true }
        return false
    }
}
