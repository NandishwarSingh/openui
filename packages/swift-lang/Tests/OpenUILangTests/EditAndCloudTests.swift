import CryptoKit
import Foundation
import Testing

@testable import OpenUILang

/// `mergeStatements` must match lang-core's edit-mode merge.
@Suite struct MergeConformanceTests {
  @Test(arguments: FixtureCase.all("merge"))
  func merge(_ fixture: FixtureCase) {
    let value = fixture.value
    let merged = mergeStatements(
      value["existing"].stringValue!, value["patch"].stringValue!,
      rootId: value["rootId"].stringValue ?? "root")
    let expected = value["expected"].stringValue!
    #expect(merged == expected, "\(fixture.name): \(firstLineDifference(merged, expected) ?? "")")
  }
}

/// `generateCloudConfig` must produce the same config block, or the same
/// error, as `generateSystemPrompt({ cloud: true })`.
@Suite struct CloudConfigConformanceTests {
  static let fixtures = Fixtures.load("cloud")

  static var cases: [FixtureCase] {
    (fixtures["cases"].arrayValue ?? []).map {
      FixtureCase(name: $0["name"].stringValue ?? "?", value: $0)
    }
  }

  @Test(arguments: cases)
  func config(_ fixture: FixtureCase) {
    let spec = fixture.value["spec"]
    let result = Result {
      try generateCloudConfig(
        library: spec["library"], promptOptions: Self.promptOptions(spec["promptOptions"]),
        instructions: spec["instructions"].stringValue)
    }
    switch result {
    case .success(let config):
      #expect(config == fixture.value["expected"].stringValue, "\(fixture.name)")
    case .failure(let error):
      #expect("\(error)" == fixture.value["error"].stringValue, "\(fixture.name)")
    }
  }

  @Test func chatLibraryConfigMatchesLangCore() throws {
    // lang-core's config for openuiChatLibrary with its prompt options is
    // ~80 KB, so the fixture keeps its length and SHA-256.
    let chatOptions = FixtureCase.all("prompts").first { $0.name == "chat-options" }!.value["spec"]
    let library = Library(
      components: ChatComponents.all.map { ComponentDefinition($0, content: ()) }, root: "Card",
      componentGroups: ChatComponents.groups)
    let config = try library.cloudConfig(Self.promptOptions(chatOptions))

    let expected = Self.fixtures["chat"]
    #expect(Double(config.utf16.count) == expected["length"].numberValue)
    let digest = SHA256.hash(data: Data(config.utf8)).map { String(format: "%02x", $0) }.joined()
    #expect(digest == expected["sha256"].stringValue)
  }

  static func promptOptions(_ value: OpenUIValue) -> PromptOptions? {
    guard value.objectValue != nil else { return nil }
    let strings = { (key: String) in value[key].arrayValue?.compactMap(\.stringValue) }
    return PromptOptions(
      preamble: value["preamble"].stringValue, additionalRules: strings("additionalRules"),
      examples: strings("examples"), tools: strings("tools")?.map(ToolDescriptor.name),
      editMode: value["editMode"].boolValue)
  }
}
