import OpenUISwiftUI
import PhotosUI
import SwiftUI

struct ChatView: View {
  let model: ChatModel
  @State private var draft = ""
  @State private var attachment: Data?
  @State private var atBottom = true
  @State private var viewport: CGFloat = 0
  @State private var viewportUpdate: Task<Void, Never>?
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // Not lazy. A lazy stack places its rows over several layout passes,
        // and inside an animated change (the scroll to the question, or the
        // keyboard closing) each pass stacks new frame animations on the
        // running ones until the main thread can't keep up: the app froze for
        // over a minute after a tapped follow-up. A chat is short enough to
        // lay out in full.
        VStack(alignment: .leading, spacing: 18) {
          if model.visibleMessages.isEmpty {
            EmptyStateView { model.send($0) }
          }
          ForEach(model.visibleMessages) { message in
            MessageRow(message: message, model: model, openURL: openURL)
              .id(message.id)
              // The latest answer gets at least a screen of room, so the
              // question above it can sit at the top while it streams.
              .frame(
                minHeight: message.id == model.visibleMessages.last?.id && message.role == .assistant
                  ? max(0, viewport - 140) : nil,
                alignment: .top)
              .transition(.opacity.combined(with: .offset(y: 12)))
          }
          // Visible only when scrolled to the end; drives the jump button.
          Color.clear.frame(height: 1).id("bottom")
            .onAppear { atBottom = true }
            .onDisappear { atBottom = false }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(16)
        .animation(.easeOut(duration: 0.25), value: model.visibleMessages.count)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(Pastel.background)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
        // The latest answer is sized from this, so take a new height only once
        // it settles. Following every frame of the keyboard or composer
        // animating resizes the answer while it scrolls into place, and those
        // animations pile up until the app freezes.
        viewportUpdate?.cancel()
        guard viewport > 0 else { return viewport = height }
        viewportUpdate = Task {
          try? await Task.sleep(for: .milliseconds(250))
          if !Task.isCancelled { viewport = height }
        }
      }
      #if DEBUG
        // `-scrollToEnd YES`: scrolls down once an answer finishes, for screenshots.
        .onChange(of: model.finishedCount) {
          guard UserDefaults.standard.bool(forKey: "scrollToEnd") else { return }
          Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 1.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
          }
        }
      #endif
      // When an answer starts, the question scrolls to the top and the answer
      // streams in below it. Nothing scrolls while it streams.
      .onChange(of: model.visibleMessages.count) {
        let messages = model.visibleMessages
        if messages.count >= 2, messages[messages.count - 1].role == .assistant {
          withAnimation(.easeOut(duration: 0.35)) {
            proxy.scrollTo(messages[messages.count - 2].id, anchor: .top)
          }
        }
      }
      .overlay(alignment: .bottom) {
        if !atBottom && !model.visibleMessages.isEmpty {
          Button {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
          } label: {
            Image(systemName: "arrow.down")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Pastel.accent)
              .frame(width: 34, height: 34)
              .background(Pastel.card, in: Circle())
              .overlay(Circle().strokeBorder(Pastel.hairline))
              .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
          }
          .buttonStyle(.plain)
          .padding(.bottom, 8)
          .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
      }
      .animation(.easeOut(duration: 0.2), value: atBottom)
    }
    .safeAreaInset(edge: .bottom) {
      Composer(model: model, draft: $draft, attachment: $attachment)
    }
    .navigationTitle(model.title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Pastel.background, for: .navigationBar)
    #endif
    .sensoryFeedback(.impact(weight: .light), trigger: model.sentCount)
    .sensoryFeedback(.success, trigger: model.finishedCount)
    .task {
      // Scripted runs for screenshots and videos: `-prompt "…"` sends a first message.
      if model.messages.isEmpty, let prompt = UserDefaults.standard.string(forKey: "prompt") {
        model.send(prompt)
      }
      #if DEBUG
        // `-followUp "…"` sends a second message once the first answer is in.
        if let followUp = UserDefaults.standard.string(forKey: "followUp") {
          while model.finishedCount == 0 { try? await Task.sleep(for: .milliseconds(200)) }
          try? await Task.sleep(for: .seconds(1))
          model.send(followUp)
        }
      #endif
    }
  }
}

