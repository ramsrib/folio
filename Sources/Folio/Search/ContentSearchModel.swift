import Foundation

/// Backs the ⇧⌘F vault-wide content search. Case-insensitive literal search (v1 —
/// no regex yet). Scans every note off the main actor on a debounced query change,
/// caches file text keyed by modification date (only re-reading changed files, the
/// same trick as `VaultStore.linkCache`), and applies results back on the main
/// actor guarded by a generation counter so a slow scan can't overwrite a newer one.
@MainActor
final class ContentSearchModel: ObservableObject {
    /// One matched line: the trimmed line text, the match range within it (for
    /// bolding), and the match's 0-based occurrence index within the whole file —
    /// which the jump-to-hit plumbing uses to land the find bar on this exact hit.
    struct Snippet: Identifiable, Sendable {
        let id = UUID()
        let line: String
        let range: Range<String.Index>
        let occurrence: Int
    }
    struct FileResult: Identifiable, Sendable {
        let file: MarkdownFile
        let matchCount: Int
        let snippets: [Snippet]
        var id: URL { file.id }
    }

    @Published private(set) var results: [FileResult] = []
    @Published private(set) var totalMatches = 0
    @Published private(set) var totalFiles = 0      // files with at least one match
    @Published private(set) var capped = false      // more files matched than we show
    @Published private(set) var isSearching = false

    // nonisolated so the off-main `scan` can read them without an actor hop.
    nonisolated static let fileCap = 30     // files shown (results ranked by match count)
    nonisolated static let snippetCap = 4   // snippets shown per file

    private var cache: [URL: (mtime: Date, text: String)] = [:]
    private var generation = 0
    private var debounce: Task<Void, Never>?

    /// Drop cached text (e.g. if the vault is reloaded). mtime-keying already makes
    /// this optional — changed files re-read themselves — but it's here for callers
    /// that want a hard reset.
    func invalidateCache() { cache = [:] }

    /// Stop any pending or in-flight scan (the palette calls this on dismiss so a
    /// full-vault read doesn't keep running behind a closed window).
    func cancel() {
        debounce?.cancel()
        generation &+= 1
        isSearching = false
    }

    func search(_ query: String, files: [MarkdownFile]) {
        debounce?.cancel()
        guard !query.isEmpty else {
            generation &+= 1               // cancel any in-flight apply
            results = []; totalMatches = 0; totalFiles = 0; capped = false; isSearching = false
            return
        }
        isSearching = true
        generation &+= 1
        let gen = generation
        let snapshot = cache               // value snapshot handed to the background pass
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            // `scan` is nonisolated async, so this hop runs the file reads + matching
            // off the main actor; control returns here on the main actor.
            let outcome = await Self.scan(query: query, files: files, cache: snapshot)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.cache = outcome.cache
            self.results = outcome.results
            self.totalMatches = outcome.totalMatches
            self.totalFiles = outcome.totalFiles
            self.capped = outcome.capped
            self.isSearching = false
        }
    }

    // MARK: - Off-main scan (pure over its inputs)

    private struct Outcome: Sendable {
        let results: [FileResult]
        let cache: [URL: (mtime: Date, text: String)]
        let totalMatches: Int
        let totalFiles: Int
        let capped: Bool
    }

    private nonisolated static func scan(
        query: String, files: [MarkdownFile], cache: [URL: (mtime: Date, text: String)]
    ) async -> Outcome {
        var cache = cache
        var matched: [FileResult] = []
        var totalMatches = 0
        var totalFiles = 0

        for f in files {
            // A newer keystroke (or palette dismiss) cancels this task; bail out
            // between files so a superseded full-vault scan stops promptly instead
            // of reading to the end (its results would be discarded anyway).
            if Task.isCancelled { break }
            let mtime = (try? f.url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let text: String
            if let c = cache[f.url], c.mtime == mtime {
                text = c.text
            } else {
                text = (try? String(contentsOf: f.url, encoding: .utf8)) ?? ""
                cache[f.url] = (mtime, text)
            }
            let (count, snippets) = matches(in: text, query: query, cap: snippetCap)
            guard count > 0 else { continue }
            totalMatches += count
            totalFiles += 1
            matched.append(FileResult(file: f, matchCount: count, snippets: snippets))
        }

        // Prune cache entries for files no longer in the vault.
        let present = Set(files.map(\.url))
        cache = cache.filter { present.contains($0.key) }

        matched.sort {
            $0.matchCount != $1.matchCount ? $0.matchCount > $1.matchCount
                : $0.file.name.localizedStandardCompare($1.file.name) == .orderedAscending
        }
        let capped = matched.count > fileCap
        return Outcome(results: Array(matched.prefix(fileCap)), cache: cache,
                       totalMatches: totalMatches, totalFiles: totalFiles, capped: capped)
    }

    /// All case-insensitive occurrences of `query` in `text`: total count, plus up
    /// to `cap` snippets (the matched line trimmed, with the match's range within
    /// that trimmed line and its occurrence index in the file).
    private nonisolated static func matches(in text: String, query: String, cap: Int) -> (Int, [Snippet]) {
        var count = 0
        var snippets: [Snippet] = []
        var from = text.startIndex
        while let r = text.range(of: query, options: .caseInsensitive, range: from..<text.endIndex) {
            let occurrence = count
            count += 1
            if snippets.count < cap, let s = snippet(for: r, in: text, occurrence: occurrence) {
                snippets.append(s)
            }
            from = r.upperBound
            if from == text.endIndex { break }
        }
        return (count, snippets)
    }

    private nonisolated static func snippet(
        for match: Range<String.Index>, in text: String, occurrence: Int
    ) -> Snippet? {
        let lineRange = text.lineRange(for: match)
        let rawLine = String(text[lineRange])
        // Offsets of the match within the raw line, then re-based onto the trimmed
        // line (leading whitespace dropped) so the bold range still lines up.
        let startOffset = text.distance(from: lineRange.lowerBound, to: match.lowerBound)
        let matchLen = text.distance(from: match.lowerBound, to: match.upperBound)
        let leading = rawLine.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let adjusted = max(0, startOffset - leading)
        guard let lo = trimmed.index(trimmed.startIndex, offsetBy: adjusted, limitedBy: trimmed.endIndex) else {
            return nil
        }
        let hi = trimmed.index(lo, offsetBy: matchLen, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
        return Snippet(line: trimmed, range: lo..<hi, occurrence: occurrence)
    }
}
