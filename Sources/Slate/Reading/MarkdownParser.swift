import Foundation

/// A rendered block of a note (used by Reading mode). The editor still edits the
/// literal Markdown; this is a read view parsed from it.
/// A key/value pair from a note's YAML frontmatter.
struct Prop: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let value: String
}

struct Block: Identifiable {
    let id = UUID()
    let kind: Kind
    enum Kind {
        case properties([Prop])
        case heading(level: Int, text: String, anchor: Int)
        case paragraph(text: String)
        case listItem(ordered: Bool, number: Int, indent: Int, text: String)
        case task(checked: Bool, indent: Int, text: String, checkboxIndex: Int)
        case quote(text: String)
        case callout(kind: String, title: String, body: String)
        case code(language: String, text: String)
        case divider
        case image(alt: String, source: String)
        case table(headers: [String], rows: [[String]])
    }
}

/// Line-based Markdown → [Block] parser. Deliberately forgiving: anything it
/// doesn't recognize falls through to a paragraph, so nothing is ever lost.
enum MarkdownParser {
    private static let headingRx = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$")
    private static let taskRx    = try! NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+\\[([ xX])\\]\\s?(.*)$")
    private static let ulRx      = try! NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+(.*)$")
    private static let olRx      = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)[.)]\\s+(.*)$")
    private static let imgRefRx  = try! NSRegularExpression(pattern: "^!\\[([^\\]]*)\\]\\(([^)]+)\\)\\s*$")
    private static let imgWikiRx = try! NSRegularExpression(pattern: "^!\\[\\[([^\\]]+)\\]\\]\\s*$")
    private static let calloutRx = try! NSRegularExpression(pattern: "^\\[!([A-Za-z]+)\\]\\s*(.*)$")
    private static let hrRx      = try! NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})$")

    static func parse(_ content: String) -> [Block] {
        let lines = content.components(separatedBy: "\n")
        var offsets: [Int] = []
        var loc = 0
        for line in lines { offsets.append(loc); loc += (line as NSString).length + 1 }

        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(Block(kind: .paragraph(text: paragraph.joined(separator: " "))))
                paragraph = []
            }
        }

        var i = 0
        if lines.first == "---" {                       // YAML frontmatter → properties block
            var j = 1
            while j < lines.count && lines[j] != "---" { j += 1 }
            if j < lines.count {
                let props = parseFrontmatter(Array(lines[1..<j]))
                if !props.isEmpty { blocks.append(Block(kind: .properties(props))) }
                i = j + 1
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineStart = offsets[i]

            if trimmed.hasPrefix("```") {               // fenced code
                flush()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []; i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                blocks.append(Block(kind: .code(language: lang, text: code.joined(separator: "\n"))))
                continue
            }
            if trimmed.isEmpty { flush(); i += 1; continue }

            if let m = headingRx.firstMatch(in: line, range: full(line)) {
                flush()
                blocks.append(Block(kind: .heading(level: m.range(at: 1).length,
                    text: sub(line, m.range(at: 2)), anchor: lineStart)))
                i += 1; continue
            }
            if hrRx.firstMatch(in: trimmed, range: full(trimmed)) != nil {
                flush(); blocks.append(Block(kind: .divider)); i += 1; continue
            }
            if let m = imgRefRx.firstMatch(in: line, range: full(line)) {
                flush(); blocks.append(Block(kind: .image(alt: sub(line, m.range(at: 1)),
                    source: sub(line, m.range(at: 2))))); i += 1; continue
            }
            if let m = imgWikiRx.firstMatch(in: line, range: full(line)) {
                flush(); blocks.append(Block(kind: .image(alt: "", source: sub(line, m.range(at: 1)))))
                i += 1; continue
            }
            if trimmed.hasPrefix(">") {                  // quote / callout
                flush()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var q = lines[i].trimmingCharacters(in: .whitespaces); q.removeFirst()
                    if q.hasPrefix(" ") { q.removeFirst() }
                    quote.append(q); i += 1
                }
                if let first = quote.first, let cm = calloutRx.firstMatch(in: first, range: full(first)) {
                    let type = sub(first, cm.range(at: 1))
                    let title = cm.range(at: 2).location != NSNotFound ? sub(first, cm.range(at: 2)) : ""
                    blocks.append(Block(kind: .callout(kind: type.lowercased(),
                        title: title.isEmpty ? type.capitalized : title,
                        body: quote.dropFirst().joined(separator: "\n"))))
                } else {
                    blocks.append(Block(kind: .quote(text: quote.joined(separator: "\n"))))
                }
                continue
            }
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flush()
                let headers = splitRow(line)
                var rows: [[String]] = []; i += 2
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitRow(lines[i])); i += 1
                }
                blocks.append(Block(kind: .table(headers: headers, rows: rows))); continue
            }
            if let m = taskRx.firstMatch(in: line, range: full(line)) {
                flush()
                blocks.append(Block(kind: .task(
                    checked: sub(line, m.range(at: 3)).lowercased() == "x",
                    indent: indentLevel(sub(line, m.range(at: 1))),
                    text: sub(line, m.range(at: 4)),
                    checkboxIndex: lineStart + m.range(at: 3).location)))
                i += 1; continue
            }
            if let m = olRx.firstMatch(in: line, range: full(line)) {
                flush()
                blocks.append(Block(kind: .listItem(ordered: true,
                    number: Int(sub(line, m.range(at: 2))) ?? 1,
                    indent: indentLevel(sub(line, m.range(at: 1))),
                    text: sub(line, m.range(at: 3)))))
                i += 1; continue
            }
            if let m = ulRx.firstMatch(in: line, range: full(line)) {
                flush()
                blocks.append(Block(kind: .listItem(ordered: false, number: 0,
                    indent: indentLevel(sub(line, m.range(at: 1))),
                    text: sub(line, m.range(at: 3)))))
                i += 1; continue
            }

            paragraph.append(trimmed); i += 1
        }
        flush()
        return blocks
    }

    // MARK: helpers

    private static func full(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }
    private static func sub(_ s: String, _ r: NSRange) -> String {
        guard r.location != NSNotFound else { return "" }
        return (s as NSString).substring(with: r)
    }
    private static func parseFrontmatter(_ lines: [String]) -> [Prop] {
        var props: [Prop] = []
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // "- item" continuation appends to the previous key's value
            if trimmed.hasPrefix("-"), let last = props.last {
                let item = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                let joined = last.value.isEmpty ? String(item) : last.value + ", " + item
                props[props.count - 1] = Prop(key: last.key, value: joined)
                continue
            }
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") && value.hasSuffix("]") {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            }
            props.append(Prop(key: key, value: value))
        }
        return props
    }

    private static func indentLevel(_ leading: String) -> Int {
        let spaces = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min(spaces / 2, 6)
    }
    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|"), t.contains("-") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }
    private static func splitRow(_ line: String) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }
}
