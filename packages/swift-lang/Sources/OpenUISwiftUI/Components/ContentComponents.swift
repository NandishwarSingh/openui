import OpenUILang
import SwiftUI

// MARK: - Card

struct CardView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let sources = props.array("sources")
    VStack(alignment: .leading, spacing: theme.spacing) {
      OpenUINodes(props.array("children"))
      if !sources.isEmpty {
        SourcesStrip(sources: sources)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .surface("card")
    .environment(\.openUICardSources, sources)
  }
}

/// Numbered references cited inline as [1], [2] in the card's text.
private struct SourcesStrip: View {
  let sources: [OpenUIValue]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Sources").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(sources.indices, id: \.self) { index in
            SourceCard(source: sources[index])
          }
        }
      }
    }
  }
}

/// One source, like react-ui's listed source: favicon and site name, then the
/// title. Opens the source when it has a URL.
private struct SourceCard: View {
  let source: OpenUIValue
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let url = source["url"].stringValue.flatMap(URL.init(string:))
    let card = VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Favicon(host: url?.host())
        Text(displayText(source["sourceName"])).font(.caption.weight(.medium)).lineLimit(1)
      }
      Text(displayText(source["title"]))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
    }
    .padding(8)
    .frame(width: 180, alignment: .topLeading)
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.border))
    if let url {
      Link(destination: url) { card }.buttonStyle(.plain)
    } else {
      card
    }
  }
}

/// A site's favicon from Google's favicon service, as react-ui uses, with a
/// globe while it loads or when there's no URL.
private struct Favicon: View {
  let host: String?

  var body: some View {
    Group {
      if let host, let url = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")
      {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          Image(systemName: "globe").foregroundStyle(.secondary)
        }
      } else {
        Image(systemName: "globe").foregroundStyle(.secondary)
      }
    }
    .frame(width: 20, height: 20)
    .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

struct CardHeaderView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let title = props.string("title"), !title.isEmpty {
        Text(title).font(.title3.weight(.semibold))
      }
      if let subtitle = props.string("subtitle"), !subtitle.isEmpty {
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Text

struct TextContentView: View {
  let props: ComponentProps

  var body: some View {
    // Full markdown with citations, like react-ui's TextContentWrapper.
    MarkdownBlocks(props.text("text"), citations: true)
      .font(font)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var font: Font {
    switch props.string("size") {
    case "small": return .footnote
    case "large": return .title3
    case "small-heavy": return .footnote.weight(.semibold)
    case "large-heavy": return .title3.weight(.semibold)
    default: return .body
    }
  }
}

struct MarkDownRendererView: View {
  let props: ComponentProps

  var body: some View {
    MarkdownBlocks(props.text("textMarkdown"))
      .frame(maxWidth: .infinity, alignment: .leading)
      .surface(props.string("variant") ?? "clear")
  }
}

struct InlineHeaderView: View {
  let props: ComponentProps

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(props.text("heading")).font(.headline)
      if let description = props.string("description"), !description.isEmpty {
        Text(description).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Callouts

struct CalloutView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    let field = context.stateField(name: "visible", binding: props["visible"], form: nil)
    let visible = field.isReactive ? (field.value == true || field.value == "true") : true
    if visible {
      Banner(
        variant: props.string("variant"), title: props.text("title"),
        description: props.text("description")
      )
      .task(id: field.isReactive && !context.isStreaming) {
        // A $visible binding auto-dismisses the callout after 3 seconds.
        guard field.isReactive, !context.isStreaming else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if !Task.isCancelled { field.setValue(false) }
      }
    }
  }
}

struct TextCalloutView: View {
  let props: ComponentProps

  var body: some View {
    Banner(
      variant: props.string("variant") ?? "neutral", title: props.text("title"),
      description: props.text("description"))
  }
}

private struct Banner: View {
  let variant: String?
  let title: String
  let description: String
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let color = statusColor(variant)
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(color)
      VStack(alignment: .leading, spacing: 2) {
        if !title.isEmpty { Text(title).font(.subheadline.weight(.semibold)) }
        if !description.isEmpty { InlineMarkdown(description).font(.subheadline) }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: theme.smallCornerRadius))
    .overlay(
      RoundedRectangle(cornerRadius: theme.smallCornerRadius).strokeBorder(color.opacity(0.35)))
  }

  private var symbol: String {
    switch variant {
    case "warning": return "exclamationmark.triangle.fill"
    case "error", "danger": return "xmark.octagon.fill"
    case "success": return "checkmark.circle.fill"
    case "info": return "info.circle.fill"
    default: return "text.bubble.fill"
    }
  }
}

// MARK: - Code

struct CodeBlockView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let language = props.string("language"), !language.isEmpty {
        Text(language).font(.caption.weight(.medium)).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        Text(props.text("codeString"))
          .font(.system(.callout, design: .monospaced))
          .textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.sunkSurface, in: RoundedRectangle(cornerRadius: theme.smallCornerRadius))
  }
}

