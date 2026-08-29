import Testing
@testable import Folio

/// What a `#tag` is, pinned down.
///
/// These cases are not invented: every string in `referenceRuns` and most of
/// `prose` was pulled from a real vault where the old rule produced 177 junk
/// tags out of 220. They are the regression, verbatim.
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

    // MARK: - Frontmatter path

    /// Frontmatter reaches the index without meeting the regex, so the same
    /// rule has to hold on the string-validation path.
    @Test("isValid agrees with the regex on tags", arguments: [
        "printing-press", "google", "log/2026", "1a", "v2", "2026-review", "_draft",
    ])
    func isValidAcceptsRealTags(_ tag: String) {
        #expect(TagSyntax.isValid(tag))
        #expect(TagSyntax.tags(in: "#\(tag)") == [tag])   // and the two agree
    }

    @Test("isValid rejects what the regex rejects", arguments: [
        "1", "218", "1/2", "20260427-014521", "", "1-", "142/", "-lead", "/lead",
        "trail-", "trail/", "has space", "emoji🎉",
    ])
    func isValidRejectsNonTags(_ tag: String) {
        #expect(!TagSyntax.isValid(tag))
    }
}
