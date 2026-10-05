import OpenUILang
import SwiftUI

// MARK: - Click context

/// Merges an item's click context into a card block's `action`, like
/// react-ui's `withItemContext`:
/// - no action: continue the conversation with the item context as params;
/// - an `Action([...])` plan: append "Selected item: {…}" to its
///   `@ToAssistant` contexts (the only channel the host receives for them);
/// - a legacy `{ type, params, url, context }` object: merge into params.
func withItemContext(_ action: OpenUIValue, _ itemContext: OpenUIObject) -> OpenUIValue {
  let context = OpenUIObject(itemContext.entries.filter { $0.value != .undefined })
  switch action {
  case .undefined, .null:
    return ["type": .string(BuiltinActionType.continueConversation), "params": .object(context)]
  case .actionPlan(let plan):
    if context.isEmpty { return action }
    let suffix = "Selected item: \(JSON.stringify(.object(context)))"
    return .actionPlan(
      ActionPlan(
        steps: plan.steps.map { step in
          guard case .continueConversation(let message, let existing) = step else { return step }
          let merged = existing.map { $0.isEmpty ? suffix : "\($0)\n\(suffix)" } ?? suffix
          return .continueConversation(message: message, context: merged)
        }))
  default:
    var params = action["params"].objectValue ?? OpenUIObject()
    if action["url"] != .undefined { params["url"] = action["url"] }
    if action["context"].isTruthy { params["context"] = action["context"] }
    for (key, value) in context { params[key] = value }
    let type =
      action["type"].isNullish ? .string(BuiltinActionType.continueConversation) : action["type"]
    return ["type": type, "params": .object(params)]
  }
}

/// A string prop of a child element (`getStringProp` in react-ui).
private func childString(_ node: OpenUIValue, _ key: String) -> String? {
  node.elementValue?.props[key]?.stringValue
}

// MARK: - Blocks

/// Lays out card items in a two-column grid or a horizontal carousel and makes
/// them clickable when the block has an action (and the response isn't streaming).
private struct CardBlockLayout<Item: View>: View {
  let props: ComponentProps
  let click: (Int, ComponentProps) -> (label: String, context: OpenUIObject)
  @ViewBuilder let item: (ComponentProps) -> Item
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let items = props.children("items")
    let gap = props.number("gap").map { CGFloat($0) } ?? theme.spacing
    let clickable = props["action"].isTruthy && !context.isStreaming
    if props.string("layout") == "carousel" {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: gap) {
          ForEach(Array(items.enumerated()), id: \.offset) { index, entry in
            card(index, entry, clickable: clickable).frame(width: 240)
          }
        }
        .padding(.vertical, 2)
      }
    } else {
      let columns = props.bool("responsive") == false ? 2 : min(2, max(items.count, 1))
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: gap, alignment: .top), count: columns),
        alignment: .leading, spacing: gap
      ) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, entry in
          card(index, entry, clickable: clickable)
        }
      }
    }
  }

  @ViewBuilder
  private func card(_ index: Int, _ entry: ComponentProps, clickable: Bool) -> some View {
    let content = item(entry).frame(maxWidth: .infinity, alignment: .topLeading)
    if clickable {
      Button {
        let (label, itemContext) = click(index, entry)
        context.triggerAction(
          label, form: form, action: withItemContext(props["action"], itemContext))
      } label: {
        content.contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      content
    }
  }
}

/// The bordered tile every card item sits on.
private struct CardTile<Content: View>: View {
  var padding: CGFloat = 12
  var tint: Color? = nil
  @ViewBuilder let content: Content
  @Environment(\.openUITheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 8) { content }
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(tint ?? theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
      .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.border))
  }
}

struct SnippetCardBlockView: View {
  let props: ComponentProps
  var body: some View {
    CardBlockLayout(props: props) { index, item in
      let title = childString(item["lhs"], "title")
      return (
        title ?? item.string("id") ?? "Snippet card \(index + 1)",
        [
          "itemIndex": .number(Double(index)), "itemId": item["id"],
          "itemTitle": title.map(OpenUIValue.string) ?? .undefined,
          "itemSubtitle": childString(item["lhs"], "subtitle").map(OpenUIValue.string)
            ?? .undefined,
          "itemValue": childString(item["rhs"], "value").map(OpenUIValue.string) ?? .undefined,
        ]
      )
    } item: {
      SnippetCard(item: $0)
    }
  }
}