// MARK: - Images

struct ImageView: View {
  let props: ComponentProps

  var body: some View {
    RemoteImage(src: props.string("src"), alt: props.text("alt"), fit: true)
  }
}

struct ImageBlockView: View {
  let props: ComponentProps

  var body: some View {
    RemoteImage(src: props.string("src"), alt: props.text("alt"), fit: true)
  }
}

struct ImageGalleryView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: theme.spacing) {
        ForEach(Array(props.array("images").enumerated()), id: \.offset) { _, image in
          VStack(alignment: .leading, spacing: 4) {
            RemoteImage(src: image["src"].stringValue, alt: displayText(image["alt"]))
              .frame(width: 220, height: 150)
              .clipped()
            let details = displayText(image["details"])
            if !details.isEmpty {
              Text(details).font(.caption).foregroundStyle(.secondary).frame(
                width: 220, alignment: .leading)
            }
          }
        }
      }
    }
  }
}

/// An image loaded from a URL, with the alt text as its accessibility label
/// and a placeholder while loading (or when the URL is missing).
///
/// `fit` keeps the image's aspect ratio at the available width (content
/// images). Otherwise the image fills whatever frame the caller gives it and
/// never affects layout, so a large photo can't widen a card or grid column.
struct RemoteImage: View {
  let src: String?
  let alt: String
  var fit = false
  @Environment(\.openUITheme) private var theme

  var body: some View {
    Group {
      if fit {
        AsyncImage(url: url, transaction: Self.fadeIn) { phase in
          if let image = phase.image {
            image.resizable().scaledToFit().transition(.opacity)
          } else {
            placeholder(phase).frame(height: 160)
          }
        }
        .frame(maxWidth: .infinity)
      } else {
        Color.clear
          .overlay {
            AsyncImage(url: url, transaction: Self.fadeIn) { phase in
              if let image = phase.image {
                image.resizable().scaledToFill().transition(.opacity)
              } else {
                placeholder(phase)
              }
            }
          }
          .clipped()
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: theme.smallCornerRadius))
    .accessibilityLabel(alt)
  }

  private var url: URL? { src.flatMap(URL.init(string:)) }

  /// The photo fades in over its loading placeholder.
  private static let fadeIn = Transaction(animation: .easeOut(duration: 0.25))

  @ViewBuilder
  private func placeholder(_ phase: AsyncImagePhase) -> some View {
    if phase.error == nil, url != nil {
      // Still loading: pulse like react-ui's skeletons.
      GeometryReader { size in SkeletonBlock(height: size.size.height, cornerRadius: 0) }
    } else {
      ZStack {
        theme.sunkSurface
        Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Separator, tags and key/value rows

struct SeparatorView: View {
  let props: ComponentProps

  var body: some View {
    if props.string("orientation") == "vertical" {
      Divider().frame(maxHeight: 24)
    } else {
      Divider()
    }
  }
}

struct TagBlockView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    FlowLayout(spacing: theme.compactSpacing) {
      ForEach(Array(props.array("tags").enumerated()), id: \.offset) { _, tag in
        let size = props.string("size")
        Text(displayText(tag))
          .font(font)
          .padding(tagPadding(size))
          .background(theme.sunkSurface, in: RoundedRectangle(cornerRadius: tagRadius(size)))
      }
    }
  }

  private var font: Font {
    switch props.string("size") {
    case "sm": return .caption2
    case "lg": return .callout
    default: return .caption
    }
  }
}

struct EntityListView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let small = props.string("size") == "small"
    VStack(spacing: 0) {
      if !small, let header = props["header"].objectValue {
        row(.object(header), emphasis: true)
        Divider()
      }
      ForEach(Array(props.array("rows").enumerated()), id: \.offset) { index, item in
        if index > 0 { Divider().opacity(0.5) }
        row(item, emphasis: false)
      }
      if !small, let footer = props["footer"].objectValue {
        Divider()
        row(.object(footer), emphasis: true)
      }
    }
    .font(small ? .footnote : .callout)
  }

  private func row(_ item: OpenUIValue, emphasis: Bool) -> some View {
    HStack {
      Text(displayText(item["left"])).foregroundStyle(emphasis ? .primary : .secondary)
      Spacer(minLength: theme.spacing)
      Text(displayText(item["right"]))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
    .fontWeight(emphasis ? .semibold : .regular)
    .padding(.vertical, 6)
  }
}
