/// What the parser and evaluator need to know about a component library.
public protocol ComponentLibrary {
  /// Positional parameters per component, compiled from the library schema.
  var paramMap: ParamMap { get }
  /// The root component, used to pick the entry statement.
  var rootName: String? { get }
  /// Whether a prop binds two-way to `$state` (lang-core's `reactive()`).
  func isReactiveProp(_ component: String, _ prop: String) -> Bool
}

/// The framework-independent runtime behind a renderer: streaming parse,
/// state store, prop evaluation, form fields and action execution. Ports the
/// logic of react-lang's `useOpenUIState`; UI layers observe it and render.
@MainActor
public final class OpenUIRuntime {
  public let library: any ComponentLibrary
  public let store = Store()
  public let queries: QueryManager

  /// Called for actions the host handles (continue the conversation, open a URL, custom).
  public var onAction: ((ActionEvent) -> Void)?
  /// Called when state changes after initialization.
  public var onStateUpdate: ((OpenUIObject) -> Void)?

  public private(set) var parseResult: ParseResult?
  public private(set) var isStreaming = false

  private let streamParser: StreamParser
  private let initialState: OpenUIObject?
  private var storeInitKey: String?
  private var initializingStore = false
  private var unsubscribe: (() -> Void)?

  public init(
    library: some ComponentLibrary, initialState: OpenUIObject? = nil,
    toolProvider: (any ToolProvider)? = nil
  ) {
    self.library = library
    self.initialState = initialState
    self.streamParser = StreamParser(library.paramMap, rootName: library.rootName)
    self.queries = QueryManager(toolProvider: toolProvider)
    unsubscribe = store.subscribe { [weak self] in
      guard let self, !self.initializingStore else { return }
      self.onStateUpdate?(self.store.snapshot)
    }
  }

  /// Stops query refreshes and drops listeners.
  public func dispose() {
    unsubscribe?()
    unsubscribe = nil
    queries.dispose()
  }

  // MARK: Parsing

  /// Feeds the latest full response text. Appended text parses incrementally.
  public func update(response: String?, isStreaming: Bool) {
    self.isStreaming = isStreaming
    guard let response, !response.isEmpty else {
      parseResult = nil
      return
    }
    parseResult = streamParser.set(response)
    initializeStoreIfNeeded()
    if !isStreaming { syncQueries() }
  }

  /// Seeds the store from `$state` declarations and `initialState` whenever
  /// either changes. Values the user already changed are kept.
  private func initializeStoreIfNeeded() {
    let declarations = parseResult?.stateDeclarations ?? OpenUIObject()
    let key =
      JSON.stringify(.object(declarations)) + "::"
      + (initialState.map { JSON.stringify(.object($0)) } ?? "")
    guard key != storeInitKey else { return }
    storeInitKey = key

    initializingStore = true
    defer { initializingStore = false }
    var bindingDefaults = OpenUIObject()
    for (key, value) in initialState ?? OpenUIObject() {
      if key.hasPrefix("$") {
        bindingDefaults[key] = value
      } else {
        store.set(key, value)
      }
    }
    store.initialize(defaults: declarations, persisted: bindingDefaults)
  }

  // MARK: Evaluation

  /// Reads state for expressions (form fields store `{ value, componentType }`)
  /// and Query/Mutation results as of now.
  public var evaluationContext: EvaluationContext {
    let results = queries.snapshot.results
    return EvaluationContext(
      getState: { [store] name in unwrapFieldValue(store.get(name)) },
      resolveRef: { name in results[name] ?? .null })
  }

  public var schemaContext: SchemaContext {
    SchemaContext(isReactiveProp: library.isReactiveProp)
  }

  /// The parsed root with every prop evaluated against the current state.
  public func evaluatedRoot() -> ElementNode? {
    guard let root = parseResult?.root else { return nil }
    return evaluateElementProps(root, evaluationContext, schemaContext)
  }

  // MARK: Fields

  public func fieldValue(form: String?, name: String) -> OpenUIValue {
    guard let form else { return unwrapFieldValue(store.get(name)) }
    guard case .object(let formData) = store.get(form) else { return .undefined }
    return unwrapFieldValue(formData[name] ?? .undefined)
  }

  public func setFieldValue(
    form: String?, componentType: String?, name: String, value: OpenUIValue,
    notifyHost: Bool = true
  ) {
    var wrapped: OpenUIObject = ["value": value]
    wrapped["componentType"] = componentType.map { .string($0) } ?? .undefined
    if let form {
      var formData = store.get(form).objectValue ?? OpenUIObject()
      formData[name] = .object(wrapped)
      store.set(form, .object(formData))
    } else {
      store.set(name, .object(wrapped))
    }
    if notifyHost { onStateUpdate?(store.snapshot) }
  }

