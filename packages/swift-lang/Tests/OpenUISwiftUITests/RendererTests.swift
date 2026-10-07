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
      // The smallest example (a short table) is about 195pt; empty or collapsed
      // renders are far below this.
      #expect(host.fittingSize.height > 120, "\(name) rendered \(host.fittingSize)")
    }

    /// The bug vishxrad hit in the Angular port: an input recreated on every
    /// update loses focus mid-typing. The AppKit text field behind the SwiftUI
    /// input must be the same object across streamed updates and typing.
    @Test func keepsInputViewsAcrossStreamingAndTyping() {
      final class Model: ObservableObject {
        @Published var response = """
          $name = ""
          root = Card([form, note])
          form = Form("f", btns, [field])
          btns = Buttons([Button("Save")])
          field = FormControl("Name", Input("name", "Your name", "text", null, $name))
          """
        var state = OpenUIObject()
      }
      struct Harness: View {
        @ObservedObject var model: Model
        var body: some View {
          OpenUIRenderer(
            response: model.response, isStreaming: true, library: OpenUIChatLibrary.library,
            onStateUpdate: { model.state = $0 }
          )
          .frame(width: 420)
        }
      }
      func textFields(_ view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).map { [$0] } ?? []
        return own + view.subviews.flatMap(textFields)
      }

      let model = Model()
      let host = NSHostingView(rootView: Harness(model: model))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 400), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      let field = textFields(host).first { $0.isEditable }
      #expect(field != nil)

      // A later statement streams in after the field.
      model.response += "\nnote = TextContent(\"Saved drafts appear here.\")"
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      #expect(textFields(host).first { $0.isEditable } === field)

      // Typing writes $name, which re-evaluates the tree.
      field?.stringValue = "Ada"
      field?.sendAction(field?.action, to: field?.target)
      NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      #expect(model.state["$name"] == "Ada")
      #expect(textFields(host).first { $0.isEditable } === field)
    }

    /// A finished response inside a stack (a restored chat message) must render
    /// even though its text never changes after the view appears.
    @Test func rendersAFinishedResponseNestedInAStack() {
      let input = Self.examples[1].input
      let host = NSHostingView(
        rootView: VStack(alignment: .leading) {
          Text("Earlier message")
          OpenUIRenderer(response: input, library: OpenUIChatLibrary.library)
        }
        .frame(width: 420))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 600), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      #expect(host.fittingSize.height > 400, "rendered \(host.fittingSize)")
    }

    /// The response shows on the very first layout, before any onChange runs.
    /// A renderer in a lazy stack is rebuilt each time it scrolls back into
    /// view; if it came back empty and then grew, the stack would keep
    /// re-placing rows.
    @Test func rendersOnTheFirstFrame() {
      let host = NSHostingView(
        rootView: OpenUIRenderer(
          response: Self.examples[1].input, library: OpenUIChatLibrary.library
        )
        .frame(width: 420))
      #expect(host.fittingSize.height > 400, "first frame was \(host.fittingSize)")
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

@Suite struct CitationTests {
  @Test func splitsLikeRemarkCitations() {
    #expect(
      CitedMarkdown.segments("Big [1][2] news [3]. End")
        == [.text("Big "), .citation([1, 2]), .text("news "), .citation([3]), .text(". End")])
    #expect(CitedMarkdown.segments("No citations") == [.text("No citations")])
    #expect(CitedMarkdown.segments("[1] [2]") == [.citation([1, 2])])
  }
}

@MainActor
@Suite struct MarkdownTests {
  @Test func parsesMathAndTables() {
    let blocks = MarkdownBlocks.parse(
      "Intro\n$$\nA = P(1 + r)^n\n$$\n| a | b |\n|---|:-:|\n| 1 | 2 |\nAfter $$x$$")
    #expect(
      blocks == [
        .paragraph("Intro"), .math("A = P(1 + r)^n"),
        .table(header: ["a", "b"], rows: [["1", "2"]]),
        .paragraph("After $$x$$"),
      ])
    #expect(MarkdownBlocks.parse("$$E = mc^2$$") == [.math("E = mc^2")])
    // Without a separator row it's just text.
    #expect(MarkdownBlocks.parse("| not | a table |") == [.paragraph("| not | a table |")])
  }

  @Test func onlyDoubleTildesStrikeThrough() {
    let lone = InlineMarkdown.attributed("about ~$5K and ~4 days")
    #expect(String(lone.characters) == "about ~$5K and ~4 days")
    let double = InlineMarkdown.attributed("~~gone~~")
    #expect(String(double.characters) == "gone")
  }

  @Test func scatterDomainPadsLikeReactUI() {
    #expect(ScatterChartView.domain([150, 190]) == 146...194)
    #expect(ScatterChartView.domain([1, 5]) == 0.6...5.4)
    #expect(ScatterChartView.domain([]) == 0...100)
  }
}

