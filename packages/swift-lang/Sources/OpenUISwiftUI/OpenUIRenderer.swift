import OpenUILang
import SwiftUI

/// Renders an OpenUI Lang response with a component library, updating as the
/// response streams in.
///
/// ```swift
/// OpenUIRenderer(response: text, isStreaming: isStreaming, library: OpenUIChatLibrary.library) {
///   event in send(event.humanFriendlyMessage)
/// }
/// ```
public struct OpenUIRenderer: View {
  let response: String?
  let isStreaming: Bool
  let onAction: ((ActionEvent) -> Void)?
  let onStateUpdate: ((OpenUIObject) -> Void)?

  @State private var context: OpenUIContext

  /// - Parameters:
  ///   - response: The response text so far.
  ///   - isStreaming: Whether more text is still arriving.
  ///   - library: The components the response may use. Changing it requires a new view identity.
  ///   - initialState: Restored `$state` and form values, e.g. from a saved conversation.
  ///   - toolProvider: Handles `Query` and `Mutation` tool calls.
  ///   - onStateUpdate: Called when `$state` or form values change.
  ///   - onAction: Called for actions the host handles (continue the conversation, open a URL).
  ///     A trailing closure binds here.
  public init(
    response: String?, isStreaming: Bool = false, library: SwiftUILibrary,
    initialState: OpenUIObject? = nil, toolProvider: (any ToolProvider)? = nil,
    onAction: ((ActionEvent) -> Void)? = nil,
    onStateUpdate: ((OpenUIObject) -> Void)? = nil
  ) {
    self.response = response
    self.isStreaming = isStreaming
    self.onAction = onAction
    self.onStateUpdate = onStateUpdate
    _context = State(
      initialValue: OpenUIContext(
        library: library, initialState: initialState, toolProvider: toolProvider))
  }

  public var body: some View {
    let _ = syncHandlers()
    Group {
      if let root = context.root {
        OpenUIElementView(element: root)
          .opacity(context.isQueryLoading ? 0.7 : 1)
          .animation(.easeInOut(duration: 0.2), value: context.isQueryLoading)
      }
    }
    .environment(context)
    .onChange(of: response, initial: true) {
      context.update(response: response, isStreaming: isStreaming)
    }
    .onChange(of: isStreaming) {
      context.update(response: response, isStreaming: isStreaming)
    }
  }

  /// Hands the latest closures to the context. They aren't observed, so this
  /// never triggers another render.
  private func syncHandlers() -> Bool {
    context.onAction = onAction
    context.onStateUpdate = onStateUpdate
    return true
  }
}
