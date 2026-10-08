import OpenUISwiftUI
import SwiftUI

/// Placeholders for components whose data comes from a `Query`. Queries run
/// once the response has finished streaming (as in react-lang), so until then
/// and until they answer, a `VisualCardBlock` bound to one has no cards and a
/// gallery has no images: the response would sit half empty and then fill in
/// all at once. These wrap the built-in components (and the native ones use the
/// same pieces) to show the shape of what's coming, then crossfade to it.
enum LoadingStates {
  /// Built-in components that get a placeholder, by the prop that holds their data.
  private static let placeholders: [String: (prop: String, shape: Placeholder.Shape)] = [
    "VisualCardBlock": ("items", .cards(height: 300)),
    "CompositeCardBlock": ("items", .cards(height: 170)),
    "ContextCardBlock": ("items", .cards(height: 120)),
    "OverviewCardBlock": ("items", .cards(height: 120)),
    "SnippetCardBlock": ("items", .rows),
    "ImageGallery": ("images", .gallery),
    "ListBlock": ("items", .rows),
  ]

  /// The component with a placeholder while its data loads, if it has one.
  static func wrap(_ component: SwiftUIComponent) -> SwiftUIComponent {
    guard let (prop, shape) = placeholders[component.name] else { return component }
    let original = component.content
    return SwiftUIComponent(component.schema) { props in
      LoadingAware(isEmpty: props.array(prop).isEmpty, shape: shape) { original(props) }
    }
  }
}

/// Shows `shape` while the content has nothing to show yet and more may come
/// (the response is streaming or its queries are loading), then crossfades to
/// the content. The port's charts follow the same rule.
struct LoadingAware<Content: View>: View {
  let isEmpty: Bool
  let shape: Placeholder.Shape
  @ViewBuilder let content: () -> Content
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    let loading = isEmpty && context.isAwaitingData
    ZStack(alignment: .topLeading) {
      if loading {
        Placeholder(shape: shape).transition(.opacity)
      } else {
        content().transition(.opacity.combined(with: .offset(y: 8)))
      }
    }
    .animation(.easeOut(duration: 0.35), value: loading)
  }
}

/// Pastel skeletons in the shape of the content they stand in for.
struct Placeholder: View {
  enum Shape {
    case cards(height: CGFloat)
    case gallery
    case rows
    case timeline
  }

  let shape: Shape
  private let tones = [Pastel.sky, Pastel.lavender, Pastel.mint, Pastel.peach]

  var body: some View {
    Group {
      switch shape {
      case .cards(let height):
        // A carousel's first card and the edge of the next. They're drawn
        // over a full-width frame rather than sized by it: two cards are wider
        // than a phone, and as the placeholder's own width they'd widen the
        // whole response until the data came in.
        Color.clear
          .frame(maxWidth: .infinity)
          .frame(height: height)
          .overlay(alignment: .leading) {
            HStack(spacing: 12) {
              ForEach(0..<2, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                  Spacer()
                  Bar(width: 160, height: 14)
                  Bar(width: 110, height: 10)
                }
                .padding(14)
                .frame(width: 280, height: height, alignment: .leading)
                .background(tones[index].fill, in: RoundedRectangle(cornerRadius: 16))
              }
            }
          }
          .clipped()
      case .gallery:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
          ForEach(0..<4, id: \.self) { index in
            RoundedRectangle(cornerRadius: 12).fill(tones[index].fill).frame(height: 130)
          }
        }
      case .rows:
        VStack(alignment: .leading, spacing: 14) {
          ForEach(0..<3, id: \.self) { index in
            HStack(spacing: 12) {
              RoundedRectangle(cornerRadius: 10).fill(tones[index].fill).frame(width: 44, height: 44)
              VStack(alignment: .leading, spacing: 6) {
                Bar(width: 170, height: 12)
                Bar(width: 110, height: 9)
              }
            }
          }
        }
      case .timeline:
        VStack(alignment: .leading, spacing: 10) {
          ForEach(0..<3, id: \.self) { index in
            HStack(spacing: 12) {
              Bar(width: 44, height: 12).frame(width: 50, alignment: .trailing)
              Circle().fill(tones[index].solid.opacity(0.6)).frame(width: 10, height: 10)
              RoundedRectangle(cornerRadius: 12).fill(tones[index].fill).frame(height: 46)
            }
          }
        }
      }
    }
    .shimmer()
    .accessibilityLabel("Loading")
  }

  private struct Bar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
      RoundedRectangle(cornerRadius: height / 2)
        .fill(Color.primary.opacity(0.08))
        .frame(width: width, height: height)
    }
  }
}

extension OpenUIContext {
  /// Whether data bound to queries may still arrive.
  var isAwaitingData: Bool { isStreaming || isQueryLoading }
}

extension View {
  /// A soft highlight sweeping across, the usual sign that something is loading.
  func shimmer() -> some View { modifier(Shimmer()) }

  /// Fades and lifts the view in after `index` earlier ones, for lists that
  /// arrive all at once.
  func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

private struct Shimmer: ViewModifier {
  @State private var phase: CGFloat = -1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .overlay {
        if !reduceMotion {
          GeometryReader { geometry in
            LinearGradient(
              colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(x: phase * geometry.size.width * 1.6)
          }
          .mask(content)
          .allowsHitTesting(false)
        }
      }
      .onAppear {
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
      }
  }
}

private struct StaggeredAppear: ViewModifier {
  let index: Int
  @State private var visible = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .opacity(visible || reduceMotion ? 1 : 0)
      .offset(y: visible || reduceMotion ? 0 : 10)
      .onAppear {
        guard !visible else { return }
        withAnimation(.spring(duration: 0.45).delay(Double(min(index, 8)) * 0.07)) { visible = true }
      }
  }
}