struct SnippetCardItemView: View {
  let props: ComponentProps
  var body: some View { SnippetCard(item: props) }
}

private struct SnippetCard: View {
  let item: ComponentProps

  var body: some View {
    let value = compactValue
    CardTile {
      // Side by side when it fits; otherwise the value moves under the label
      // rather than squeezing it into mid-word breaks.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 8) {
          OpenUINode(item["lhs"]).fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 8)
          OpenUINode(value).fixedSize()
        }
        VStack(alignment: .leading, spacing: 8) {
          OpenUINode(item["lhs"])
          OpenUINode(value)
        }
      }
    }
  }

  /// The value sits small on the right, as in react-ui.
  private var compactValue: OpenUIValue {
    guard var rhs = item["rhs"].elementValue else { return item["rhs"] }
    rhs.props["size"] = "xs"
    return .element(rhs)
  }
}

struct OverviewCardBlockView: View {
  let props: ComponentProps
  var body: some View {
    CardBlockLayout(props: props) { index, item in
      let title = childString(item["top"], "title") ?? childString(item["top"], "value")
      let subtitle = childString(item["top"], "subtitle") ?? childString(item["top"], "subtext")
      return (
        title ?? item.string("id") ?? "Overview card \(index + 1)",
        [
          "itemIndex": .number(Double(index)), "itemId": item["id"],
          "itemTitle": title.map(OpenUIValue.string) ?? .undefined,
          "itemSubtitle": subtitle.map(OpenUIValue.string) ?? .undefined,
          "itemMetricValue": item["bottom"].elementValue?.props["value"] ?? .undefined,
        ]
      )
    } item: {
      OverviewCard(item: $0)
    }
  }
}

struct OverviewCardItemView: View {
  let props: ComponentProps
  var body: some View { OverviewCard(item: props) }
}

private struct OverviewCard: View {
  let item: ComponentProps
  var body: some View {
    CardTile {
      OpenUINode(item["top"])
      OpenUINode(item["bottom"])
    }
  }
}

struct ContextCardBlockView: View {
  let props: ComponentProps
  var body: some View {
    CardBlockLayout(props: props) { index, item in
      let title = contextTitle(item)
      return (
        title.isEmpty ? (item.string("id") ?? "Context card \(index + 1)") : title,
        [
          "itemIndex": .number(Double(index)), "itemId": item["id"], "itemTitle": .string(title),
          "itemBody": item["body"], "itemBgColor": item["bgColor"],
          "itemBgImageSrc": item["bgImageSrc"], "itemBgImageAlt": item["bgImageAlt"],
        ]
      )
    } item: {
      ContextCard(item: $0)
    }
  }
}

struct ContextCardItemView: View {
  let props: ComponentProps
  var body: some View { ContextCard(item: props) }
}

/// A context card's title text: the string, or its Tag's text.
private func contextTitle(_ item: ComponentProps) -> String {
  switch item["title"] {
  case .string(let title): return title
  case .element(let tag): return tag.props["text"]?.stringValue ?? ""
  default: return ""
  }
}

/// A compact tinted card, or a photo card with a scrim when it has a
/// background image.
private struct ContextCard: View {
  let item: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let image = item.string("bgImageSrc").flatMap { $0.isEmpty ? nil : $0 }
    VStack(alignment: .leading, spacing: 6) {
      if case .element = item["title"] {
        OpenUINode(item["title"])
      } else {
        Text(item.text("title")).font(.subheadline).opacity(0.75)
      }
      if let body = item.string("body"), !body.isEmpty {
        Text(body).font(.headline)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: image == nil ? nil : 130, alignment: .bottomLeading)
    .foregroundStyle(image == nil ? Color.primary : Color.white)
    .background {
      if let image {
        RemoteImage(src: image, alt: item.text("bgImageAlt"))
          .overlay(
            LinearGradient(
              colors: [.black.opacity(0.1), .black.opacity(0.7)], startPoint: .top,
              endPoint: .bottom))
      } else {
        item.string("bgColor") == "gray" ? theme.sunkSurface : theme.surface
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.border))
  }
}