/// The first screen of a new plan: a greeting and colored starting points.
private struct EmptyStateView: View {
  let send: (String) -> Void

  private struct Suggestion: Identifiable {
    var id: String { prompt }
    let symbol: String
    let title: String
    let prompt: String
    let tone: Pastel.Tone
  }

  private let suggestions = [
    Suggestion(
      symbol: "calendar", title: "My Saturday",
      prompt: "What does my Saturday look like, and what's the weather?", tone: Pastel.sky),
    Suggestion(
      symbol: "binoculars", title: "Things to see",
      prompt: "What's worth seeing near me this weekend? Show me photos.", tone: Pastel.mint),
    Suggestion(
      symbol: "fork.knife", title: "Brunch nearby",
      prompt: "Find a good brunch spot near me for Saturday morning", tone: Pastel.peach),
    Suggestion(
      symbol: "sparkles", title: "Plan the whole day",
      prompt: "Plan a relaxed Saturday around my calendar, with places, photos and travel times",
      tone: Pastel.lavender),
    Suggestion(
      symbol: "ticket", title: "Book a spot",
      prompt: "Find a place near me for Saturday afternoon and let me pay a deposit for it here",
      tone: Pastel.rose),
    Suggestion(
      symbol: "camera", title: "From a photo",
      prompt: "I want to show you a photo of an event poster and plan around it", tone: Pastel.butter),
  ]

  private var server = ServerStatus.shared

