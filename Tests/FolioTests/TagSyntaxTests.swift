import Foundation
import Testing
@testable import Folio

/// What a `#tag` is, pinned down.
///
/// The rejected strings are not invented — they are lifted verbatim from notes
/// where the old rule got it wrong, in a vault where it produced 78 junk tags
/// out of 147. They are the regression, in the words it actually appeared in.
@Suite("Tag syntax")
struct TagSyntaxTests {

    // MARK: - Not tags

    @Test("Bare numbers are not tags", arguments: [
        "#1", "#2", "#218", "#106", "#571",
    ])
    func bareNumbersRejected(_ text: String) {
        #expect(TagSyntax.tags(in: text).isEmpty)
    }

    @Test("Numbered prose is not a tag", arguments: [
        "then ship post #1. Design is intentional",
        "**Example #3:** Shipments to filter",
        "Talking to speaker #1 made speaker #2 easy.",
        "Closes quick win #4, the last one",
        "'Entered at #18, peaked at #4 over 6h'",
    ])
    func numberedProseRejected(_ text: String) {
        #expect(TagSyntax.tags(in: text).isEmpty)
    }

    /// The case that "at least one non-digit" (Obsidian's rule) gets wrong: the
    /// separator joining two references is itself a non-digit, so `#1-#10` came
    /// back as the tag `1-`.
    @Test("Reference runs are not tags", arguments: [
        "Build-checklist conformance (Phase 3 #1-#10)",
        "Survivors #1/#3/#10 in the table",
        "forbid JSON null #116/#121, merge alembic heads",
        "the #1303/#1305/#1332 carry-forward",
        "stravalib issues #142/#217; r/Strava",
        "Related prior retros: food52 retro #20260427-014521",
    ])
    func referenceRunsRejected(_ text: String) {
        #expect(TagSyntax.tags(in: text).isEmpty)
    }

    @Test("A `#` mid-word is not a tag", arguments: [
        "word#nope", "example.com#fragment", "https://host/p#anchor",
    ])
    func midWordRejected(_ text: String) {
        #expect(TagSyntax.tags(in: text).isEmpty)
    }

    // MARK: - Tags

    @Test("Ordinary tags are found", arguments: [
        ("#printing-press", "printing-press"),
        ("#google", "google"),
        ("#nosec", "nosec"),
        ("#PiDay", "PiDay"),
        ("#_draft", "_draft"),
    ])
    func ordinaryTags(_ text: String, _ expected: String) {
        #expect(TagSyntax.tags(in: text) == [expected])
    }

    /// Digits are fine in a tag — they just cannot be the whole of it.
    @Test("Tags may contain digits", arguments: [
        ("#1a", "1a"),
        ("#v2", "v2"),
        ("#2026-review", "2026-review"),
        ("#112-style", "112-style"),
    ])
    func digitsAllowed(_ text: String, _ expected: String) {
        #expect(TagSyntax.tags(in: text) == [expected])
    }

    @Test("Nested tags keep their slashes", arguments: [
        ("#log/2026", "log/2026"),
        ("#a/b/c", "a/b/c"),
        ("#project/folio/ui", "project/folio/ui"),
    ])
    func nestedTags(_ text: String, _ expected: String) {
        #expect(TagSyntax.tags(in: text) == [expected])
    }

    /// A tag ends at the last letter/digit — punctuation that merely follows it
    /// in a sentence is not part of the name.
    @Test("Trailing punctuation is trimmed, not absorbed", arguments: [
        ("#done.", "done"), ("#done,", "done"), ("#done!", "done"),
        ("#tag- rest", "tag"), ("#tag/ rest", "tag"),
        ("#inbox\n", "inbox"),
    ])
    func trailingPunctuationTrimmed(_ text: String, _ expected: String) {
        #expect(TagSyntax.tags(in: text) == [expected])
    }

    // MARK: - Mixed text

    @Test("Real tags survive alongside numbered prose")
    func mixedText() {
        let note = """
        Shipped post #1 today, closing quick win #4.
        Filed under #writing and #project/folio — see #1303/#1305 for context.
        """
        #expect(TagSyntax.tags(in: note) == ["writing", "project/folio"])
    }

    @Test("Tags are deduplicated per note")
    func deduplicated() {
        #expect(TagSyntax.tags(in: "#alpha and #alpha again\n#alpha") == ["alpha"])
    }

