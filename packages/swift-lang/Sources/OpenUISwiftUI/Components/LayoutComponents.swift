import OpenUILang
import SwiftUI

// MARK: - Table

/// Column-oriented table: each `Col` holds its own data array. Cells can be
/// text or elements (e.g. buttons from `@Each`). Long tables page by 10 rows.
struct TableView: View {
  let props: ComponentProps
  @State private var page = 0
  @Environment(\.openUITheme) private var theme

  private static let pageSize = 10

  var body: some View {
    let columns = props.children("columns")
    let data = columns.map { column -> [OpenUIValue] in
      let raw = column["data"]
      if case .array(let items) = raw { return items }
      return raw.isNullish ? [] : [raw]
    }
    let rowCount = data.map(\.count).max() ?? 0
    let pages = max(1, Int((Double(rowCount) / Double(Self.pageSize)).rounded(.up)))
    let current = min(page, pages - 1)
    let rows = Array(
      stride(from: current * Self.pageSize, to: min(rowCount, (current + 1) * Self.pageSize), by: 1)
    )

    VStack(alignment: .leading, spacing: theme.compactSpacing) {
      ScrollView(.horizontal, showsIndicators: false) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
          GridRow {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
              Text(column.text("label"))
                .font(.subheadline.weight(.semibold))
                .gridColumnAlignment(isNumeric(column) ? .trailing : .leading)
            }
          }
          Divider()
          ForEach(rows, id: \.self) { row in
            GridRow {
              ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                cell(row < data[index].count ? data[index][row] : .null, numeric: isNumeric(column))
              }
            }
            if row != rows.last { Divider().opacity(0.5) }
          }
        }
        .padding(.vertical, 4)
      }
      if pages > 1 {
        HStack {
          Button("Previous") { page = max(0, current - 1) }.disabled(current == 0)
          Spacer()
          Text("\(current + 1) / \(pages)").font(.caption.monospacedDigit()).foregroundStyle(
            .secondary)
          Spacer()
          Button("Next") { page = min(pages - 1, current + 1) }.disabled(current >= pages - 1)
        }
        .buttonStyle(.borderless)
        .font(.caption)
      }
    }
  }

  private func isNumeric(_ column: ComponentProps) -> Bool { column.string("type") == "number" }

  @ViewBuilder
  private func cell(_ value: OpenUIValue, numeric: Bool) -> some View {
    switch value {
    case .element, .array:
      OpenUINode(value)
    default:
      Text(displayText(value))
        .font(numeric ? .callout.monospacedDigit() : .callout)
    }
  }
}

struct ColView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(props.text("label")).font(.subheadline.weight(.semibold))
      OpenUINodes(props.array("data"), spacing: 4)
    }
  }
}

// MARK: - Lists

struct ListBlockView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    let numbered = props.string("variant") != "image"
    let small = props.string("size") == "small"
    VStack(alignment: .leading, spacing: small ? 6 : 10) {
      ForEach(Array(props.children("items").enumerated()), id: \.offset) { index, item in
        ListRow(
          item: item, marker: numbered ? "\(index + 1)" : nil, small: small,
          onTap: item["action"].isNullish
            ? nil
            : { context.triggerAction(item.text("title"), action: item["action"]) })
      }
    }
  }
}

struct ListItemView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    ListRow(
      item: props, marker: nil, small: false,
      onTap: props["action"].isNullish
        ? nil : { context.triggerAction(props.text("title"), action: props["action"]) })
  }
}

/// A list row: marker or image, title and subtitle, clickable only with an action.
private struct ListRow: View {
  let item: ComponentProps
  let marker: String?
  let small: Bool
  let onTap: (() -> Void)?
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let row = HStack(alignment: .top, spacing: 10) {
      if let marker {
        Text(marker)
          .font(.caption.weight(.semibold).monospacedDigit())
          .frame(width: 22, height: 22)
          .background(theme.sunkSurface, in: Circle())
      } else if let src = item["image"]["src"].stringValue {
        RemoteImage(src: src, alt: displayText(item["image"]["alt"]))
          .frame(width: 44, height: 44)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(item.text("title")).font(small ? .subheadline : .body)
        if let subtitle = item.string("subtitle"), !subtitle.isEmpty {
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      if onTap != nil {
        if let actionLabel = item.string("actionLabel"), !actionLabel.isEmpty {
          Text(actionLabel).font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
        } else {
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .contentShape(Rectangle())
    if let onTap {
      Button(action: onTap) { row }.buttonStyle(.plain)
    } else {
      row
    }
  }
}

struct FollowUpBlockView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(props.children("items").enumerated()), id: \.offset) { _, item in
        FollowUpButton(text: item.text("text")) { context.triggerAction(item.text("text")) }
      }
    }
    .disabled(context.isStreaming)
  }
}

