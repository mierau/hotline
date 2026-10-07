import SwiftUI
import Textual
import UniformTypeIdentifiers

private struct SoftScrollEdgeEffect: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.scrollEdgeEffectStyle(.soft, for: .vertical)
    } else {
      content
    }
  }
}

private enum ComposeField {
  case body
}

private struct ComposeContext: Identifiable {
  let id = UUID()
  let initialText: String
  let isReply: Bool
}

struct MessageView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.colorScheme) private var colorScheme

  @State private var userInfo: HotlineUserClientInfo?
  @State private var disconnectConfirmShown: Bool = false
  @State private var deleteAllConfirmShown: Bool = false
  @State private var username: String?
  @State private var composeContext: ComposeContext? = nil
  @State private var deleteMessageID: UUID? = nil
  @FocusState private var focusedMessageID: UUID?

  var userID: UInt16
  /// Given a private chat they invited you to, once you've joined it, to go to it.
  var onJoinPrivateChat: (UInt32) -> Void = { _ in }

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.dateTimeStyle = .named
    return formatter
  }()

  private static let exactDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  private static let filenameDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HHmmss"
    return formatter
  }()

  var body: some View {
    NavigationStack {
      self.messageList
    }
    .overlay {
      if self.messages.isEmpty && self.invitations.isEmpty {
        self.emptyState
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .serverBackground(.page)
    .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
      self.moveFocus(direction: 1)
      return .handled
    }
    .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
      self.moveFocus(direction: -1)
      return .handled
    }
    .onKeyPress(.return) {
      if let id = self.focusedMessageID,
         let msg = self.displayMessages.first(where: { $0.id == id }) {
        self.replyTo(msg)
        return .handled
      }
      return .ignored
    }
    .onKeyPress(keys: [.delete, .deleteForward]) { _ in
      if let id = self.focusedMessageID {
        self.deleteMessageID = id
        return .handled
      }
      return .ignored
    }
    .onAppear {
      self.model.restorePrivateHistory(userID: self.userID)
      self.model.markPrivateMessagesAsRead(userID: self.userID)
      self.model.markInvitationsAsRead(from: self.userID)

      let user = self.model.users.first(where: { $0.id == self.userID })
      self.username = user?.name
    }
    .onDisappear {
      self.model.setPrivateMessagesRead(userID: self.userID)
    }
    .onChange(of: self.invitations.count) {
      self.model.markInvitationsAsRead(from: self.userID)
    }
    .onChange(of: self.model.privateMessages[self.userID]?.count) {
      self.model.markPrivateMessagesAsRead(userID: self.userID)

      if let newest = self.messages.last, newest.direction == .outgoing {
        self.focusedMessageID = newest.id
      }
    }
    .toolbar {

      ToolbarItemGroup {
          Button {
            if let id = self.focusedMessageID,
               let msg = self.displayMessages.first(where: { $0.id == id }) {
              self.replyTo(msg)
            }
          } label: {
            Image(systemName: "arrowshape.turn.up.left")
          }
          .help("Reply to selected message")
          .disabled(self.focusedMessageID == nil || self.model.access?.contains(.canSendMessages) != true || self.userRefusesMessages)

          Button {
            if let id = self.focusedMessageID {
              self.deleteMessageID = id
            }
          } label: {
            Image(systemName: "trash")
          }
          .help("Delete selected message")
          .disabled(self.focusedMessageID == nil)

          Menu {
            Button(role: .destructive) {
              self.deleteAllConfirmShown = true
            } label: {
              Label("Delete All Messages...", systemImage: "trash")
            }
            .disabled(self.messages.isEmpty)

            Divider()

            Button {
              self.getUserInfo()
            } label: {
              Label("User Info", systemImage: "info.circle")
            }
            .disabled(self.model.access?.contains(.canGetClientInfo) != true)

            Button(role: .destructive) {
              self.disconnectConfirmShown = true
            } label: {
              Label("Disconnect \(self.username ?? "User")...", systemImage: "nosign")
            }
            .disabled(self.model.access?.contains(.canDisconnectUsers) != true)
          } label: {
            Image(systemName: "ellipsis")
          }
      }

      if #available(macOS 26.0, *) {
        ToolbarSpacer()
      }

      ToolbarItem {
        Button {
          self.composeContext = ComposeContext(initialText: "", isReply: false)
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .help("Compose message to \(self.username ?? "user")")
        .disabled(self.model.access?.contains(.canSendMessages) != true || self.userRefusesMessages)
      }
    }
    .sheet(item: self.$composeContext) { context in
      ComposeMessageView(userID: self.userID, username: self.username, initialText: context.initialText, isReply: context.isReply)
    }
    .sheet(item: self.$userInfo) { info in
      UserClientInfoSheet(info: info)
    }
    .alert("Are you sure you want to disconnect \(self.username ?? "this user")?", isPresented: self.$disconnectConfirmShown) {
      Button("Disconnect", role: .destructive) {
        self.disconnectUser()
      }
    } message: {
      Text("They will be disconnected from the server, but may reconnect.")
    }
    .alert(
      "Delete this message?",
      isPresented: Binding(
        get: { self.deleteMessageID != nil },
        set: { if !$0 { self.deleteMessageID = nil } }
      )
    ) {
      Button("Delete", role: .destructive) {
        if let id = self.deleteMessageID {
          self.model.deletePrivateMessage(id: id, userID: self.userID)
          self.deleteMessageID = nil
        }
      }
    } message: {
      Text("This message will be permanently deleted from your computer. This cannot be undone.")
    }
    .alert("Delete all messages with \(self.username ?? "this user")?", isPresented: self.$deleteAllConfirmShown) {
      Button("Delete All", role: .destructive) {
        self.model.deleteAllPrivateMessages(userID: self.userID)
        self.focusedMessageID = nil
      }
    } message: {
      Text("All messages will be permanently deleted from your computer. This cannot be undone.")
    }
  }

  /// The private chats they've invited you to.
  private var invitations: [PrivateChat] {
    self.model.privateChatInvitations(from: self.userID)
  }

  private var messages: [InstantMessage] {
    self.model.privateMessages[self.userID] ?? []
  }

  /// Messages in display order (newest first).
  private var displayMessages: [InstantMessage] {
    self.messages.reversed()
  }

  private var userRefusesMessages: Bool {
    self.model.users.first(where: { $0.id == self.userID })?.refusesPrivateMessages ?? false
  }

  private func getUserInfo() {
    Task {
      if let info = try? await self.model.getClientInfoText(id: self.userID) {
        self.userInfo = info
      }
    }
  }

  private func disconnectUser() {
    Task {
      try? await self.model.disconnectUser(id: self.userID, options: nil)
    }
  }

  private func replyTo(_ msg: InstantMessage) {
    let maxLength = 80
    var body = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Skip past existing "Re: " line to avoid "Re: Re: ..."
    if body.hasPrefix("Re: "), let newlineIndex = body.firstIndex(of: "\n") {
      body = String(body[body.index(after: newlineIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var excerpt = body.prefix(while: { $0 != "." && $0 != "!" && $0 != "?" && $0 != "\n" })
    if excerpt.isEmpty {
      excerpt = body.prefix(maxLength)
    }
    if excerpt.count > maxLength {
      excerpt = excerpt.prefix(maxLength)
    }
    let ellipsis = excerpt.count < body.count ? "..." : ""
    self.composeContext = ComposeContext(initialText: "Re: \(excerpt)\(ellipsis)\n\n", isReply: true)
  }

  private func splitReplyPrefix(_ text: String) -> (String, String)? {
    guard text.hasPrefix("Re: ") else { return nil }
    guard let newlineIndex = text.firstIndex(of: "\n") else { return nil }
    let reLine = String(text[text.startIndex..<newlineIndex])
    let body = String(text[newlineIndex...]).trimmingCharacters(in: .newlines)
    guard !body.isEmpty else { return nil }
    return (reLine, body)
  }

  private func moveFocus(direction: Int) {
    let msgs = self.displayMessages
    guard !msgs.isEmpty else { return }

    guard let currentID = self.focusedMessageID,
          let currentIndex = msgs.firstIndex(where: { $0.id == currentID }) else {
      self.focusedMessageID = msgs.first?.id
      return
    }

    let newIndex = currentIndex + direction
    if newIndex >= 0 && newIndex < msgs.count {
      self.focusedMessageID = msgs[newIndex].id
    }
  }

  // MARK: - Message List

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No Messages", systemImage: "envelope")
    } description: {
      Text("Messages with \(self.username ?? "this user") will appear here")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var messageList: some View {
    ScrollView(.vertical) {
      HStack {
        Spacer(minLength: 0)

        LazyVStack(alignment: .leading, spacing: 8) {
          // Their invitations to private chats, until they're answered, above what they've said.
          ForEach(self.invitations) { chat in
            PrivateChatInvitationView(chat: chat, onJoin: self.onJoinPrivateChat)
          }

          ForEach(self.displayMessages) { msg in
            self.messageCard(msg)
              .id(msg.id)
          }
        }
        .frame(maxWidth: 800, alignment: .center)

        Spacer(minLength: 0)
      }
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
    .defaultScrollAnchor(.top)
    .modifier(SoftScrollEdgeEffect())
  }

  // MARK: - Message Card

  private func isCollapsed(_ msg: InstantMessage) -> Bool {
    msg.isRead && self.focusedMessageID != msg.id
  }

  @ViewBuilder
  private func messageCardHeader(_ msg: InstantMessage, collapsed: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        if let iconImage = HotlineState.getClassicIcon(Int(msg.senderIconID)) {
          Image(nsImage: iconImage)
            .frame(width: 16, height: 16)
        }

        Text(msg.senderName)
          .fontWeight(msg.isRead ? .regular : .semibold)
          .foregroundStyle(msg.senderIsAdmin ? AnyShapeStyle(.serverAdmin) : AnyShapeStyle(.primary))
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.disabled)

        if collapsed {
          Text(self.collapsedSnippet(msg))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.disabled)
        }

        Spacer()

        TimelineView(.periodic(from: .now, by: 60)) { context in
          Text(Self.relativeDateFormatter.localizedString(for: msg.date, relativeTo: context.date))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.disabled)
            .help(Self.exactDateFormatter.string(from: msg.date))
        }
      }

      if !collapsed, let (reLine, _) = self.splitReplyPrefix(msg.text) {
        Text(reLine)
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.disabled)
          .padding(.leading, 24)
      }
    }
    .background(
      self.colorScheme == .light
      ? LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom).blendMode(.softLight)
      : LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom).blendMode(.softLight)
    )
  }

  private func collapsedSnippet(_ msg: InstantMessage) -> String {
    if let (reLine, _) = self.splitReplyPrefix(msg.text) {
      return reLine
    }
    let body = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let sentence = body.prefix(while: { $0 != "." && $0 != "!" && $0 != "?" && $0 != "\n" })
    let excerpt = sentence.isEmpty ? body.prefix(80) : sentence.prefix(80)
    let ellipsis = excerpt.count < body.count ? "..." : ""
    return excerpt + ellipsis
  }

  private func messageBodyText(_ msg: InstantMessage) -> String {
    if let (_, bodyText) = self.splitReplyPrefix(msg.text) {
      return bodyText
    }
    return msg.text
  }

  @ViewBuilder
  private func messageCardBody(_ msg: InstantMessage) -> some View {
    HStack(spacing: 0) {
      StructuredText(markdown: self.messageBodyText(msg).convertingLinksToMarkdown())
        .textual.textSelection(.enabled)

      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private func messageCard(_ msg: InstantMessage) -> some View {
    let collapsed = self.isCollapsed(msg)

    VStack(alignment: .leading, spacing: 16) {
      self.messageCardHeader(msg, collapsed: collapsed)

      if !collapsed {
        Divider()
        self.messageCardBody(msg)
      }
    }
    .padding(24)
    .serverBackground(.message)
    .clipShape(.rect(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(.tint, lineWidth: 2)
        .opacity(self.focusedMessageID == msg.id ? 1 : 0)
    )
    .opacity(collapsed ? 0.75 : 1.0)
    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    .padding(.horizontal, 24)
    .focusable()
    .focused(self.$focusedMessageID, equals: msg.id)
    .focusEffectDisabled()
    .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
      self.moveFocus(direction: 1)
      return .handled
    }
    .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
      self.moveFocus(direction: -1)
      return .handled
    }
    .onKeyPress(.return) {
      self.replyTo(msg)
      return .handled
    }
    .onKeyPress(keys: [.delete, .deleteForward]) { _ in
      self.deleteMessageID = msg.id
      return .handled
    }
    .onDrag {
      self.dragProvider(for: msg)
    }
  }

  private func dragProvider(for msg: InstantMessage) -> NSItemProvider {
    let timestamp = Self.exactDateFormatter.string(from: msg.date)
    let content = "From: \(msg.senderName)\nDate: \(timestamp)\n\n\(msg.text)"
    let filename = "Message from \(msg.senderName) \(Self.filenameDateFormatter.string(from: msg.date)).txt"

    let provider = NSItemProvider()
    provider.suggestedName = filename
    provider.registerFileRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
      let data = Data(content.utf8)
      let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
      try? data.write(to: tempURL)
      completion(tempURL, true, nil)
      return nil
    }
    return provider
  }
}

