import Foundation
import SwiftUI

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
        /// Character *offsets* into the candidate of the matched characters (for
        /// highlighting). Offsets rather than `String.Index` so a candidate can be
        /// prepared once and matched many times — see `Prepared`.
        let matchedOffsets: [Int]
    }

    /// A candidate with its character arrays built once.
    ///
    /// This is the whole performance story for the quick switcher. Matching a
    /// plain `String` allocates two arrays and lowercases the candidate *per
    /// call*, which over a couple of thousand notes costs ~12ms a keystroke;
    /// preparing once and matching over the arrays costs ~0.4ms.
    struct Prepared {
        let chars: [Character]
        let lower: [Character]

        init(_ candidate: String) {
            chars = Array(candidate)
            lower = Array(candidate.lowercased())
        }

        /// Cheap rejection before scoring: are all query characters present, in
        /// order? Most candidates fail this, and it allocates nothing.
        func couldMatch(_ query: [Character]) -> Bool {
            if query.isEmpty { return true }
            var qi = 0
            for ch in lower where ch == query[qi] {
                qi += 1
                if qi == query.count { return true }
            }
            return false
        }
    }

    /// Normalize a query once, for reuse across many candidates. Whitespace is a
    /// word separator, not a required character.
    static func queryCharacters(_ query: String) -> [Character] {
        Array(query.lowercased().filter { !$0.isWhitespace })
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
        match(query: queryCharacters(query), in: Prepared(candidate))
    }

    /// The real matcher: a normalized query against a prepared candidate.
    static func match(query q: [Character], in candidate: Prepared) -> Result? {
        guard !q.isEmpty else { return Result(score: 0, matchedOffsets: []) }
        let chars = candidate.chars
        let lower = candidate.lower

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
        return Result(score: score, matchedOffsets: indices)
    }

    /// Render `string` with the matched characters emphasized. Shared by every
    /// palette so they highlight identically.
    @MainActor
    static func highlighted(_ string: String, _ match: Result?, tint: Color) -> AttributedString {
        guard let match, !match.matchedOffsets.isEmpty else { return AttributedString(string) }
        let hits = Set(match.matchedOffsets)
        var result = AttributedString()
        for (offset, character) in string.enumerated() {
            var piece = AttributedString(String(character))
            if hits.contains(offset) {
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = tint
            }
            result += piece
        }
        return result
    }

    /// A character is a "word start" if it follows a separator or is a lower→upper
    /// camelCase bump — the spots humans mentally anchor an abbreviation to.
    private static func isBoundary(prev: Character, cur: Character) -> Bool {
        if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." { return true }
        if prev.isLowercase && cur.isUppercase { return true }
        return false
    }
}
