import OpenUISwiftUI
import SwiftUI

/// Conversations in a sidebar (iPad, Mac) or a stack (iPhone), the open one on
/// the right. Each conversation keeps its model, so a response keeps streaming
/// while you look at another one.
struct RootView: View {
  @State private var store = ConversationStore()
  @State private var selection: Conversation.ID?
  @State private var models: [Conversation.ID: ChatModel] = [:]
  @Bindable private var payments = PaymentController.shared
  @Bindable private var server = ServerStatus.shared

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        ForEach(store.conversations) { conversation in
          HStack(spacing: 10) {
            Image(systemName: "calendar")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Pastel.sky.onSolid)
              .frame(width: 28, height: 28)
              .background(Pastel.sky.solid, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
              Text(conversation.title).lineLimit(1)
              Text(conversation.updated, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          .tag(conversation.id)
          .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(conversation.id) }
          }
        }
        .onDelete { offsets in
          for index in offsets { delete(store.conversations[index].id) }
        }
      }
      .navigationTitle("Plans")
      .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
      .toolbar {
        ToolbarItem {
          Button("New plan", systemImage: "square.and.pencil", action: newConversation)
            .keyboardShortcut("n")
        }
        ToolbarItem {
          Button("Settings", systemImage: "gearshape") { server.showingSettings = true }
        }
      }
    } detail: {
      if let id = selection, let model = models[id] {
        ChatView(model: model).id(id)
      } else {
        ContentUnavailableView("No plan selected", systemImage: "calendar")
      }
    }
    // The pastel theme for the app and for every OpenUI component in it.
    .tint(Pastel.accent)
    .environment(\.openUITheme, Pastel.openUI)
    .onChange(of: selection, initial: true) { prepareModel(selection) }
    // Razorpay's web checkout, where the native SDK isn't available (macOS).
    .sheet(item: $payments.webCheckout) { WebCheckoutSheet(request: $0) }
    .sheet(isPresented: $server.showingSettings) { ServerSettingsView() }
    .task {
      // Start in a fresh conversation.
      if selection == nil { newConversation() }
      await server.check()
    }
  }

  /// Opens an empty plan, reusing one that's still empty instead of adding
  /// another.
  private func newConversation() {
    let empty = store.conversations.first { conversation in
      models[conversation.id].map(\.messages.isEmpty) ?? conversation.messages.isEmpty
    }
    selection = empty?.id ?? store.newConversation().id
  }

  private func delete(_ id: Conversation.ID) {
    models[id]?.stop()
    models[id] = nil
    store.delete(id)
    if selection == id { selection = store.conversations.first?.id }
  }

  private func prepareModel(_ id: Conversation.ID?) {
    guard let id, models[id] == nil,
      let conversation = store.conversations.first(where: { $0.id == id })
    else { return }
    models[id] = ChatModel(conversation, store: store)
  }
}