  /// The field a component reads and writes for `name`, honouring `$state` bindings.
  public func stateField(name: String, binding: OpenUIValue, form: String?) -> StateField {
    resolveStateField(
      name: name, bindingValue: binding, store: store, evaluationContext: evaluationContext,
      getField: { [weak self] field in self?.fieldValue(form: form, name: field) ?? .undefined },
      setField: { [weak self] field, value in
        self?.setFieldValue(form: form, componentType: nil, name: field, value: value)
      })
  }

  /// The state sent along with an action: the named form, or everything.
  public func formPayload(_ form: String?) -> OpenUIObject {
    if let form, case .object = store.get(form) { return [form: store.get(form)] }
    return store.snapshot
  }

  // MARK: Actions

  /// Runs a component's action. `action` is an evaluated `Action([...])` plan,
  /// a legacy `{ type, params }` object, or nil (continue the conversation
  /// with the label as the message).
  public func triggerAction(_ userMessage: String, form: String? = nil, action: OpenUIValue? = nil)
    async
  {
    let payload = formPayload(form)

    if case .object(let legacy)? = action {
      var params = legacy["params"]?.objectValue ?? OpenUIObject()
      if let url = legacy["url"], !url.isNullish { params["url"] = url }
      if let context = legacy["context"], !context.isNullish { params["context"] = context }
      let type = legacy["type"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
      onAction?(
        ActionEvent(
          type: type ?? BuiltinActionType.continueConversation, params: params,
          humanFriendlyMessage: userMessage, formState: payload, formName: form))
      return
    }

    guard case .actionPlan(let plan)? = action else {
      onAction?(
        ActionEvent(
          type: BuiltinActionType.continueConversation, humanFriendlyMessage: userMessage,
          formState: payload, formName: form))
      return
    }

    for step in plan.steps {
      switch step {
      case .run(let statementId, let refType):
        if refType == .mutation {
          let argsAST = parseResult?.mutationStatements.first { $0.statementId == statementId }?
            .argsAST
          let args = argsAST.map { evaluate($0, evaluationContext) }?.objectValue ?? OpenUIObject()
          // A failed mutation halts the remaining steps.
          guard await queries.fireMutation(statementId, args: args) else { return }
        } else {
          queries.invalidate([statementId])
        }
      case .continueConversation(let message, let context):
        onAction?(
          ActionEvent(
            type: BuiltinActionType.continueConversation,
            params: context.map { ["context": .string($0)] } ?? OpenUIObject(),
            humanFriendlyMessage: message, formState: payload, formName: form))
      case .openUrl(let url):
        onAction?(
          ActionEvent(
            type: BuiltinActionType.openUrl, params: ["url": .string(url)],
            humanFriendlyMessage: "", formState: payload, formName: form))
      case .set(let target, let valueAST):
        store.set(target, evaluate(valueAST, evaluationContext))
      case .reset(let targets):
        let declarations = parseResult?.stateDeclarations ?? OpenUIObject()
        for target in targets {
          let declared = declarations[target] ?? .null
          store.set(target, declared.isNullish ? .null : declared)
        }
      }
    }
  }

  // MARK: Queries

  /// Evaluates Query/Mutation statements against the current state and hands
  /// them to the query manager. Runs once the stream has finished.
  public func syncQueries() {
    guard let result = parseResult, !isStreaming else { return }
    let context = evaluationContext
    let snapshot = store.snapshot
    queries.evaluateQueries(
      result.queryStatements.map { query in
        var deps = OpenUIObject()
        for dep in query.deps ?? [] { deps[dep] = snapshot[dep] ?? .undefined }
        return QueryNode(
          statementId: query.statementId,
          toolName: query.toolAST.map { evaluate($0, context) }?.stringValue ?? "",
          args: query.argsAST.map { evaluate($0, context) } ?? .null,
          defaults: query.defaultsAST.map { evaluate($0, context) } ?? .null,
          refreshInterval: query.refreshAST.map { evaluate($0, context) }?.numberValue,
          deps: deps.isEmpty ? nil : deps, complete: query.complete)
      })
    queries.registerMutations(
      result.mutationStatements.map { mutation in
        MutationNode(
          statementId: mutation.statementId,
          toolName: mutation.toolAST.map { evaluate($0, context) }?.stringValue ?? "")
      })
  }
}

/// Form fields store `{ value, componentType }`; expressions see the raw value.
func unwrapFieldValue(_ value: OpenUIValue) -> OpenUIValue {
  if case .object(let object) = value, let inner = object["value"] { return inner }
  return value
}
