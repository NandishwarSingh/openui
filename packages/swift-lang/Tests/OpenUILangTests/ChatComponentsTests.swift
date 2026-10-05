import Testing

@testable import OpenUILang

/// The chat component schemas must match openuiChatLibrary's Zod schemas, so
/// one backend prompt drives both the web and native renderers.
@Suite struct ChatComponentsTests {
  static let tsDefs = Fixtures.schemas["chat"]["schema"]["$defs"]
  static let tsSpec = Fixtures.load("chat-spec")

  @Test(arguments: ChatComponents.all.map(\.name))
  func matchesOpenUIChatLibrary(_ name: String) {
    let schema = ChatComponents.all.first { $0.name == name }!
    let expected = Self.tsDefs[name]
    let diff = firstDifference(normalized(schema.jsonSchema), normalized(expected))
    #expect(diff == nil, "\(name): \(diff ?? "")")
    // Property order is positional-argument order, so it must match exactly.
    #expect(
      schema.jsonSchema["properties"].objectValue?.keys == expected["properties"].objectValue?.keys)
    #expect(schema.signature == Self.tsSpec["components"][name]["signature"].stringValue)
  }

  @Test func coversEveryComponentInLibraryOrder() {
    #expect(ChatComponents.all.map(\.name) == Self.tsDefs.objectValue?.keys)
  }

  @Test func bindingsMatchReactiveProps() {
    let reactive = Fixtures.schemas["chat"]["reactive"].objectValue ?? OpenUIObject()
    for schema in ChatComponents.all {
      let expected = (reactive[schema.name]?.arrayValue ?? []).compactMap(\.stringValue)
      #expect(schema.props.filter(\.isBinding).map(\.name) == expected, "\(schema.name)")
    }
  }

  @Test func groupsMatchOpenUIChatLibrary() {
    let expected = (Self.tsSpec["componentGroups"].arrayValue ?? []).map { group in
      ComponentGroup(
        name: group["name"].stringValue ?? "",
        components: (group["components"].arrayValue ?? []).compactMap(\.stringValue),
        notes: group["notes"].arrayValue?.compactMap(\.stringValue))
    }
    #expect(ChatComponents.groups == expected)
  }

  @Test func chatLibraryPromptMatchesLangCore() {
    // The full chat prompt (no options) is one of the prompt fixtures.
    let fixture = FixtureCase.all("prompts").first { $0.name == "chat-default" }!
    let library = Library(
      components: ChatComponents.all.map { ComponentDefinition($0, content: ()) }, root: "Card",
      componentGroups: ChatComponents.groups)
    let prompt = library.prompt()
    let expected = fixture.value["expected"].stringValue!
    #expect(prompt == expected, "\(firstLineDifference(prompt, expected) ?? "")")
  }
}
