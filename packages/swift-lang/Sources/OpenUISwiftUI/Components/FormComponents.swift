import OpenUILang
import SwiftUI

// MARK: - Form

struct FormView: View {
  let props: ComponentProps
  @State private var validation = FormValidation()
  @Environment(\.openUITheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing + 4) {
      OpenUINode(props["fields"])
      OpenUINode(props["buttons"])
    }
    .environment(\.openUIFormName, props.string("name"))
    .environment(validation)
  }
}

struct FormControlView: View {
  let props: ComponentProps
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let input = props.children("input").first
    let fieldName = input?.string("name")
    let required = input?["rules"]["required"] == true
    VStack(alignment: .leading, spacing: 6) {
      Text(props.text("label") + (required ? "*" : "")).font(.subheadline.weight(.medium))
      OpenUINode(props["input"])
      if let fieldName, let error = validation?.error(for: fieldName) {
        Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
      } else if let hint = props.string("hint"), !hint.isEmpty {
        Text(hint).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct LabelView: View {
  let props: ComponentProps

  var body: some View {
    Text(props.text("text")).font(.subheadline.weight(.medium))
  }
}

/// The field a form component reads and writes, plus its validation rules.
private struct FieldContext {
  let field: StateField
  let rules: [ParsedRule]
  let form: String?

  @MainActor
  init(_ props: ComponentProps, context: OpenUIContext, form: String?) {
    self.field = context.stateField(name: props.text("name"), binding: props["value"], form: form)
    self.rules = parseStructuredRules(props["rules"])
    self.form = form
  }
}

// MARK: - Text input

struct InputView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let text = Binding<String>(
      get: { displayText(state.field.value) },
      set: { newValue in
        state.field.setValue(.string(newValue))
        if !state.rules.isEmpty { validation?.clearError(state.field.name) }
      })
    Group {
      if props.string("type") == "password" {
        SecureField(props.text("placeholder"), text: text)
      } else {
        TextField(props.text("placeholder"), text: text)
          #if os(iOS)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalization)
          #endif
      }
    }
    .textFieldStyle(.plain)
    .fieldSurface()
    .disabled(context.isStreaming)
    .onSubmit {
      if !state.rules.isEmpty {
        validation?.validateField(state.field.name, value: state.field.value, rules: state.rules)
      }
    }
    .formField(state.field.name, rules: state.rules, value: state.field.value)
  }

  #if os(iOS)
    private var keyboard: UIKeyboardType {
      switch props.string("type") {
      case "email": return .emailAddress
      case "url": return .URL
      case "number": return .decimalPad
      default: return .default
      }
    }

    private var autocapitalization: TextInputAutocapitalization {
      ["email", "url"].contains(props.string("type") ?? "") ? .never : .sentences
    }
  #endif
}

struct TextAreaView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let rows = max(Int(props.number("rows") ?? 3), 1)
    TextField(
      props.text("placeholder"),
      text: Binding(
        get: { displayText(state.field.value) },
        set: { newValue in
          state.field.setValue(.string(newValue))
          if !state.rules.isEmpty { validation?.clearError(state.field.name) }
        }),
      axis: .vertical
    )
    .lineLimit(rows...max(rows, 12))
    .textFieldStyle(.plain)
    .fieldSurface()
    .disabled(context.isStreaming)
    .formField(state.field.name, rules: state.rules, value: state.field.value)
  }
}

// MARK: - Choices