struct FollowUpItemView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    FollowUpButton(text: props.text("text")) { context.triggerAction(props.text("text")) }
      .disabled(context.isStreaming)
  }
}

/// A suggested next message; tapping it sends the text as the user's message.
private struct FollowUpButton: View {
  let text: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "arrow.turn.down.right").font(.caption)
        Text(text).multilineTextAlignment(.leading)
      }
      .font(.subheadline)
    }
    .buttonStyle(.borderless)
  }
}

struct StepsView: View {
  let props: ComponentProps

  var body: some View {
    let items = props.children("items")
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        HStack(alignment: .top, spacing: 12) {
          VStack(spacing: 0) {
            Text("\(index + 1)")
              .font(.caption.weight(.bold).monospacedDigit())
              .foregroundStyle(.white)
              .frame(width: 22, height: 22)
              .background(Color.accentColor, in: Circle())
            if index < items.count - 1 {
              Rectangle().fill(.secondary.opacity(0.3)).frame(width: 2).frame(maxHeight: .infinity)
            }
          }
          StepContent(item: item).padding(.bottom, index < items.count - 1 ? 14 : 0)
        }
      }
    }
  }
}

struct StepsItemView: View {
  let props: ComponentProps
  var body: some View { StepContent(item: props) }
}

private struct StepContent: View {
  let item: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(item.text("title")).font(.subheadline.weight(.semibold))
      InlineMarkdown(item.text("details")).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Tabs, accordions and sections

struct TabsView: View {
  let props: ComponentProps
  @State private var selected: String?
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let items = props.children("items")
    let current = selected ?? items.first?.text("value")
    VStack(alignment: .leading, spacing: theme.spacing) {
      Picker("", selection: Binding(get: { current ?? "" }, set: { selected = $0 })) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          Text(item.text("trigger")).tag(item.text("value"))
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      if let item = items.first(where: { $0.text("value") == current }) {
        OpenUINodes(item.array("content"))
      }
    }
  }
}

struct AccordionView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      let items = props.children("items")
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        Disclosure(
          trigger: item.text("trigger"), content: item.array("content"), initiallyOpen: false)
        if index < items.count - 1 { Divider() }
      }
    }
  }
}

struct SectionBlockView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let sections = props.children("sections")
    let foldable = props.bool("isFoldable") ?? true
    VStack(alignment: .leading, spacing: foldable ? 0 : theme.spacing) {
      ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
        if foldable {
          // Sections open by default so they reveal content as it streams in.
          Disclosure(
            trigger: section.text("trigger"), content: section.array("content"), initiallyOpen: true
          )
          if index < sections.count - 1 { Divider() }
        } else {
          VStack(alignment: .leading, spacing: theme.compactSpacing) {
            Text(section.text("trigger")).font(.headline)
            OpenUINodes(section.array("content"))
          }
        }
      }
    }
  }
}

/// A sub-item rendered on its own: its trigger as a heading, then its content.
struct TriggeredContentView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.compactSpacing) {
      Text(props.text("trigger")).font(.headline)
      OpenUINodes(props.array("content"))
    }
  }
}

private struct Disclosure: View {
  let trigger: String
  let content: [OpenUIValue]
  @State private var isOpen: Bool

  init(trigger: String, content: [OpenUIValue], initiallyOpen: Bool) {
    self.trigger = trigger
    self.content = content
    _isOpen = State(initialValue: initiallyOpen)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isOpen) {
      OpenUINodes(content).padding(.top, 6)
    } label: {
      Text(trigger).font(.subheadline.weight(.semibold))
    }
    .padding(.vertical, 8)
  }
}

// MARK: - Carousel

/// Slides scroll horizontally; each slide is an array of content.
struct CarouselView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: theme.spacing) {
        ForEach(Array(props.array("children").enumerated()), id: \.offset) { _, slide in
          OpenUINodes(slide.arrayValue ?? [slide])
            .frame(width: 260, alignment: .topLeading)
            .surface(props.string("variant") ?? "card")
        }
      }
      .padding(.vertical, 2)
    }
  }
}
