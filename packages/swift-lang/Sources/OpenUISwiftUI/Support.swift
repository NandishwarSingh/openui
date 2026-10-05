import SwiftUI

/// Text with inline markdown (bold, italic, code, links), falling back to the
/// raw string when it doesn't parse (e.g. half-streamed markup).
struct InlineMarkdown: View {
  let source: String

  init(_ source: String) {
    self.source = source
  }

  var body: some View {
    Text(Self.attributed(source))
  }

  static func attributed(_ source: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
  }
}

/// Block-level markdown: headings, bullet and numbered lists, quotes, code
/// fences, rules and paragraphs. Inline formatting uses `InlineMarkdown`.
struct MarkdownBlocks: View {
  enum Block {
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(String, String)
    case quote(String)
    case code(String)
    case rule
    case paragraph(String)
  }

  let blocks: [Block]

  init(_ source: String) {
    blocks = Self.parse(source)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        view(for: block)
      }
    }
  }

  @ViewBuilder
  private func view(for block: Block) -> some View {
    switch block {
    case .heading(let level, let text):
      InlineMarkdown(text).font(
        level <= 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
    case .bullet(let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•")
        InlineMarkdown(text)
      }
    case .numbered(let marker, let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(marker).monospacedDigit()
        InlineMarkdown(text)
      }
    case .quote(let text):
      InlineMarkdown(text)
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3) }
    case .code(let text):
      Text(text).font(.system(.callout, design: .monospaced))
    case .rule:
      Divider()
    case .paragraph(let text):
      InlineMarkdown(text)
    }
  }

  static func parse(_ source: String) -> [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    var code: [String]? = nil

    func flushParagraph() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
      }
    }

    for rawLine in source.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("```") {
        if let lines = code {
          blocks.append(.code(lines.joined(separator: "\n")))
          code = nil
        } else {
          flushParagraph()
          code = []
        }
        continue
      }
      if code != nil {
        code!.append(rawLine)
        continue
      }
      if line.isEmpty {
        flushParagraph()
      } else if let hashes = line.prefix(while: { $0 == "#" }).count as Int?, hashes > 0,
        hashes <= 6,
        line.dropFirst(hashes).first == " "
      {
        flushParagraph()
        blocks.append(.heading(level: hashes, text: String(line.dropFirst(hashes + 1))))
      } else if line == "---" || line == "***" {
        flushParagraph()
        blocks.append(.rule)
      } else if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
        flushParagraph()
        blocks.append(.bullet(String(line.dropFirst(2))))
      } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber),
        !line[..<dot].isEmpty, line[line.index(after: dot)...].first == " "
      {
        flushParagraph()
        blocks.append(
          .numbered(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...])))
      } else if line.hasPrefix(">") {
        flushParagraph()
        blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
      } else {
        paragraph.append(line)
      }
    }
    if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
    flushParagraph()
    return blocks
  }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(subviews, width: proposal.width ?? .infinity)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in arrange(subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > width, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}