    @Test("A note with no tags yields none")
    func emptyNote() {
        #expect(TagSyntax.tags(in: "Just prose, no hashes at all.").isEmpty)
        #expect(TagSyntax.tags(in: "").isEmpty)
    }

    /// `# Heading` is a heading; the space means there is no tag there.
    @Test("Markdown headings are not tags")
    func headingsAreNotTags() {
        #expect(TagSyntax.tags(in: "# Title\n## Section\n### Deeper").isEmpty)
    }

    // MARK: - Unicode

    /// An ASCII-only rule truncated real tags mid-word: `#café` indexed as
    /// `caf`, `#日本語` not at all. A vault is not obliged to be in English.
    @Test("Non-ASCII tags survive whole", arguments: [
        ("#café", "café"),
        ("#日本語", "日本語"),
        ("#naïve", "naïve"),
        ("#Über", "Über"),
        ("#Ελλάδα", "Ελλάδα"),
        ("#русский", "русский"),
        ("#2026-año", "2026-año"),
    ])
    func unicodeTags(_ text: String, _ expected: String) {
        #expect(TagSyntax.tags(in: text) == [expected])
    }

    /// A decomposed `é` is `e` + U+0301. Without `\p{M}` the tag stopped before
    /// its own accent, so the same word indexed differently depending on how the
    /// editor happened to normalise it.
    @Test("Combining marks stay attached")
    func combiningMarks() {
        let decomposed = "e\u{0301}"                      // é, as two scalars
        #expect(TagSyntax.tags(in: "#\(decomposed)") == [decomposed])
        #expect(TagSyntax.isValid(decomposed))
    }

    /// A Unicode digit is a digit: it can be *in* a tag but cannot be the whole
    /// of it, exactly like `1`.
    @Test("Unicode digits follow the same rule as ASCII digits")
    func unicodeDigits() {
        #expect(TagSyntax.tags(in: "#\u{0661}a") == ["\u{0661}a"])   // Arabic-Indic 1 + letter
        #expect(TagSyntax.tags(in: "#\u{0661}").isEmpty)              // digit alone
    }

    /// `café` written precomposed and decomposed are the same tag, and must not
    /// become two picker entries. Nothing in the regex arranges that — Swift's
    /// `String` equality is canonical, so `Set` and the `tagsIndex` dictionary
    /// unify them for free. Pinned because the rule depends on it and it is not
    /// visible in the pattern.
    @Test("Precomposed and decomposed spellings are one tag")
    func normalisationUnifies() {
        let precomposed = "caf\u{00E9}"        // café
        let decomposed  = "cafe\u{0301}"       // cafe + combining acute
        #expect(precomposed == decomposed)     // canonical equivalence
        #expect(TagSyntax.tags(in: "#\(precomposed) and #\(decomposed)").count == 1)
    }

    @Test("Emoji ends a tag rather than joining it")
    func emojiTerminates() {
        #expect(TagSyntax.tags(in: "#emoji🎉") == ["emoji"])
        #expect(!TagSyntax.isValid("emoji🎉"))
    }

    /// A mark belongs to the character before it, not to the tag syntax at
    /// large. Loose marks let invisible scalars and mark-based emoji into the
    /// picker: `#a\u{FE0F}` looks exactly like `#a` but is a different key, and
    /// `#a1\u{FE0F}\u{20E3}` renders as "a1️⃣".
    @Test("Variation selectors and enclosing marks do not join a tag")
    func loneMarksExcluded() {
        #expect(TagSyntax.tags(in: "#a\u{FE0F}") == ["a"])              // VS16 dropped
        #expect(TagSyntax.tags(in: "#a1\u{FE0F}\u{20E3}") == ["a1"])    // keycap dropped
        #expect(!TagSyntax.isValid("a\u{FE0F}"))
    }

    @Test("A mark cannot attach to a separator", arguments: ["#a/\u{0301}", "#a-\u{0301}"])
    func markAfterSeparatorExcluded(_ text: String) {
        #expect(TagSyntax.tags(in: text) == ["a"])
    }

    /// Scripts whose vowels are spacing marks (`Mc`) must still index whole —
    /// the exclusion is aimed at variation selectors, not at Indic text.
    @Test("Spacing marks stay part of the tag")
    func spacingMarksKept() {
        let devanagari = "\u{0915}\u{093E}\u{0924}"     // का + त
        #expect(TagSyntax.tags(in: "#\(devanagari)") == [devanagari])
        #expect(TagSyntax.isValid(devanagari))
    }

