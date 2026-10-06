import OpenUILang
import SwiftUI

/// Renders any prop value: an element through its library component, an array
/// as a stack of nodes, scalars as text, and nothing for null.
public struct OpenUINode: View {
  public let value: OpenUIValue

  public init(_ value: OpenUIValue) {
    self.value = value
  }

  public var body: some View {
    switch value {
    case .element(let element):
      OpenUIElementView(element: element)
    case .array(let items):
      OpenUINodes(items)
    case .string, .number, .bool:
      Text(displayText(value))
    default:
      EmptyView()
    }
  }
}

/// Renders a list of nodes in a vertical stack. Each node keeps its identity
/// across streamed updates (by statement name, else position), so inputs keep
/// focus and local state while the response re-renders.
public struct OpenUINodes: View {
  let items: [NodeItem]
  let spacing: CGFloat?
  let alignment: HorizontalAlignment

  public init(
    _ values: [OpenUIValue], spacing: CGFloat? = OpenUITheme.default.spacing,
    alignment: HorizontalAlignment = .leading
  ) {
    self.items = NodeItem.list(values)
    self.spacing = spacing
    self.alignment = alignment
  }

  public var body: some View {
    VStack(alignment: alignment, spacing: spacing) {
      ForEach(items) { item in
        OpenUINode(item.value).transition(.openUIInsertion)
      }
    }
    // Nodes keep their identity, so only newly streamed ones animate in.
    .openUIAnimation(Motion.insertion, value: items.map(\.id))
  }
}

/// A node with a stable identity for `ForEach`.
struct NodeItem: Identifiable {
  let id: String
  let value: OpenUIValue

  static func list(_ values: [OpenUIValue]) -> [NodeItem] {
    var seen: [String: Int] = [:]
    return values.enumerated().compactMap { index, value in
      if value.isNullish { return nil }
      var id = value.elementValue?.statementId ?? "#\(index)"
      // A statement referenced twice in one list still needs unique ids.
      if let count = seen[id] {
        seen[id] = count + 1
        id += "~\(count)"
      } else {
        seen[id] = 1
      }
      return NodeItem(id: id, value: value)
    }
  }
}

/// Renders an element with its library component; unknown components render nothing.
struct OpenUIElementView: View {
  let element: ElementNode
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    if let component = context.library.component(named: element.typeName) {
      component.content(ComponentProps(element))
    }
  }
}