/// Mirrors react-ui's paletteUtils tests.
@Suite struct ChartPaletteTests {
  let ramp = ChartPalette.ocean

  @Test func picksFromTheMiddleOutwards() {
    #expect(ChartPalette.colors(1) == [ramp[5]])
    #expect(ChartPalette.colors(2) == [ramp[4], ramp[6]])
    #expect(ChartPalette.colors(3) == [ramp[4], ramp[5], ramp[6]])
    #expect(ChartPalette.colors(5) == Array(ramp[3...7]))
  }

  @Test func usesTheThemePaletteAndFallsBackWhenEmpty() {
    let pastel: [Color] = [.pink, .mint, .yellow]
    #expect(ChartPalette.colors(3, pastel) == pastel)
    #expect(ChartPalette.colors(2, [.pink, .mint]) == [.pink, .mint])
    #expect(ChartPalette.colors(1, []) == [ramp[5]])
  }

  @Test func neverIndexesOutOfBounds() {
    for size in 1...12 {
      let palette = (0..<size).map { Color(white: Double($0) / 12) }
      for count in 1...40 {
        #expect(ChartPalette.colors(count, palette).count == count)
      }
    }
  }
}

/// The slider's range logic, against react-ui's SliderBlock.
@MainActor
@Suite struct SliderTests {
  @Test func snapsToStepsWithinBounds() {
    #expect(RangeSlider.snap(23, bounds: 0...100, step: 5) == 25)
    #expect(RangeSlider.snap(-7, bounds: 0...100, step: 5) == 0)
    #expect(RangeSlider.snap(140, bounds: 0...100, step: 5) == 100)
    #expect(RangeSlider.snap(12.4, bounds: 10...20, step: 0.5) == 12.5)
  }

  @Test func reportsReactUIErrors() {
    #expect(SliderView.errors([20, 80], minimum: 0, maximum: 100) == ["", ""])
    #expect(
      SliderView.errors([120], minimum: 0, maximum: 100) == ["Value must be between 0 and 100"])
    #expect(
      SliderView.errors([90, 10], minimum: 0, maximum: 100) == ["Min must be less than max", ""])
    #expect(SliderView.errors([.nan], minimum: 0, maximum: 100) == ["Invalid number"])
  }
}

/// The highlighter's token kinds, standing in for Prism's.
@Suite struct SyntaxHighlighterTests {
  func kinds(_ code: String, _ language: String) -> [String: SyntaxHighlighter.Token] {
    var kinds: [String: SyntaxHighlighter.Token] = [:]
    for (text, token) in SyntaxHighlighter.tokenize(code, language: language)
    where !text.trimmingCharacters(in: .whitespaces).isEmpty {
      kinds[text] = token
    }
    return kinds
  }

  @Test func keepsTheSourceIntact() {
    for (code, language) in [
      ("const total = items.map(x => x * 2) // twice\n", "ts"),
      ("def f(x):\n    \"\"\"doc\"\"\"\n    return x  # done", "python"),
      ("{\"a\": [1, true, null]}", "json"), ("<a href=\"/x\">Hi</a>", "html"),
      ("SELECT name FROM users WHERE id = 3", "sql"), ("let s = \"unfinished", "swift"),
    ] {
      let joined = SyntaxHighlighter.tokenize(code, language: language).map(\.0).joined()
      #expect(joined == code)
    }
  }