// MARK: - Compose Message View

struct ComposeMessageView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(HotlineState.self) private var model: HotlineState

  let userID: UInt16
  let username: String?
  var initialText: String = ""
  var isReply: Bool = false

  @State private var text: String = ""
  @State private var sending: Bool = false
  @FocusState private var focusedField: ComposeField?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        Button {
          self.dismiss()
        } label: {
          Image(systemName: "xmark")
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .opacity(0.5)
        }
        .buttonStyle(.plain)
        .frame(width: 16, height: 16)

        Spacer()

        Text(self.isReply ? "Reply to \(self.username ?? "User")" : "Message to \(self.username ?? "User")")
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()

        if self.sending {
          ProgressView()
            .controlSize(.small)
            .frame(width: 22, height: 22)
        }
        else {
          Button {
            self.sending = true
            Task {
              try? await self.model.sendInstantMessage(self.text, userID: self.userID)
              Task { @MainActor in
                self.sending = false
                self.dismiss()
              }
            }
          } label: {
            Image(systemName: "paperplane.circle.fill")
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .foregroundColor(self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
          }
          .buttonStyle(.plain)
          .frame(width: 26, height: 26)
          .help("Send Message")
          .disabled(self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .frame(maxWidth: .infinity)
      .padding()

      Divider()

      BetterTextEditor(text: self.$text)
        .betterEditorFont(NSFont.systemFont(ofSize: 14.0))
        .betterEditorAutomaticSpellingCorrection(true)
        .betterEditorTextInset(.init(width: 16, height: 18))
        .lineSpacing(20)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focused(self.$focusedField, equals: .body)
    }
    .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity, minHeight: 200, idealHeight: 350, maxHeight: .infinity)
    .background(Color(nsColor: .textBackgroundColor))
    .presentationCompactAdaptation(.sheet)
    .onAppear {
      self.text = self.initialText
      self.focusedField = .body
    }
    .onDisappear {
      self.dismiss()
    }
  }
}

#Preview {
  MessageView(userID: 1)
    .environment(HotlineState())
}
