import ChatCore
import SwiftUI

/// Renders a reply's Markdown: headings, lists, quotes, tables and code blocks,
/// with inline styling handled by AttributedString.
struct MarkdownView: View {
    let source: String

    var body: some View {
        let blocks = Markdown.blocks(from: source)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, 4)

        case .paragraph(let text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let marker, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Self.inline(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case .quote(let text):
            Text(Self.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.magenta.opacity(0.7)).frame(width: 3)
                }

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows)

        case .rule:
            Divider().overlay(Theme.hairline)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Clipboard.copy(code)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

struct TableBlockView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(header.indices, id: \.self) { i in
                        Text(MarkdownView.inline(header[i])).font(.subheadline.weight(.semibold))
                    }
                }
                Divider().overlay(Theme.hairline)
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(rows[r].indices, id: \.self) { c in
                            Text(MarkdownView.inline(rows[r][c])).font(.subheadline)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