struct CompositeCardBlockView: View {
  let props: ComponentProps
  var body: some View {
    CardBlockLayout(props: props) { index, item in
      let header = item["header"].elementValue?.props ?? OpenUIObject()
      func pick(_ keys: String...) -> String? {
        keys.lazy.compactMap { header[$0]?.stringValue }.first
      }
      let title = pick("title", "value")
      let alt = pick("alt")
      let footer = item["footer"]
      let label = [title, alt, item.string("id")].compactMap { $0 }.first { !$0.isEmpty }
      return (
        label ?? "Composite card \(index + 1)",
        [
          "itemIndex": .number(Double(index)), "itemId": item["id"],
          "itemHeaderTitle": title.map(OpenUIValue.string) ?? .undefined,
          "itemHeaderSubtitle": pick("subtitle", "subtext").map(OpenUIValue.string) ?? .undefined,
          "itemHeaderAlt": alt.map(OpenUIValue.string) ?? .undefined,
          "itemBodyCount": .number(Double(item.array("body").count)),
          "itemFooterPrice": footer["price"].elementValue?.props["value"] ?? .undefined,
          "itemFooterButtonLabel": footer["button"].elementValue?.props["label"] ?? .undefined,
        ]
      )
    } item: {
      CompositeCard(item: $0)
    }
  }
}

struct CompositeCardItemView: View {
  let props: ComponentProps
  var body: some View { CompositeCard(item: props) }
}

private struct CompositeCard: View {
  let item: ComponentProps
  var body: some View {
    CardTile {
      OpenUINode(item["header"])
      OpenUINodes(item.array("body"), spacing: 8)
      let footer = item["footer"]
      if !footer["price"].isNullish || !footer["button"].isNullish {
        HStack(alignment: .center) {
          OpenUINode(footer["price"])
          Spacer(minLength: 8)
          OpenUINode(footer["button"])
        }
      }
    }
  }
}

struct VisualCardBlockView: View {
  let props: ComponentProps
  var body: some View {
    CardBlockLayout(props: props) { index, item in
      let bodyValue = item["body"].elementValue?.props["value"]?.stringValue
      let tagText = item["tag"].elementValue?.props["text"]?.stringValue
      let label = [bodyValue, tagText, item.string("id")].compactMap { $0 }.first { !$0.isEmpty }
      return (
        label ?? "Visual card \(index + 1)",
        [
          "itemIndex": .number(Double(index)), "itemId": item["id"],
          "itemTag": tagText.map(OpenUIValue.string) ?? .undefined,
          "itemBody": bodyValue.map(OpenUIValue.string) ?? .undefined,
          "itemBodySubtext": item["body"].elementValue?.props["subtext"] ?? .undefined,
          "itemBgImageSrc": item["bgImageSrc"], "itemBgImageAlt": item["bgImageAlt"],
        ]
      )
    } item: {
      VisualCard(item: $0)
    }
  }
}

struct VisualCardItemView: View {
  let props: ComponentProps
  var body: some View { VisualCard(item: props) }
}

/// A photo-first card: full-bleed image, tag on top, bold text panel below.
private struct VisualCard: View {
  let item: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      RemoteImage(src: item.string("bgImageSrc"), alt: item.text("bgImageAlt"))
        .frame(height: 140)
        .clipped()
        .overlay(alignment: .topLeading) {
          OpenUINode(item["tag"])
            .environment(\.openUITagOnImage, true)
            .padding(8)
        }
      OpenUINode(item["body"]).padding(12)
    }
    .background(theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.border))
  }
}

// MARK: - Building blocks