  init(send: @escaping (String) -> Void) { self.send = send }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if server.state == .unreachable {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "wifi.exclamationmark").foregroundStyle(Pastel.peach.ink)
          VStack(alignment: .leading, spacing: 4) {
            Text("Can't reach the Planner server").font(.subheadline.weight(.semibold))
            Text("Start it with `node server.mjs` on your Mac, or set its address in Settings.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          Button("Settings") { server.showingSettings = true }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Pastel.accent)
        }
        .padding(14)
        .background(Pastel.peach.fill, in: RoundedRectangle(cornerRadius: 14))
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Pastel.accent)
        Text("What are we planning?")
          .font(.largeTitle.weight(.bold))
        Text("Answers stream in as native views, built from your calendar, places nearby, photos and the forecast.")
          .foregroundStyle(.secondary)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
        ForEach(suggestions) { suggestion in
          Button {
            send(suggestion.prompt)
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              Image(systemName: suggestion.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(suggestion.tone.onSolid)
                .frame(width: 34, height: 34)
                .background(suggestion.tone.solid, in: RoundedRectangle(cornerRadius: 10))
              Text(suggestion.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
              Text(suggestion.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(suggestion.tone.fill, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.top, 20)
  }
}

/// The message field, with a photo attachment and a send/stop button.
private struct Composer: View {
  let model: ChatModel
  @Binding var draft: String
  @Binding var attachment: Data?
  @State private var showLibrary = false
  @State private var showCamera = false
  @State private var libraryItem: PhotosPickerItem?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let attachment {
        PhotoThumbnail(key: "attachment-\(attachment.hashValue)", side: 64) { attachment }
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(alignment: .topTrailing) {
            Button {
              withAnimation(.easeOut(duration: 0.2)) { self.attachment = nil }
            } label: {
              Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
          }
          .transition(.scale(scale: 0.8).combined(with: .opacity))
      }
      HStack(alignment: .bottom, spacing: 8) {
        Group {
          if CameraPicker.isAvailable {
            Menu {
              Button("Take Photo", systemImage: "camera") { showCamera = true }
              Button("Choose Photo", systemImage: "photo.on.rectangle") { showLibrary = true }
            } label: {
              attachLabel
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
          } else {
            Button { showLibrary = true } label: { attachLabel }
          }
        }
        .accessibilityLabel("Add photo")
        .buttonStyle(.plain)
        .fixedSize()
        TextField("Ask Planner", text: $draft, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...5)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(Pastel.card, in: RoundedRectangle(cornerRadius: 18))
          .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Pastel.hairline))
          .focused($focused)
          .onSubmit(submit)
        Button {
          if model.isStreaming { model.stop() } else { submit() }
        } label: {
          Image(systemName: model.isStreaming ? "stop.fill" : "arrow.up")
            .contentTransition(.symbolEffect(.replace))
            .font(.body.weight(.semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(Pastel.onAccent)
            .background(canSend || model.isStreaming ? Pastel.accent : Pastel.accent.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isStreaming ? "Stop" : "Send")
        .disabled(!model.isStreaming && !canSend)
      }
    }
    .frame(maxWidth: 760)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Pastel.background)
    .animation(.easeOut(duration: 0.2), value: attachment)
    .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
    .onChange(of: libraryItem) {
      guard let libraryItem else { return }
      Task {
        if let data = try? await libraryItem.loadTransferable(type: Data.self) {
          attachment = uploadJPEG(data)
        }
        self.libraryItem = nil
      }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $showCamera) {
        CameraPicker { attachment = uploadJPEG($0) }.ignoresSafeArea()
      }
    #endif
    #if DEBUG
      // `-typeFollowUp "…"`: once the first answer is in, does what a person
      // does: focuses the field (keyboard up), types, sends (keyboard down).
      .task {
        guard let text = UserDefaults.standard.string(forKey: "typeFollowUp") else { return }
        while model.finishedCount == 0 { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .seconds(2))
        focused = true
        try? await Task.sleep(for: .seconds(1.5))
        draft = text
        try? await Task.sleep(for: .seconds(0.5))
        submit()
      }
    #endif
  }

  private var attachLabel: some View {
    Image(systemName: "plus")
      .font(.body.weight(.semibold))
      .foregroundStyle(Pastel.lavender.onSolid)
      .frame(width: 36, height: 36)
      .background(Pastel.lavender.chip, in: Circle())
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespaces).isEmpty || attachment != nil
  }

  private func submit() {
    guard canSend else { return }
    model.send(draft, images: attachment.map { [$0] } ?? [])
    draft = ""
    attachment = nil
    // Make room for the answer.
    focused = false
  }
}

/// A user bubble, or an assistant response rendered by OpenUI on a card, with
/// its thinking, streaming and error states.
struct MessageRow: View {
  let message: ChatMessage
  let model: ChatModel
  let openURL: OpenURLAction
  /// Whether the response has a layout to show yet. Models often write their
  /// queries first, so text arrives a while before anything renders.
  @State private var hasLayout = false
  /// Whether the renderer has parsed the response at least once.
  @State private var parsed = false
  /// Tools that failed while loading this response's data.
  @State private var toolErrors: [OpenUIError] = []

  var body: some View {
    switch message.role {
    case .user:
      VStack(alignment: .trailing, spacing: 6) {
        ForEach(message.stored.images, id: \.self) { name in
          PhotoThumbnail(key: name, side: 180) { [model] in model.image(named: name) }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        if !message.stored.display.isEmpty {
          Text(message.stored.display)
            .foregroundStyle(Pastel.chipText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Pastel.lavender.chip, in: RoundedRectangle(cornerRadius: 18))
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.leading, 48)
    case .assistant:
      VStack(alignment: .leading, spacing: 12) {
        let program = Wire.program(message.stored.content)
        if message.isStreaming && !hasLayout && Self.looksLikeProgram(program) {
          ThinkingIndicator()
        }
        if !program.isEmpty && !Self.looksLikeProgram(program) {
          // A plain-text answer (react-ui shows these as markdown too).
          ProseView(text: program)
        } else if parsed && !hasLayout && !message.isStreaming && !program.isEmpty {
          // A program that never produced anything to show.
          ProseView(text: "That answer didn't come out right. Try asking again.")
            .foregroundStyle(.secondary)
        }
        if !message.stored.content.isEmpty && Self.looksLikeProgram(program) {
          OpenUIRenderer(
            response: Wire.program(message.stored.content), isStreaming: message.isStreaming,
            library: PlannerLibrary.library, initialState: message.state,
            toolProvider: PlannerTools(
              results: ToolResults(message.stored.toolResults ?? [:]) { [model, id = message.id] key, json in
                model.saveToolResult(json, for: key, of: id)
              }),
            queryLoader: ToolStatusChip(),
            onAction: { model.handle($0) { openURL($0) } },
            onStateUpdate: { model.updateState($0, of: message.id) },
            onParseResult: { result in
              if !parsed { parsed = true }
              let rendered = result?.root != nil
              if rendered != hasLayout { hasLayout = rendered }
            },
            onError: { errors in
              toolErrors = errors.filter { $0.source == .query || $0.source == .mutation }
            }
          )
          .environment(
            \.messageActions,
            MessageActions(
              messageID: message.id,
              sendPhoto: { [model] jpeg, text in model.send(text, images: [jpeg]) },
              reportPayment: { [model] receipt, description in
                model.reportPayment(receipt, for: description)
              }))
          if message.isStreaming && hasLayout { StreamingDot() }
          ForEach(Self.notes(toolErrors), id: \.self) { note in
            Label {
              Text(note).foregroundStyle(.secondary)
            } icon: {
              Image(systemName: "exclamationmark.circle").foregroundStyle(Pastel.peach.ink)
            }
            .font(.footnote)
          }
        }
        if let failure = message.stored.failure {
          HStack(spacing: 10) {
            Label(failure, systemImage: "exclamationmark.triangle")
              .font(.footnote).foregroundStyle(Pastel.peach.ink)
            Button("Retry") { model.retry() }
              .font(.footnote.weight(.semibold))
              .buttonStyle(.plain)
              .foregroundStyle(Pastel.accent)
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Pastel.card, in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Pastel.hairline))
    }
  }
}

extension MessageRow {
  /// Whether a response is an openui-lang program rather than plain text:
  /// fenced, or starting with a statement (`name = ...`).
  static func looksLikeProgram(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.hasPrefix("```") || hasLangSyntax(trimmed) { return true }
    let firstLine = trimmed.prefix { $0 != "\n" }
    return firstLine.wholeMatch(of: /[A-Za-z_$][A-Za-z0-9_$]*\s*=.*/) != nil
  }

  /// The failed tools' notes, in order: what each was doing and why it
  /// failed. Tools that failed for the same reason, like three that needed
  /// the location, share one note that gives the reason.
  static func notes(_ errors: [OpenUIError]) -> [String] {
    var reasons: [String] = []
    var doing: [String: [String]] = [:]
    for error in errors {
      let label = error.toolName.map { ToolRunner.label(for: $0) } ?? "A tool"
      let reason =
        error.message.range(of: "failed: ").map { String(error.message[$0.upperBound...]) } ?? error.message
      if doing[reason] == nil { reasons.append(reason) }
      if doing[reason]?.contains(label) != true { doing[reason, default: []].append(label) }
    }
    return reasons.map { reason in
      let labels = doing[reason] ?? []
      return labels.count == 1 ? "\(labels[0]): \(reason)" : reason
    }
  }
}

/// Plain text from the model, with inline markdown.
struct ProseView: View {
  let text: String

  var body: some View {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
  }
}

/// Three dots breathing in turn while the model starts its answer.
struct ThinkingIndicator: View {
  private let colors = [Pastel.sky.ink, Pastel.lavender.ink, Pastel.rose.ink]

  var body: some View {
    TimelineView(.animation) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 6) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(colors[index])
            .frame(width: 8, height: 8)
            .opacity(0.3 + 0.7 * max(0, sin((time * 4) - Double(index) * 0.7)))
        }
      }
      .padding(.vertical, 6)
    }
    .accessibilityLabel("Thinking")
  }
}

/// A small pulsing dot under a response that is still streaming.
struct StreamingDot: View {
  @State private var bright = false

  var body: some View {
    Circle()
      .fill(Pastel.accent)
      .frame(width: 8, height: 8)
      .opacity(bright ? 0.9 : 0.3)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bright = true }
      }
      .accessibilityHidden(true)
  }
}


