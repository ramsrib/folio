import Foundation

/// Backs the ⇧⌘F vault-wide content search. Case-insensitive **word-AND** search:
/// space-separated terms must all appear in a file (anywhere — not adjacent);
/// wrap the query in quotes for an exact phrase. No regex yet.
/// Scans every note off the main actor on a debounced query change,
/// caches file text keyed by modification date (only re-reading changed files, the
/// same trick as `VaultStore.linkCache`), and applies results back on the main
/// actor guarded by a generation counter so a slow scan can't overwrite a newer one.
@MainActor
final class ContentSearchModel: ObservableObject {
    /// One matched line: the trimmed line text, the ranges of every term hit in
    /// it (for bolding), plus a jump target — the first-hit term and that term's
    /// 0-based occurrence index within the whole file, which the jump-to-hit
    /// plumbing feeds to the find bar to land on this exact hit.
    struct Snippet: Identifiable, Sendable {
        let id = UUID()
        let line: String
        let ranges: [Range<String.Index>]
        let jumpTerm: String
        let jumpOccurrence: Int
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

    /// Query → search terms. Space-separated words AND together; a query wrapped
    /// in straight or curly quotes is one exact phrase.
    nonisolated static func terms(from query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let quotes = CharacterSet(charactersIn: "\"\u{201C}\u{201D}")
        if q.count > 1,
           let first = q.unicodeScalars.first, let last = q.unicodeScalars.last,
           quotes.contains(first), quotes.contains(last) {
            let phrase = String(q.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            return phrase.isEmpty ? [] : [phrase]
        }
        return q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private nonisolated static func scan(
        query: String, files: [MarkdownFile], cache: [URL: (mtime: Date, text: String)]
    ) async -> Outcome {
        var cache = cache
        var matched: [FileResult] = []
        var totalMatches = 0
        var totalFiles = 0
        let terms = terms(from: query)

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
            let (count, snippets) = matches(in: text, terms: terms, cap: snippetCap)
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

    /// AND semantics over `terms`: nil result (count 0) unless *every* term occurs
    /// in the text. Count = total occurrences of all terms. Snippets are matching
    /// lines, preferring lines where several distinct terms co-occur; every term
    /// hit in a chosen line is recorded for bolding, and each snippet carries a
    /// (term, occurrence-in-file) jump target for the find bar.
    private nonisolated static func matches(in text: String, terms: [String], cap: Int) -> (Int, [Snippet]) {
        guard !terms.isEmpty else { return (0, []) }

        // Cheap AND gate + total count first — most files fail on some term and
        // never pay the line walk below.
        var totalCount = 0
        for term in terms {
            var termCount = 0
            var from = text.startIndex
            while let r = text.range(of: term, options: .caseInsensitive, range: from..<text.endIndex) {
                termCount += 1
                from = r.upperBound
                if from == text.endIndex { break }
            }
            if termCount == 0 { return (0, []) }
            totalCount += termCount
        }

        // Line walk: collect every line with a hit, tracking per-term running
        // occurrence counters so each snippet knows where its first hit sits in
        // file order (what the find-bar jump needs).
        struct Candidate { let snippet: Snippet; let distinctTerms: Int; let order: Int }
        var candidates: [Candidate] = []
        var occurrenceSoFar = [String: Int]()
        var order = 0
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineRange = text.lineRange(for: lineStart..<lineStart)
            defer { lineStart = lineRange.upperBound }
            let rawLine = String(text[lineRange])
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            var ranges: [Range<String.Index>] = []
            var distinct = 0
            var jump: (term: String, occ: Int)?
            for term in terms {
                var hits = 0
                var from = trimmed.startIndex
                while let r = trimmed.range(of: term, options: .caseInsensitive, range: from..<trimmed.endIndex) {
                    ranges.append(r)
                    if jump == nil { jump = (term, occurrenceSoFar[term, default: 0] + hits) }
                    hits += 1
                    from = r.upperBound
                    if from == trimmed.endIndex { break }
                }
                if hits > 0 { distinct += 1 }
                occurrenceSoFar[term, default: 0] += hits
            }
            guard let jump, !trimmed.isEmpty else { continue }
            candidates.append(Candidate(
                snippet: Snippet(line: trimmed, ranges: ranges.sorted { $0.lowerBound < $1.lowerBound },
                                 jumpTerm: jump.term, jumpOccurrence: jump.occ),
                distinctTerms: distinct, order: order))
            order += 1
        }

        // Prefer lines where the terms co-occur (they're what an AND query is
        // really asking about), then file order; cap as before.
        let snippets = candidates
            .sorted { $0.distinctTerms != $1.distinctTerms ? $0.distinctTerms > $1.distinctTerms
                                                           : $0.order < $1.order }
            .prefix(cap)
            .sorted { $0.order < $1.order }
            .map(\.snippet)
        return (totalCount, snippets)
    }
}