/// `Text` / `BoldText`: a value line with optional subtext. `variant "number"`
/// uses tabular digits; `subtextVariant "metric"` colors a leading +/- green/red.
struct TextLineView: View {
  let props: ComponentProps
  let bold: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(props.text("value"))
        .font(font.weight(bold ? .semibold : .regular))
        .monospacedDigit(props.string("variant") == "number")
      if let subtext = props.string("subtext"), !subtext.isEmpty {
        Text(subtext)
          .font(.caption)
          .monospacedDigit(props.string("subtextVariant") != "text")
          .foregroundStyle(subtextColor(subtext))
      }
    }
  }

  private var font: Font {
    switch props.string("size") {
    case "xs": return .footnote
    case "sm": return .subheadline
    case "lg": return .title2
    default: return .body
    }
  }

  private func subtextColor(_ subtext: String) -> Color {
    guard props.string("subtextVariant") == "metric" else { return .secondary }
    if subtext.hasPrefix("+") { return .green }
    if subtext.hasPrefix("-") || subtext.hasPrefix("−") { return .red }
    return .secondary
  }
}

extension View {
  @ViewBuilder
  fileprivate func monospacedDigit(_ enabled: Bool) -> some View {
    if enabled { monospacedDigit() } else { self }
  }
}

struct IconTextView: View {
  let props: ComponentProps

  var body: some View {
    let vertical = props.string("layout") == "vertical"
    let layout =
      vertical
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 10))
    layout {
      IconBadge(
        symbol: iconSymbol(props["icon"])
          ?? LucideSymbols.systemName(for: "circle-dot", category: nil),
        variant: props.string("iconVariant"), size: props.string("iconSize"))
      TitleStack(props: props)
    }
  }
}

/// An icon on a tinted rounded square.
private struct IconBadge: View {
  let symbol: String
  let variant: String?
  let size: String?
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let side: CGFloat =
      switch size {
      case "xs": 20
      case "s", "sm": 26
      case "l", "lg": 40
      case "xl": 48
      default: 32
      }
    let (foreground, background) = colors
    Image(systemName: symbol)
      .font(.system(size: side * 0.5))
      .foregroundStyle(foreground)
      .frame(width: side, height: side)
      .background(background, in: RoundedRectangle(cornerRadius: theme.smallCornerRadius))
  }

  private var colors: (Color, Color) {
    switch variant {
    case "info", "success", "warning", "danger":
      let color = statusColor(variant)
      return (color, color.opacity(0.14))
    case "inverted": return (Color(white: 0.98), Color.primary)
    case "filled": return (.white, .accentColor)
    case "soft": return (.accentColor, Color.accentColor.opacity(0.14))
    default: return (.primary, theme.sunkSurface)
    }
  }
}

/// Title (bold when asked) with an optional subtitle.
private struct TitleStack: View {
  let props: ComponentProps
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(props.text("title")).fontWeight(props.bool("bold") == true ? .semibold : .medium)
      if let subtitle = props.string("subtitle"), !subtitle.isEmpty {
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct ImageTextView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let size = CGFloat(props.number("imageSize") ?? 40)
    let vertical = props.string("layout") == "vertical"
    let layout =
      vertical
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 10))
    layout {
      RemoteImage(src: props.string("src"), alt: props.text("alt"))
        .frame(width: size, height: size)
      TitleStack(props: props)
    }
  }
}

struct ImageTextLargeView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RemoteImage(src: props.string("src"), alt: props.text("alt"))
        .frame(height: 160)
        .clipped()
      TitleStack(props: props)
    }
  }
}

struct MetricIndicatorInlineView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(props.text("value")).font(.headline.monospacedDigit())
        TrendLabel(trend: props["trend"])
      }
      if let subtext = props.string("subtext"), !subtext.isEmpty {
        Text(subtext).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct MetricIndicatorWithStrikethroughView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(props.text("value")).font(.title3.weight(.semibold).monospacedDigit())
        if let previous = props.string("previousValue"), !previous.isEmpty {
          Text(previous).font(.subheadline).strikethrough().foregroundStyle(.secondary)
        }
        TrendLabel(trend: props["trend"])
      }
      if let subtext = props.string("subtext"), !subtext.isEmpty {
        Text(subtext).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

/// `{ direction, value }` as an arrow and percentage, green up, red down.
private struct TrendLabel: View {
  let trend: OpenUIValue

  var body: some View {
    if let value = trend["value"].numberValue {
      let up = trend["direction"].stringValue == "up"
      HStack(spacing: 2) {
        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
        Text("\(jsNumberToString(value))%")
      }
      .font(.caption.weight(.medium).monospacedDigit())
      .foregroundStyle(up ? .green : .red)
    }
  }
}