struct SelectView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let items = props.children("items")
    let current = displayText(state.field.value)
    let label = items.first { $0.text("value") == current }?.text("label")
    // A full-width field like react-ui's select, opening a native menu.
    Menu {
      Picker(
        props.text("placeholder"),
        selection: Binding<String>(
          get: { current },
          set: { newValue in
            state.field.setValue(.string(newValue))
            if !state.rules.isEmpty {
              validation?.validateField(
                state.field.name, value: .string(newValue), rules: state.rules)
            }
          })
      ) {
        ForEach(items.indices, id: \.self) { index in
          Text(items[index].text("label")).tag(items[index].text("value"))
        }
      }
      .pickerStyle(.inline)
    } label: {
      HStack {
        Text(label ?? props.string("placeholder") ?? "Select…")
          .foregroundStyle(label == nil ? .secondary : .primary)
        Spacer()
        Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .fieldSurface(border: theme.border)
      .contentShape(Rectangle())
    }
    .menuIndicator(.hidden)
    .buttonStyle(.plain)
    .disabled(context.isStreaming)
    .formField(state.field.name, rules: state.rules, value: state.field.value)
  }
}

struct SelectItemView: View {
  let props: ComponentProps

  var body: some View {
    Text(props.text("label"))
  }
}

struct RadioGroupView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let selected =
      state.field.value.isNullish ? props.text("defaultValue") : displayText(state.field.value)
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(props.children("items").enumerated()), id: \.offset) { _, item in
        let value = item.text("value")
        Button {
          state.field.setValue(.string(value))
          if !state.rules.isEmpty {
            validation?.validateField(state.field.name, value: .string(value), rules: state.rules)
          }
        } label: {
          OptionRow(
            symbol: value == selected ? "largecircle.fill.circle" : "circle",
            label: item.text("label"), description: item.text("description"))
        }
        .buttonStyle(.plain)
      }
    }
    .disabled(context.isStreaming)
    .formField(state.field.name, rules: state.rules, value: state.field.value)
  }
}

struct RadioItemView: View {
  let props: ComponentProps

  var body: some View {
    OptionRow(symbol: "circle", label: props.text("label"), description: props.text("description"))
  }
}

/// A group of named booleans stored as one `{ name: Bool }` record, shared by
/// check boxes and switches. Unset items fall back to `defaultChecked`.
private struct BooleanGroup: View {
  let props: ComponentProps
  let style: Style
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  enum Style { case checkbox, toggle }

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let items = props.children("items")
    let stored = state.field.value.objectValue ?? OpenUIObject()
    let aggregate = OpenUIObject(
      items.map { item in
        let name = item.text("name")
        let value = stored[name]?.boolValue ?? item.bool("defaultChecked") ?? false
        return (name, OpenUIValue.bool(value))
      })
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        let name = item.text("name")
        let isOn = aggregate[name]?.boolValue ?? false
        let toggle = {
          var next = aggregate
          next[name] = .bool(!isOn)
          state.field.setValue(.object(next))
          if !state.rules.isEmpty {
            validation?.validateField(state.field.name, value: .object(next), rules: state.rules)
          }
        }
        switch style {
        case .checkbox:
          Button(action: toggle) {
            OptionRow(
              symbol: isOn ? "checkmark.square.fill" : "square", label: item.text("label"),
              description: item.text("description"))
          }
          .buttonStyle(.plain)
        case .toggle:
          // The switch leads and the text follows, as in react-ui's SwitchItem.
          HStack(alignment: .top, spacing: 8) {
            Toggle(item.text("label"), isOn: Binding(get: { isOn }, set: { _ in toggle() }))
              .toggleStyle(.switch)
              .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
              Text(item.text("label"))
              if let description = item.string("description"), !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .disabled(context.isStreaming)
    .formField(state.field.name, rules: state.rules, value: state.field.value)
  }
}

struct CheckBoxGroupView: View {
  let props: ComponentProps
  var body: some View { BooleanGroup(props: props, style: .checkbox) }
}

struct SwitchGroupView: View {
  let props: ComponentProps
  var body: some View {
    BooleanGroup(props: props, style: .toggle).surface(props.string("variant") ?? "clear")
  }
}

struct CheckBoxItemView: View {
  let props: ComponentProps
  var body: some View {
    OptionRow(
      symbol: props.bool("defaultChecked") == true ? "checkmark.square.fill" : "square",
      label: props.text("label"), description: props.text("description"))
  }
}

struct SwitchItemView: View {
  let props: ComponentProps
  var body: some View {
    Toggle(props.text("label"), isOn: .constant(props.bool("defaultChecked") ?? false))
      .toggleStyle(.switch)
      .disabled(true)
  }
}

/// A selectable row: indicator symbol, label and optional description.
private struct OptionRow: View {
  let symbol: String
  let label: String
  let description: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: symbol).foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
        if !description.isEmpty {
          Text(description).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
  }
}

