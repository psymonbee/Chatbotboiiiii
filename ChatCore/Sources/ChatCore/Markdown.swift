import Foundation

/// Block-level Markdown, enough for chat replies. Inline formatting (bold, code spans,
/// links) is left in the text for `AttributedString(markdown:)` to handle.
public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case listItem(marker: String, indent: Int, text: String)
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
}

public enum Markdown {
    public static func blocks(from source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
            if !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n")))
                quote = []
            }
            if !table.isEmpty {
                blocks.append(parseTable(table))
                table = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code. An unclosed fence (mid-stream) runs to the end.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: lang.isEmpty ? nil : lang, code: code.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flush()
                i += 1
                continue
            }

            if trimmed.hasPrefix("|") {
                if table.isEmpty { flush() }
                table.append(trimmed)
                i += 1
                continue
            } else if !table.isEmpty {
                flush()
            }

            if let heading = parseHeading(trimmed) {
                flush()
                blocks.append(heading)
            } else if isRule(trimmed) {
                flush()
                blocks.append(.rule)
            } else if trimmed.hasPrefix(">") {
                if quote.isEmpty { flush() }
                quote.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if let item = parseListItem(line) {
                flush()
                blocks.append(item)
            } else {
                if !quote.isEmpty { flush() }
                paragraph.append(trimmed)
            }
            i += 1
        }
        flush()
        return blocks
    }

    /// Plain text for reading aloud: no code, no markup.
    public static func speakableText(from source: String) -> String {
        blocks(from: source).compactMap { block -> String? in
            switch block {
            case .heading(_, let t), .paragraph(let t), .quote(let t), .listItem(_, _, let t):
                return stripInline(t)
            case .code: return nil
            case .table(let header, let rows):
                return ([header] + rows).map { $0.map(stripInline).joined(separator: ", ") }.joined(separator: ". ")
            case .rule: return nil
            }
        }.joined(separator: "\n")
    }

    public static func stripInline(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[*_~`]+"#, with: "", options: .regularExpression)
        return t
    }

    // MARK: - Pieces

    static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
        return .heading(level: hashes, text: text)
    }

    static func isRule(_ line: String) -> Bool {
        let chars = line.filter { !$0.isWhitespace }
        guard chars.count >= 3, let first = chars.first, "-*_".contains(first) else { return false }
        return chars.allSatisfy { $0 == first }
    }

    static func parseListItem(_ line: String) -> MarkdownBlock? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let rest = line.dropFirst(leading.count)

        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            var text = String(rest.dropFirst(2))
            var marker = "•"
            if text.hasPrefix("[ ] ") { marker = "☐"; text.removeFirst(4) }
            else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { marker = "☑"; text.removeFirst(4) }
            return .listItem(marker: marker, indent: indent, text: text)
        }

        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 4 {
            let after = rest.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") {
                return .listItem(marker: "\(digits).", indent: indent, text: String(after.dropFirst(2)))
            }
        }
        return nil
    }

    static func parseTable(_ lines: [String]) -> MarkdownBlock {
        func cells(_ line: String) -> [String] {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("|") { l.removeFirst() }
            if l.hasSuffix("|") { l.removeLast() }
            return l.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func isSeparator(_ line: String) -> Bool {
            let c = cells(line)
            return !c.isEmpty && c.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { "-:".contains($0) }
            }
        }
        let rows = lines.filter { !isSeparator($0) }.map(cells)
        guard let header = rows.first else { return .table(header: [], rows: []) }
        let width = rows.map(\.count).max() ?? 0
        func pad(_ r: [String]) -> [String] { r + Array(repeating: "", count: max(0, width - r.count)) }
        return .table(header: pad(header), rows: rows.dropFirst().map(pad))
    }
}