  @Test func classifiesTokensLikePrism() {
    let ts = kinds("import { x } from \"y\"\nconst total = sum(3.5) // note", "ts")
    #expect(ts["import"] == .control)
    #expect(ts["const"] == .keyword)
    #expect(ts["\"y\""] == .string)
    #expect(ts["sum"] == .function)
    #expect(ts["3.5"] == .number)
    #expect(ts["// note"] == .comment)
    #expect(ts["total"] == .plain)

    let python = kinds("def greet(name):\n    return None  # nothing", "python")
    #expect(python["def"] == .keyword)
    #expect(python["greet"] == .function)
    #expect(python["return"] == .control)
    #expect(python["None"] == .constant)
    #expect(python["# nothing"] == .comment)

    let json = kinds("{\"name\": \"Ada\", \"age\": 36, \"ok\": true}", "json")
    #expect(json["\"name\""] == .property)
    #expect(json["\"Ada\""] == .string)
    #expect(json["36"] == .number)
    #expect(json["true"] == .constant)

    let html = kinds("<a href=\"/x\">Hi</a>", "html")
    #expect(html["<a"] == .tag)
    #expect(html["href"] == .attribute)
    #expect(html["\"/x\""] == .string)

    #expect(kinds("SELECT id FROM t", "sql")["SELECT"] == .keyword)
  }

  @Test func colorsPlainWordsPerLanguage() {
    let dark = SyntaxHighlighter.Theme.darkPlus
    #expect(dark.color(.plain, language: "ts") != dark.color(.plain, language: "python"))
    #expect(dark.color(.punctuation, language: "ts") == dark.plain)
  }
}

@MainActor
@Suite struct MarkdownCodeAndImageTests {
  @Test func keepsTheFenceLanguageAndTrims() {
    #expect(
      MarkdownBlocks.parse("```swift\nlet x = 1\n\n```")
        == [.code(language: "swift", "let x = 1")])
    #expect(MarkdownBlocks.parse("```\nplain\n```") == [.code(language: nil, "plain")])
  }

  @Test func readsImageLines() {
    #expect(
      MarkdownBlocks.parse("Intro\n![A lake](https://x.test/l.jpg \"Lake\")")
        == [.paragraph("Intro"), .image(alt: "A lake", url: "https://x.test/l.jpg")])
    // Inline in a sentence it stays part of the paragraph.
    #expect(
      MarkdownBlocks.parse("See ![a](https://x.test/a.png) here")
        == [.paragraph("See ![a](https://x.test/a.png) here")])
  }
}

@Suite struct GalleryMosaicTests {
  /// The frames tile the gallery like react-ui's grid templates: inside the
  /// bounds, no overlaps, and the first image the largest.
  @Test(arguments: [false, true], 1...5)
  func tilesLikeReactUI(narrow: Bool, count: Int) {
    let width: CGFloat = narrow ? 360 : 700
    let bounds = CGRect(
      x: 0, y: 0, width: width, height: GalleryMosaic.height(width: width, count: count))
    let frames = GalleryMosaic.frames(count: count, in: bounds)
    #expect(frames.count == count)
    for (index, frame) in frames.enumerated() {
      #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
      for other in frames[(index + 1)...] {
        #expect(frame.intersection(other).width < 0.5 || frame.intersection(other).height < 0.5)
      }
      #expect(frame.width * frame.height <= frames[0].width * frames[0].height + 0.5)
    }
    // Nothing left uncovered but the gaps.
    let area = frames.reduce(0) { $0 + $1.width * $1.height }
    #expect(area > bounds.width * bounds.height * 0.9)
  }

  @Test func usesReactUITemplates() {
    // Five or more, wide: 2fr 1fr 1fr with the first image down both rows.
    let wide = GalleryMosaic.frames(count: 5, in: CGRect(x: 0, y: 0, width: 708, height: 376))
    #expect(wide[0] == CGRect(x: 0, y: 0, width: 346, height: 376))
    #expect(wide[1] == CGRect(x: 354, y: 0, width: 173, height: 184))
    #expect(wide[4] == CGRect(x: 535, y: 192, width: 173, height: 184))
    // Narrow: two on top, three below.
    let narrow = GalleryMosaic.frames(count: 5, in: CGRect(x: 0, y: 0, width: 368, height: 288))
    #expect(narrow[0].width == narrow[1].width)
    #expect(narrow[2].minY == narrow[3].minY && narrow[3].minY == narrow[4].minY)
    #expect(GalleryMosaic.height(width: 1200, count: 5) == GalleryMosaic.maxHeight)
  }
}