// MARK: - Date and slider

/// Dates are stored as `yyyy-MM-dd` strings; a range as `{ from, to }`.
private let dayFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter
}()

struct DatePickerView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let isRange = props.string("mode") == "range"
    if state.field.value.isNullish {
      // Nothing is picked until the user picks it, so the form can't submit a
      // date the user never chose.
      Button {
        let today = OpenUIValue.string(dayFormatter.string(from: Date()))
        set(state, isRange ? .object(["from": today, "to": today]) : today)
      } label: {
        HStack {
          Text(isRange ? "Select a range" : "Select a date").foregroundStyle(.secondary)
          Spacer()
          Image(systemName: "calendar").foregroundStyle(.secondary)
        }
        .fieldSurface(border: theme.border)
      }
      .buttonStyle(.plain)
      .disabled(context.isStreaming)
      .formField(state.field.name, rules: state.rules, value: state.field.value)
    } else if isRange {
      VStack(alignment: .leading, spacing: 6) {
        rangePicker("From", key: "from", state)
        rangePicker("To", key: "to", state)
      }
      .formField(state.field.name, rules: state.rules, value: state.field.value)
    } else {
      DatePicker(
        "",
        selection: Binding(
          get: { state.field.value.stringValue.flatMap(dayFormatter.date(from:)) ?? Date() },
          set: { set(state, .string(dayFormatter.string(from: $0))) }),
        displayedComponents: .date
      )
      .labelsHidden()
      .disabled(context.isStreaming)
      .formField(state.field.name, rules: state.rules, value: state.field.value)
    }
  }

  private func rangePicker(_ label: String, key: String, _ state: FieldContext) -> some View {
    let range = state.field.value.objectValue ?? OpenUIObject()
    return DatePicker(
      label,
      selection: Binding(
        get: { range[key]?.stringValue.flatMap(dayFormatter.date(from:)) ?? Date() },
        set: { date in
          var next = range
          next[key] = .string(dayFormatter.string(from: date))
          set(state, .object(next))
        }),
      displayedComponents: .date
    )
    .disabled(context.isStreaming)
  }

  private func set(_ state: FieldContext, _ value: OpenUIValue) {
    state.field.setValue(value)
    if !state.rules.isEmpty {
      validation?.validateField(state.field.name, value: value, rules: state.rules)
    }
  }
}

struct SliderView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let state = FieldContext(props, context: context, form: form)
    let minimum = props.number("min") ?? 0
    let maximum = max(props.number("max") ?? 100, minimum)
    let step = props.string("variant") == "discrete" ? max(props.number("step") ?? 1, 0.0001) : nil
    let stored = state.field.value.isNullish ? props["defaultValue"] : state.field.value
    let values = (stored.arrayValue ?? []).compactMap(\.numberValue)
    let current = values.isEmpty ? [minimum] : values
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(props.string("label") ?? state.field.name).font(.subheadline)
        Spacer()
        Text(current.map(jsNumberToString).joined(separator: " – "))
          .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
      }
      ForEach(current.indices, id: \.self) { index in
        let binding = Binding<Double>(
          get: { min(max(current[index], minimum), maximum) },
          set: { newValue in
            var next = current
            next[index] = newValue
            state.field.setValue(.array(next.map { .number($0) }))
            if !state.rules.isEmpty {
              validation?.validateField(
                state.field.name, value: .number(next[0]), rules: state.rules)
            }
          })
        if let step {
          Slider(value: binding, in: minimum...maximum, step: step)
        } else {
          Slider(value: binding, in: minimum...maximum)
        }
      }
      HStack {
        Text(compactNumber(minimum))
        Spacer()
        Text(compactNumber(maximum))
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
    .disabled(context.isStreaming)
    .formField(state.field.name, rules: state.rules, value: state.field.value)
  }
}

