import Foundation
import SwiftUI
import Testing

@testable import OpenUISwiftUI

#if canImport(AppKit)
  import AppKit
#endif

@MainActor
@Suite struct ChatLibraryTests {
  @Test func everyComponentHasAView() {
    for schema in ChatComponents.all {
      #expect(
        OpenUIChatLibrary.views[schema.name] != nil
          || OpenUIChatLibrary.dataOnly.contains(schema.name),
        "\(schema.name) has no view")
    }
    #expect(OpenUIChatLibrary.library.rootName == "Card")
    #expect(OpenUIChatLibrary.library.components.count == ChatComponents.all.count)
  }
}

@Suite struct CardActionTests {
  let item: OpenUIObject = ["itemIndex": 1, "itemId": "a", "itemTitle": .undefined]

  @Test func noActionContinuesWithItemContext() {
    #expect(
      withItemContext(.null, item)
        == ["type": "continue_conversation", "params": ["itemIndex": 1, "itemId": "a"]])
  }

  @Test func actionPlanAppendsSelectedItemToToAssistant() {
    let plan = OpenUIValue.actionPlan(
      ActionPlan(steps: [
        .continueConversation(message: "Go", context: "ctx"),
        .continueConversation(message: "Bare", context: nil),
        .openUrl(url: "https://openui.com"),
      ]))
    guard case .actionPlan(let merged) = withItemContext(plan, item) else {
      Issue.record("expected an action plan")
      return
    }
    let suffix = #"Selected item: {"itemIndex":1,"itemId":"a"}"#
    #expect(
      merged.steps == [
        .continueConversation(message: "Go", context: "ctx\n\(suffix)"),
        .continueConversation(message: "Bare", context: suffix),
        .openUrl(url: "https://openui.com"),
      ])
    #expect(withItemContext(plan, [:]) == plan)
  }

  @Test func legacyActionMergesParams() {
    let legacy: OpenUIValue = [
      "type": "continue_conversation", "context": "Explore", "params": ["x": 1],
    ]
    #expect(
      withItemContext(legacy, item)
        == [
          "type": "continue_conversation",
          "params": ["x": 1, "context": "Explore", "itemIndex": 1, "itemId": "a"],
        ])
  }
}

@Suite struct IconTests {
  @Test func mapsLucideNamesWithFallbacks() {
    #expect(LucideSymbols.systemName(for: "users", category: nil) == "person.2")
    #expect(
      LucideSymbols.systemName(for: "triangle-alert", category: nil) == "exclamationmark.triangle")
    #expect(LucideSymbols.systemName(for: "no-such-icon", category: "finance") == "dollarsign")
    #expect(
      LucideSymbols.systemName(for: "no-such-icon", category: nil)
        == LucideSymbols.symbols[LucideSymbols.defaultFallback])
  }

  @Test func categoryFallbacksResolve() {
    for (category, name) in LucideSymbols.categoryFallbacks {
      #expect(LucideSymbols.symbols[name] != nil, "\(category) → \(name)")
    }
  }

  #if canImport(AppKit)
    @Test func everyMappedSymbolExists() {
      for (name, symbol) in LucideSymbols.symbols {
        #expect(
          NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
          "\(name) → \(symbol)")
      }
    }
  #endif
}

@Suite struct NodeIdentityTests {
  @Test func prefersStatementIdsAndStaysUnique() {
    let element = { (id: String?) -> OpenUIValue in
      .element(ElementNode(statementId: id, typeName: "TextContent", props: [:], partial: false))
    }
    let items = NodeItem.list([element("a"), .null, element(nil), element("a"), "text"])
    #expect(items.map(\.id) == ["a", "#2", "a~1", "#4"])
  }
}

@MainActor
@Suite struct OpenUIContextTests {
  @Test func updatesAndRoutesActions() async {
    let context = OpenUIContext(library: OpenUIChatLibrary.library)
    var events: [ActionEvent] = []
    context.onAction = { events.append($0) }
    let start = context.revision

    context.update(
      response: "root = Card([FollowUpBlock([FollowUpItem(\"More\")])])", isStreaming: false)
    #expect(context.revision > start)
    #expect(context.root?.typeName == "Card")

    await context.runtime.triggerAction("More")
    #expect(events.map(\.humanFriendlyMessage) == ["More"])

    let before = context.revision
    context.runtime.store.set("$x", 1)
    #expect(context.revision > before)
  }

  @Test func seedsDefaultsOnlyAfterStreaming() {
    let context = OpenUIContext(library: OpenUIChatLibrary.library)
    context.update(response: "root = Card([])", isStreaming: true)
    context.setDefaultValue(form: "f", componentType: "Chips", name: "c", value: ["a"])
    #expect(context.fieldValue(form: "f", name: "c") == .undefined)

    context.update(response: "root = Card([])", isStreaming: false)
    context.setDefaultValue(form: "f", componentType: "Chips", name: "c", value: ["a"])
    #expect(context.fieldValue(form: "f", name: "c") == ["a"])
  }
}

#if canImport(AppKit)
  /// Renders each chat library example end to end, offscreen, and checks it
  /// produced a real layout (not an empty or collapsed view).
  @MainActor
  @Suite struct EndToEndRenderTests {
    nonisolated static let examples: [(name: String, input: String)] = {
      let url = Bundle.module.url(
        forResource: "chat-examples", withExtension: "json", subdirectory: "Fixtures")!
      let json = try! JSON.parse(String(contentsOf: url, encoding: .utf8))
      return (json.arrayValue ?? []).map { ($0["name"].stringValue!, $0["input"].stringValue!) }
    }()

    @Test(arguments: examples.map(\.name))
    func rendersChatExample(_ name: String) {
      let input = Self.examples.first { $0.name == name }!.input
      let host = NSHostingView(
        rootView: OpenUIRenderer(response: input, library: OpenUIChatLibrary.library)
          .frame(width: 420))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 600), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      #expect(host.fittingSize.height > 200, "\(name) rendered \(host.fittingSize)")
    }

    @Test func passesParseResultsAndErrorsToTheHost() {
      final class Received {
        var parseResults = 0
        var errors: [[OpenUIError]] = []
      }
      let received = Received()
      let host = NSHostingView(
        rootView: OpenUIRenderer(
          response: "root = Card([Mystery(), TextContent(\"ok\")])",
          library: OpenUIChatLibrary.library,
          onParseResult: { _ in received.parseResults += 1 },
          onError: { received.errors.append($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      #expect(received.parseResults == 1)
      #expect(received.errors.map { $0.map(\.code) } == [["unknown-component"]])
    }
  }
#endif

/// Libraries are typically global constants; this must compile under Swift 6.
let globalTestLibrary = SwiftUILibrary(
  components: [
    SwiftUIComponent(ComponentSchema("Box", description: "", props: [Prop("text", .string)])) {
      Text($0.text("text"))
    }
  ], root: "Box")

@Suite struct GlobalLibraryTests {
  @Test func globalLibraryIsUsable() {
    #expect(globalTestLibrary.paramMap["Box"]?.map(\.name) == ["text"])
  }
}
