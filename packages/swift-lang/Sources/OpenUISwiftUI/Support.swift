import OpenUILang
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
    // Only ~~double~~ tildes strike through, as in react-ui; a lone "~$5K"
    // ("about") stays literal.
    return (try? AttributedString(markdown: escapingLoneTildes(source), options: options))
      ?? AttributedString(source)
  }

  private static func escapingLoneTildes(_ source: String) -> String {
    let characters = Array(source)
    var result = ""
    for (index, character) in characters.enumerated() {
      if character == "~", characters[safe: index - 1] != "~", characters[safe: index + 1] != "~" {
        result += "\\~"
      } else {
        result.append(character)
      }
    }
    return result
  }
}

/// Inline markdown with react-ui's citations: a run of `[1][2]` markers
/// becomes a small globe when the card has a source with a title and name for
/// one of them, and disappears otherwise.
struct CitedMarkdown: View {
  let source: String
  @Environment(\.openUICardSources) private var sources

  var body: some View {
    let segments = Self.segments(source)
    return segments.indices.reduce(Text("")) { text, index in
      switch segments[index] {
      case .text(let part):
        return text + Text(InlineMarkdown.attributed(part))
      case .citation(let indices) where hasSource(indices):
        // The marker pattern swallows the space after it; put it back before a word.
        let spaced: Bool = {
          guard index + 1 < segments.count, case .text(let next) = segments[index + 1] else {
            return false
          }
          return next.first.map { $0.isLetter || $0.isNumber } ?? false
        }()
        return text + Text(Image(systemName: "globe")).font(.caption).foregroundStyle(.secondary)
          + Text(spaced ? " " : "")
      case .citation:
        return text
      }
    }
  }

  enum Segment: Equatable {
    case text(String)
    case citation([Int])
  }

  /// Splits on react-ui's citation pattern, `(\[\d+\]\s*)+`.
  nonisolated static func segments(_ source: String) -> [Segment] {
    let pattern = /(\[\d+\]\s*)+/
    var segments: [Segment] = []
    var rest = source[...]
    while let match = rest.firstMatch(of: pattern) {
      if match.range.lowerBound > rest.startIndex {
        segments.append(.text(String(rest[..<match.range.lowerBound])))
      }
      let indices = match.output.0.matches(of: /\[(\d+)\]/).compactMap { Int($0.output.1) }
      segments.append(.citation(indices))
      rest = rest[match.range.upperBound...]
    }
    if !rest.isEmpty { segments.append(.text(String(rest))) }
    return segments
  }

  private func hasSource(_ indices: [Int]) -> Bool {
    indices.contains { index in
      guard index >= 1, index <= sources.count else { return false }
      let source = sources[index - 1]
      let title = source["title"].stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
      let name = source["sourceName"].stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
      return !title.isEmpty && !name.isEmpty
    }
  }
}

private struct CardSourcesKey: EnvironmentKey {
  static let defaultValue: [OpenUIValue] = []
}

extension EnvironmentValues {
  /// The enclosing Card's `sources`, which inline citations refer to.
  var openUICardSources: [OpenUIValue] {
    get { self[CardSourcesKey.self] }
    set { self[CardSourcesKey.self] = newValue }
  }
}

/// Block-level markdown: headings, bullet and numbered lists, quotes, code
/// fences, rules and paragraphs. Inline formatting uses `InlineMarkdown`.
struct MarkdownBlocks: View {
  enum Block: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(String, String)
    case quote(String)
    case code(String)
    /// `$$ … $$` math. There's no native TeX renderer, so it shows as source.
    case math(String)
    case table(header: [String], rows: [[String]])
    case rule
    case paragraph(String)
  }

  let blocks: [Block]
  /// Renders `[n]` markers as citations (TextContent does, MarkDownRenderer doesn't).
  let citations: Bool

  init(_ source: String, citations: Bool = false) {
    blocks = Self.parse(source)
    self.citations = citations
  }

  @ViewBuilder
  private func inline(_ text: String) -> some View {
    if citations { CitedMarkdown(source: text) } else { InlineMarkdown(text) }
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
      inline(text).font(
        level <= 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
    case .bullet(let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•")
        inline(text)
      }
    case .numbered(let marker, let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(marker).monospacedDigit()
        inline(text)
      }
    case .quote(let text):
      inline(text)
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3) }
    case .code(let text):
      Text(text).font(.system(.callout, design: .monospaced))
    case .math(let tex):
      Text(tex)
        .font(.system(.callout, design: .monospaced))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    case .table(let header, let rows):
      ScrollView(.horizontal, showsIndicators: false) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
          GridRow {
            ForEach(header.indices, id: \.self) { inline(header[$0]).fontWeight(.semibold) }
          }
          Divider()
          ForEach(rows.indices, id: \.self) { row in
            GridRow {
              ForEach(rows[row].indices, id: \.self) { inline(rows[row][$0]) }
            }
          }
        }
      }
    case .rule:
      Divider()
    case .paragraph(let text):
      inline(text)
    }
  }

  static func parse(_ source: String) -> [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    var code: [String]? = nil
    var math: [String]? = nil
    var table: [[String]] = []

    func cells(_ line: String) -> [String] {
      var trimmed = Substring(line)
      if trimmed.hasPrefix("|") { trimmed = trimmed.dropFirst() }
      if trimmed.hasSuffix("|") { trimmed = trimmed.dropLast() }
      return trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
    }

    func flushTable() {
      // A GFM table: header, a ---|--- separator, then rows.
      if table.count >= 2,
        table[1].allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } })
      {
        blocks.append(.table(header: table[0], rows: Array(table.dropFirst(2))))
      } else {
        paragraph.append(contentsOf: table.map { "| " + $0.joined(separator: " | ") + " |" })
      }
      table = []
    }

    func flushParagraph() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
      }
    }

    for rawLine in source.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if math != nil {
        if line.hasSuffix("$$") {
          math!.append(String(line.dropLast(2)))
          blocks.append(
            .math(math!.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
          math = nil
        } else {
          math!.append(rawLine)
        }
        continue
      }
      if !table.isEmpty, !line.hasPrefix("|") { flushTable() }
      if line.hasPrefix("$$"), code == nil {
        flushParagraph()
        let rest = line.dropFirst(2)
        if rest.hasSuffix("$$"), rest.count >= 2 {
          blocks.append(.math(String(rest.dropLast(2)).trimmingCharacters(in: .whitespaces)))
        } else {
          math = [String(rest)]
        }
        continue
      }
      if line.hasPrefix("|"), code == nil {
        if table.isEmpty { flushParagraph() }
        table.append(cells(line))
        continue
      }
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
    if !table.isEmpty { flushTable() }
    if let lines = math { blocks.append(.math(lines.joined(separator: "\n"))) }
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