    // MARK: - The two paths must agree

    /// `isValid` (frontmatter) and the regex (inline) are one rule reached two
    /// ways. When they were separate implementations they disagreed on every
    /// non-ASCII tag, and `#café` in the body became a *different* picker entry
    /// from `tags: [café]` in the header. These are the invariants that bind
    /// them; an earlier version of this suite asserted neither.
    @Test("Anything isValid accepts, the regex extracts exactly", arguments: [
        "printing-press", "google", "log/2026", "1a", "v2", "2026-review",
        "_draft", "café", "日本語", "Ελλάδα", "\u{0661}a", "a/b/c",
    ])
    func validTagsRoundTrip(_ tag: String) {
        #expect(TagSyntax.isValid(tag))
        #expect(TagSyntax.tags(in: "#\(tag)") == [tag])
    }

    /// The converse, and the reason it is not simply "isValid == extracted":
    /// `#trail-` yields the tag `trail`, so extraction is non-empty while
    /// `trail-` itself is not a tag. What must hold is that whatever comes out
    /// of the regex is itself valid.
    @Test("Anything the regex extracts is itself isValid", arguments: [
        "#trail- rest", "#emoji🎉", "#has space", "ship post #1 and #real",
        "#café here", "#1-#10 then #actual", "#a/b/c.",
    ])
    func extractedTagsAreValid(_ text: String) {
        for tag in TagSyntax.tags(in: text) {
            #expect(TagSyntax.isValid(tag), "regex produced \(tag), which isValid rejects")
        }
    }

    @Test("isValid rejects non-tags", arguments: [
        "1", "218", "1/2", "20260427-014521", "", "1-", "142/", "-lead", "/lead",
        "trail-", "trail/", "has space", "emoji🎉", "#hash", "a b",
    ])
    func isValidRejectsNonTags(_ tag: String) {
        #expect(!TagSyntax.isValid(tag))
    }

    /// The highlighter colours `m.range` (the `#` included) while the index
    /// takes group 1. If those ever diverged the editor would underline the
    /// wrong span.
    @Test("Whole match is `#` plus the capture", arguments: ["#tag", "#café", "#log/2026", "#tag- rest"])
    func rangeInvariant(_ text: String) {
        let ns = text as NSString
        let m = TagSyntax.regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        let match = try! #require(m)
        #expect(ns.substring(with: match.range) == "#" + ns.substring(with: match.range(at: 1)))
    }
}

/// The frontmatter path into the index. Not a YAML parser — these pin the three
/// shapes it claims to read, and the fact that the tag rule is applied here too.
@Suite("Frontmatter tags")
struct FrontmatterTests {

    private func note(_ header: String) -> String { "---\n\(header)\n---\n\nBody text.\n" }

    @Test("Scalar form")
    func scalar() {
        #expect(Frontmatter.tags(in: note("tags: solo")) == ["solo"])
    }

    @Test("Flow list form")
    func flowList() {
        #expect(Frontmatter.tags(in: note("tags: [alpha, beta, gamma]")) == ["alpha", "beta", "gamma"])
    }

    @Test("Block list form")
    func blockList() {
        #expect(Frontmatter.tags(in: note("tags:\n  - alpha\n  - beta")) == ["alpha", "beta"])
    }

    /// The filter has to be reached on this path: nothing else stops a note from
    /// declaring a bare number and putting it in the picker.
    @Test("Numbers declared as tags are still rejected")
    func numericRejected() {
        #expect(Frontmatter.rawTags(in: note("tags: [218, real, 1]")) == ["218", "real", "1"])
        #expect(Frontmatter.tags(in: note("tags: [218, real, 1]")) == ["real"])
    }

    @Test("Unicode tags survive the frontmatter path too")
    func unicodePreserved() {
        #expect(Frontmatter.tags(in: note("tags: [café, 日本語]")) == ["café", "日本語"])
    }

    @Test("A block list ends at the next key")
    func blockListEndsAtNextKey() {
        #expect(Frontmatter.tags(in: note("tags:\n  - alpha\ntitle: Something")) == ["alpha"])
    }

    @Test("No frontmatter, no tags", arguments: [
        "Just a body.\n",
        "\n---\ntags: [a]\n---\n",          // fence not on line 1
        "---\ntitle: No tags here\n---\n",
    ])
    func noTags(_ text: String) {
        #expect(Frontmatter.tags(in: text).isEmpty)
    }
}