// MARK: - Buttons

struct ButtonView: View {
  let props: ComponentProps
  @Environment(\.openUIButtonFillsWidth) private var fillsWidth
  @Environment(OpenUIContext.self) private var context
  @Environment(\.openUIFormName) private var form
  @Environment(FormValidation.self) private var validation: FormValidation?

  var body: some View {
    let label = props.text("label")
    let variant = props.string("variant") ?? "primary"
    let destructive = props.string("type") == "destructive"
    Button(role: destructive ? .destructive : nil) {
      let action = props["action"]
      if let validation, variant == "primary", !shouldSkipValidation(action) {
        guard validation.validateForm() else { return }
      }
      context.triggerAction(label, form: form, action: action.isNullish ? nil : action)
    } label: {
      Text(label).frame(maxWidth: fillsWidth ? .infinity : nil)
    }
    .modifier(ButtonVariant(variant: variant))
    .controlSize(controlSize)
    .disabled(context.isStreaming)
  }

  /// Primary buttons validate the form first, unless their action plan only
  /// has steps that don't submit anything (no @ToAssistant, no mutation).
  private func shouldSkipValidation(_ action: OpenUIValue) -> Bool {
    guard case .actionPlan(let plan) = action else { return false }
    return !plan.steps.contains { step in
      switch step {
      case .continueConversation: return true
      case .run(_, let refType): return refType == .mutation
      default: return false
      }
    }
  }

  private var controlSize: ControlSize {
    switch props.string("size") {
    case "extra-small": return .mini
    case "small": return .small
    case "large": return .large
    default: return .regular
    }
  }
}

private struct ButtonFillsWidthKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Whether buttons stretch to the available width, like a card footer's.
  var openUIButtonFillsWidth: Bool {
    get { self[ButtonFillsWidthKey.self] }
    set { self[ButtonFillsWidthKey.self] = newValue }
  }
}

private struct ButtonVariant: ViewModifier {
  let variant: String

  func body(content: Content) -> some View {
    switch variant {
    case "secondary": content.buttonStyle(.bordered)
    case "tertiary", "ghost": content.buttonStyle(.borderless)
    default: content.buttonStyle(.borderedProminent)
    }
  }
}

struct ButtonsView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let buttons = props.array("buttons")
    if props.string("direction") == "column" {
      VStack(alignment: .leading, spacing: theme.compactSpacing) {
        ForEach(NodeItem.list(buttons)) { OpenUINode($0.value) }
      }
    } else {
      FlowLayout(spacing: theme.compactSpacing) {
        ForEach(NodeItem.list(buttons)) { OpenUINode($0.value) }
      }
    }
  }
}

/// react-ui's slider labels: 1000 and up in short compact notation ("10k",
/// "2.5m"), smaller numbers as JavaScript prints them.
func compactNumber(_ number: Double) -> String {
  guard number >= 1000 else { return jsNumberToString(number) }
  return number.formatted(
    .number.notation(.compactName).locale(Locale(identifier: "en_US"))
  ).lowercased()
}

/// react-ui's field look: a faint fill, a 1pt border and 10pt corners.
private struct FieldSurface: ViewModifier {
  var border: Color?
  @Environment(\.openUITheme) private var theme

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(theme.subtleSurface, in: RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10).strokeBorder(border ?? theme.interactiveBorder))
  }
}

extension View {
  fileprivate func fieldSurface(border: Color? = nil) -> some View {
    modifier(FieldSurface(border: border))
  }
}
