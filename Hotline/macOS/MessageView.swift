import SwiftUI
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

private struct ComposeContext: Identifiable {
  let id = UUID()
  /// The message it's a reply to, as the reply quotes it, or nil for a new message.
  let quoting: String?
}

struct MessageView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openWindow) private var openWindow

  @State private var userInfo: HotlineUserClientInfo?
  @State private var disconnectConfirmShown: Bool = false
  @State private var deleteAllConfirmShown: Bool = false
  @State private var composeContext: ComposeContext? = nil
  @State private var deleteMessageID: UUID? = nil
  /// A linked file's info, from its link's menu.
  @State private var fileDetails: FileDetails?
  @FocusState private var focusedMessageID: UUID?
  /// A message to scroll to and select, like the one a reply's quote is of.
  @State private var revealedMessageID: UUID?

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
      if let msg = self.focusedMessage, msg.canBeRepliedTo, self.cantSendReason == nil {
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
    }
    .onDisappear {
      self.model.setPrivateMessagesRead(userID: self.userID)
    }
    // Their messages and invitations that come while it's shown are seen.
    .onSeen(self.model.unreadCount(from: self.userID)) {
      self.model.markPrivateMessagesAsRead(userID: self.userID)
      self.model.markInvitationsAsRead(from: self.userID)
    }
    .onChange(of: self.messages.count) {
      if let newest = self.messages.last, newest.direction == .outgoing {
        self.focusedMessageID = newest.id
      }
    }
    .toolbar {

      ToolbarItemGroup {
          Button {
            if let msg = self.focusedMessage {
              self.replyTo(msg)
            }
          } label: {
            Image(systemName: "arrowshape.turn.up.left")
          }
          .help(self.replyHelp)
          .disabled(self.focusedMessage?.canBeRepliedTo != true || self.cantSendReason != nil)

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
            .disabled(self.model.access?.contains(.canGetClientInfo) != true || self.currentUserID == nil)

            Button(role: .destructive) {
              self.disconnectConfirmShown = true
            } label: {
              Label("Disconnect \(self.username ?? "User")...", systemImage: "nosign")
            }
            .disabled(self.model.access?.contains(.canDisconnectUsers) != true || self.currentUserID == nil)
          } label: {
            Image(systemName: "ellipsis")
          }
      }

      if #available(macOS 26.0, *) {
        ToolbarSpacer()
      }

      ToolbarItem {
        Button {
          self.composeContext = ComposeContext(quoting: nil)
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .help(self.cantSendReason ?? "Compose message to \(self.username ?? "user")")
        .disabled(self.cantSendReason != nil)
      }
    }
    .sheet(item: self.$composeContext) { context in
      ComposeMessageView(userID: self.currentUserID ?? self.userID, username: self.username, quoting: context.quoting)
    }
    .sheet(item: self.$userInfo) { info in
      UserClientInfoSheet(info: info)
    }
    .sheet(item: self.$fileDetails) { details in
      FileDetailsSheet(details: details)
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
    self.model.conversations[self.userID]?.messages ?? []
  }

  /// Messages in display order (newest first).
  private var displayMessages: [InstantMessage] {
    self.messages.reversed()
  }

  /// Their name as it is now, through any change, or as it was when they left.
  private var username: String? {
    self.model.conversations[self.userID]?.name ?? self.model.users.first(where: { $0.id == self.userID })?.name
  }

  /// Where they are on the server now: the user ID they're shown for while they're here, the one
  /// they came back with if they've reconnected, or nil while they're gone.
  private var currentUserID: UInt16? {
    self.model.currentUserID(of: self.userID)
  }

  private var userRefusesMessages: Bool {
    self.model.users.first(where: { $0.id == self.currentUserID })?.refusesPrivateMessages ?? false
  }

  /// Why nothing can be sent to them, as Reply and Compose say while they're off, or nil when it
  /// can.
  private var cantSendReason: String? {
    if self.model.access?.contains(.canSendMessages) != true {
      return "Your account on this server can't send private messages"
    }
    if self.userRefusesMessages {
      return "\(self.username ?? "They") doesn't accept private messages"
    }
    if self.currentUserID == nil {
      return "\(self.username ?? "They") isn't on the server"
    }
    return nil
  }

  /// The message that's selected, if one is.
  private var focusedMessage: InstantMessage? {
    self.focusedMessageID.flatMap { id in self.displayMessages.first(where: { $0.id == id }) }
  }

  /// What Reply says it does, or why it's off.
  private var replyHelp: String {
    if let reason = self.cantSendReason {
      return reason
    }
    guard let msg = self.focusedMessage else {
      return "Select a message to reply to"
    }
    switch msg.type {
    case .message:
      return "Reply to selected message"
    case .automaticResponse:
      return "An automatic reply can't be replied to"
    case .refusal:
      return "This is from the server, and can't be replied to"
    }
  }

  private func getUserInfo() {
    guard let id = self.currentUserID else {
      return
    }
    Task {
      if let info = try? await self.model.getClientInfoText(id: id) {
        self.userInfo = info
      }
    }
  }

  private func disconnectUser() {
    guard let id = self.currentUserID else {
      return
    }
    Task {
      try? await self.model.disconnectUser(id: id, options: nil)
    }
  }

  /// Writes a reply, which quotes what it's a reply to, as the protocol has replies do, for the
  /// server to pass on with it, and other clients show with it, as this one does.
  private func replyTo(_ msg: InstantMessage) {
    guard msg.canBeRepliedTo else {
      return
    }
    self.composeContext = ComposeContext(quoting: InstantMessage.quote(of: self.messageBodyText(msg)))
  }

  /// The message a reply's quote is of, if it's among these: the latest one before it with what it
  /// quotes.
  private func original(quotedBy msg: InstantMessage) -> InstantMessage? {
    guard let quoting = msg.quoting else {
      return nil
    }
    return self.messages.last { $0.id != msg.id && $0.date <= msg.date && $0.isQuoted(by: quoting) }
  }

  /// A reply from before replies quoted what they're replies to, which started with a line of it,
  /// as its line and the rest.
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
    ScrollViewReader { proxy in
      self.messageScrollView
        // To a message asked for, like the one a reply's quote is of, selected, and so open.
        .onChange(of: self.revealedMessageID) { _, id in
          guard let id else {
            return
          }
          withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
          }
          self.focusedMessageID = id
          self.revealedMessageID = nil
        }
    }
  }

  private var messageScrollView: some View {
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
        UserIconView(iconID: Int(msg.senderIconID))

        Text(msg.senderName)
          .fontWeight(msg.isRead ? .regular : .semibold)
          .foregroundStyle(msg.senderIsAdmin ? AnyShapeStyle(.serverAdmin) : AnyShapeStyle(.primary))
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.disabled)

        if let kind = self.kindLabel(msg) {
          Text(kind)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.fill.secondary, in: .capsule)
            .textSelection(.disabled)
        }

        if case .notDelivered(let reason)? = msg.delivery {
          self.notDelivered(msg, reason: reason)
        }

        if collapsed {
          Text(self.collapsedSnippet(msg).hidingOffensiveWords)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.disabled)
        }

        Spacer()

        if let delivery = msg.delivery {
          DeliveryMark(delivery: delivery)
        }

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

  /// That one of yours didn't get to them, in red, with why in its tip, and Try Again, to send it to
  /// them as it was, while they're here.
  private func notDelivered(_ msg: InstantMessage, reason: String?) -> some View {
    HStack(spacing: 8) {
      Text("Not Delivered")
        .font(.caption)
        .foregroundStyle(.red)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(.red.opacity(0.12), in: .capsule)
        .help(reason ?? "It didn't get to them.")
      Button("Try Again") {
        self.model.resendPrivateMessage(id: msg.id, userID: self.userID)
      }
      .buttonStyle(.link)
      .font(.caption)
      .disabled(self.cantSendReason != nil)
      .help(self.cantSendReason ?? "Send it to them again")
    }
    .textSelection(.disabled)
  }

  /// What a message says, without its Markdown's marks, as it reads, for a line of it, like a
  /// collapsed message's. From its first part, as that's all a line shows.
  private static func plain(_ text: String) -> String {
    let start = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    let shown = Markdown.shownText(start, layout: Markdown.Layout(imagePreviews: 0))
    return Markdown.plainText(shown).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func collapsedSnippet(_ msg: InstantMessage) -> String {
    if let (reLine, _) = self.splitReplyPrefix(msg.text) {
      return Self.plain(reLine)
    }
    let body = Self.plain(msg.text)
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

  private func messageCardBody(_ msg: InstantMessage) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let quoting = msg.quoting {
        self.quoteView(quoting, of: self.original(quotedBy: msg))
      }
      MarkdownText(text: self.messageBodyText(msg), fileLinkMenu: { url in
        FileLinkMenu(model: self.model, openWindow: self.openWindow, showInfo: { self.fileDetails = $0 }).menu(for: url)
      })
    }
  }

  /// What a reply quotes, faint, with a bar beside it, as a quote is on the board, which is of the
  /// other one's message, as a conversation's only the two of you. When the message it's of is
  /// here, a click goes to it, as the pointer says over it.
  private func quoteView(_ quoting: String, of original: InstantMessage?) -> some View {
    Button {
      if let original {
        self.revealedMessageID = original.id
      }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Capsule()
          .fill(.tertiary)
          .frame(width: 3)
        Text(Self.plain(quoting).hidingOffensiveWords)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .truncationMode(.tail)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }
      .fixedSize(horizontal: false, vertical: true)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(original == nil)
    .pointerStyle(original == nil ? nil : .link)
    .help(original == nil ? "" : "Show the message this is a reply to")
  }

  /// What a message is, when it's not one they wrote, for its header.
  private func kindLabel(_ msg: InstantMessage) -> String? {
    switch msg.type {
    case .message:
      nil
    case .automaticResponse:
      "Auto-Reply"
    case .refusal:
      "Not Delivered"
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
      guard msg.canBeRepliedTo, self.cantSendReason == nil else {
        return .ignored
      }
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
    // As one name, as their nickname could have a / in it.
    let filename = "Message from \(msg.senderName) \(Self.filenameDateFormatter.string(from: msg.date)).txt".safeFileName

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

// MARK: - Delivery

/// Whether one of yours got to them, by when it was sent: a spinner while it's on its way, once that's
/// taken a moment, as it usually takes none, and a check once the server says it has it.
private struct DeliveryMark: View {
  let delivery: InstantMessageDelivery

  @State private var slow = false

  var body: some View {
    switch self.delivery {
    case .sending:
      ProgressView()
        .controlSize(.mini)
        .opacity(self.slow ? 1 : 0)
        .help("Sending…")
        .accessibilityLabel("Sending")
        .task {
          try? await Task.sleep(for: .milliseconds(400))
          guard !Task.isCancelled else {
            return
          }
          withAnimation(.easeOut(duration: 0.2)) {
            self.slow = true
          }
        }
    case .delivered:
      Image(systemName: "checkmark")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .help("Delivered")
        .accessibilityLabel("Delivered")
    case .unconfirmed, .notDelivered:
      EmptyView()
    }
  }
}

// MARK: - Compose Message View

/// Writing a private message, across all of the sheet, with who it's to at the top, which can
/// be changed, by the name of anyone on the server, which it suggests as it's typed, and what it
/// says, in Markdown, styled as it's written, with the marks kept but faint, as on the board, and the
/// Format menu's marks, and the formatting buttons', at the bottom on the left, across from Cancel
/// and Send. ⌘↩ sends it, as Return's for new lines.
struct ComposeMessageView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(HotlineState.self) private var model: HotlineState

  /// Who it's to, to start with, or nobody yet, to type a name.
  let userID: UInt16?
  let username: String?
  /// The message it's a reply to, as it quotes it, which goes with it, for a reply.
  let quoting: String?

  init(userID: UInt16? = nil, username: String? = nil, quoting: String? = nil) {
    self.userID = userID
    self.username = username
    self.quoting = quoting
    // Their name from the start, and not set once it's shown, which would be as if it was typed.
    self._recipientName = State(initialValue: username ?? "")
  }

  private var isReply: Bool {
    self.quoting != nil
  }

  /// As small as there's room for who it's to and what it says in.
  private static let smallest = CGSize(width: 420, height: 320)
  /// How big who it's to is written, a little bigger than what it says.
  private static let recipientFontSize: CGFloat = 15
  /// How far in from the sheet's edges who it's to and what it says are, as far as the bottom bar's
  /// buttons are.
  private static let inset = NSSize(width: 20, height: 16)

  @State private var editor = MarkdownEditor()
  @State private var text = ""
  @State private var recipientName: String
  /// Whether the name's been typed, or changed, here, as names are only suggested once it has, and
  /// not for one it starts with, as the field can have the keys for a moment as the sheet opens.
  @State private var recipientEdited = false
  @State private var failed = false
  @State private var confirmingDiscard = false
  /// How big it opens: as big as it was last made, or else as it's meant to be.
  @State private var opening: CGSize = {
    let saved = NSSizeFromString(Prefs.shared.privateMessageSize)
    return saved.width >= Self.smallest.width && saved.height >= Self.smallest.height ? saved : CGSize(width: 520, height: 420)
  }()
  /// How big it is, as it's shown, to keep once it's made bigger or smaller.
  @State private var shown = ShownSize()
  @FocusState private var recipientFocused: Bool

  /// Who it's to. For a reply, whoever wrote what it's a reply to, by who they are rather than by
  /// their name, which they can change, under whatever user ID they've come back with, while
  /// they're here. For a new message, by the name typed: the one it started to, while it's still
  /// their name, or else whoever on the server has that name, and nobody, for a name nobody here
  /// has.
  private var recipient: User? {
    if self.isReply {
      return self.userID.flatMap { self.model.currentUserID(of: $0) }.flatMap { id in self.model.users.first(where: { $0.id == id }) }
    }
    let name = self.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      return nil
    }
    let named = self.model.users.filter { $0.name == name }
    let matching = named.isEmpty ? self.model.users.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame } : named
    if let userID = self.userID, let started = matching.first(where: { $0.id == userID }) {
      return started
    }
    return matching.first(where: { $0.id != self.model.ownUserID }) ?? matching.first
  }

  /// The names it suggests for who it's to, once it's being typed: everyone else here, with what's
  /// typed in their name, those it starts first. Someone whose name it is already stays among them,
  /// so the list doesn't empty, and close, as the name's finished, which SwiftUI's suggestions don't
  /// take well as they open, and only while the name has the keys, as it's for that.
  private var suggestions: [User] {
    guard self.recipientFocused && self.recipientEdited else {
      return []
    }
    let typed = self.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
    let others = self.model.users.filter { $0.id != self.model.ownUserID }
    guard !typed.isEmpty else {
      return others
    }
    let containing = others.filter { $0.name.localizedCaseInsensitiveContains(typed) }
    let starting = containing.filter { $0.name.lowercased().hasPrefix(typed.lowercased()) }
    return starting + containing.filter { !$0.name.lowercased().hasPrefix(typed.lowercased()) }
  }

  var body: some View {
    let message = MessageBoardPost.cleaned(self.text)
    let room = Markdown.maximumLength - message.utf8.count
    let recipient = self.recipient

    // Across all of the sheet: who it's to, along the top, and what it says, under it, to the
    // bottom bar, with its formatting.
    VStack(alignment: .leading, spacing: 0) {
      // Lined up on their words' baseline: what it says it is, their icon, their name, and what's
      // said of them.
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(self.isReply ? "Reply to:" : "To:")
          .font(.system(size: Self.recipientFontSize))
          .foregroundStyle(.secondary)
        if let recipient {
          // With its bottom a little under the words' baseline, as their descenders are.
          UserIconView(iconID: Int(recipient.iconID))
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
        }
        // A reply's to whoever sent what it's a reply to, which can't be changed, as a reply that
        // went to someone else would quote what they've never seen. A new message is to whoever's
        // typed.
        if self.isReply {
          // As they're named now.
          Text(recipient?.name ?? self.recipientName)
            .font(.system(size: Self.recipientFontSize, weight: .semibold))
            .lineLimit(1)
        }
        else {
          // As wide as the name, for what's said of them to go beside it: a copy of it, out of sight,
          // sets how wide, as a text field's own width doesn't follow its text, with room for the
          // insertion point after it.
          Text(self.recipientName.isEmpty ? "Name" : self.recipientName)
            .font(.system(size: Self.recipientFontSize, weight: .semibold))
            .padding(.trailing, 4)
            .fixedSize()
            .hidden()
            .overlay(alignment: .leading) {
              TextField("Name", text: self.$recipientName)
                .textFieldStyle(.plain)
                .font(.system(size: Self.recipientFontSize, weight: .semibold))
                .focused(self.$recipientFocused)
                // AppKit puts a text field's words a point higher as they're edited than as they're
                // shown, as editing hands them to another view, so it's a point lower then, for
                // them to stay where they are, on the line with "To:".
                .offset(y: self.recipientFocused ? 1 : 0)
                .textInputSuggestions(self.suggestions) { user in
                  Label {
                    Text(user.name.hidingOffensiveWords)
                  } icon: {
                    if let icon = HotlineState.getClassicIcon(Int(user.iconID)) {
                      Image(nsImage: icon)
                    }
                  }
                  .textInputCompletion(user.name)
                }
                // Return goes on to what it says.
                .onSubmit {
                  if let textView = self.editor.textView {
                    textView.window?.makeFirstResponder(textView)
                  }
                }
            }
        }
        if let note = self.recipientNote(recipient) {
          Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.fill.secondary, in: .capsule)
            .transition(.opacity)
        }
        Spacer()
        self.status
      }
      .padding(.vertical, 18)
      .padding(.horizontal, Self.inset.width)
      // Anywhere along it, to type who it's to, as the name's field is only as wide as the name, for
      // a new message.
      .contentShape(.rect)
      .onTapGesture {
        if !self.isReply {
          self.recipientFocused = true
        }
      }

      Divider()

      // What it's a reply to, as it quotes it, faint, over what's written.
      if let quoting = self.quoting {
        HStack(alignment: .top, spacing: 10) {
          Capsule()
            .fill(.tertiary)
            .frame(width: 3)
          Text(Self.plain(quoting).hidingOffensiveWords)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .truncationMode(.tail)
          Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Self.inset.width)
        .padding(.top, Self.inset.height)
      }

      PostEditor(text: self.$text, controller: self.editor, startsHere: self.userID != nil, inset: Self.inset)
        .overlay(alignment: .topLeading) {
          if self.text.isEmpty {
            Text(self.placeholder(recipient: recipient))
              .foregroundStyle(.tertiary)
              .padding(.horizontal, Self.inset.width)
              .padding(.vertical, Self.inset.height)
              .allowsHitTesting(false)
          }
        }
    }
    .serverBackground(.post)
    .frame(minWidth: Self.smallest.width, idealWidth: self.opening.width, maxWidth: .infinity, minHeight: Self.smallest.height, idealHeight: self.opening.height, maxHeight: .infinity)
    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
      self.shown.size = size
    }
    .background(ResizableSheet(smallest: Self.smallest, opening: self.opening, shown: self.shown) { size in
      Prefs.shared.privateMessageSize = NSStringFromSize(size)
    })
    // As big as it's meant to be, as above.
    .presentationSizing(.fitted)
    .toolbar {
      // The formatting, at the bottom on the left, across from Cancel and Send, as one item, in the
      // one place a sheet's bottom bar has on that side, which is for a destructive button but
      // takes anything, and off while who it's to is being typed, which has none.
      ToolbarItem(placement: .destructiveAction) {
        PostFormattingBar(editor: self.editor)
          .disabled(self.recipientFocused)
      }

      // Asking first, once something's been written, as it's thrown away.
      ToolbarItem(placement: .cancellationAction) {
        PostCancelButton(room: room, what: "A message") {
          if self.text.isWritten() {
            self.confirmingDiscard = true
          }
          else {
            self.dismiss()
          }
        }
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("Send") {
          self.send()
        }
        .buttonStyle(.borderedProminent)
        // Return is for new lines.
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(message.isEmpty || recipient == nil || recipient?.refusesPrivateMessages == true || room < 0)
        .help("Send Message (⌘↩)")
      }
    }
    .onChange(of: self.recipientName) {
      self.recipientEdited = true
    }
    .discardConfirmation("Discard this message?", isPresented: self.$confirmingDiscard) {
      self.dismiss()
    }
    .onAppear {
      // Without anyone to send it to yet, it starts with who it's to.
      if self.userID == nil {
        self.recipientFocused = true
      }
    }
  }

  /// What's said of who it's to, beside their name, when it can't go to them: that nobody here
  /// has that name, as when they've left, once it's not being typed, or that they don't take
  /// private messages.
  private func recipientNote(_ recipient: User?) -> String? {
    if let recipient {
      return recipient.refusesPrivateMessages ? "Refuses Messages" : nil
    }
    let name = self.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
    return !name.isEmpty && !self.recipientFocused ? "Not Online" : nil
  }

  /// What's at the right of who it's to: that it couldn't be sent, if it couldn't.
  @ViewBuilder
  private var status: some View {
    if self.failed {
      Label("not sent", systemImage: "exclamationmark.circle.fill")
        .foregroundStyle(.red)
        .help("It couldn't be sent, as you're not connected.")
        .transition(.opacity)
    }
  }

  /// What a quote says, without its Markdown's marks, for a few lines of it.
  private static func plain(_ text: String) -> String {
    let start = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    return Markdown.plainText(Markdown.shownText(start, layout: Markdown.Layout(imagePreviews: 0))).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// What the message says before anything's written in it, with who it's for.
  private func placeholder(recipient: User?) -> String {
    if self.isReply {
      return "Write your reply…"
    }
    return recipient.map { "Write a message to \($0.name)…" } ?? "Write a message…"
  }

  /// Sends it, and puts the sheet away, as it's in your conversation with them at once, which says
  /// whether it got to them, once the server does. If it can't be sent, as when you're not
  /// connected, it's still here.
  private func send() {
    let message = MessageBoardPost.cleaned(self.text)
    guard let recipient = self.recipient, !message.isEmpty else {
      return
    }

    do {
      try self.model.sendInstantMessage(message, userID: recipient.id, quoting: self.quoting)
    }
    catch {
      withAnimation(.easeOut(duration: 0.15)) {
        self.failed = true
      }
      return
    }
    self.dismiss()
  }
}

#Preview("Conversation") {
  let model = HotlineState()
  model.users = [User(id: 1, name: "Halcyon", iconID: 4217, status: [])]
  for message in [
    InstantMessage(direction: .incoming, senderName: "Halcyon", senderIconID: 4217, text: "Have you seen the **new** `hotline://` links? They're in *Files* now.\n\n> Quoted from the board\n\n- one\n- two", type: .message, date: .now.addingTimeInterval(-600)),
    InstantMessage(direction: .outgoing, senderName: "macro", senderIconID: 130, text: "Yes! ~~Old~~ new and _shiny_.\n\n```\nlet x = 1\n```", type: .message, date: .now.addingTimeInterval(-300), isRead: false, quoting: "Have you seen the **new** `hotline://` links? They're in *Files* now.\n\n> Quoted from the board\n\n- one\n- two", delivery: .delivered),
    InstantMessage(direction: .incoming, senderName: "Halcyon", senderIconID: 4217, text: "Out to lunch, back at 2.", type: .automaticResponse, date: .now.addingTimeInterval(-290)),
    InstantMessage(direction: .outgoing, senderName: "macro", senderIconID: 130, text: "Back already?", type: .message, date: .now, isRead: false, delivery: .notDelivered("Halcyon isn't on the server anymore.")),
  ] {
    model.conversations.file(message, with: 1, name: "Halcyon", iconID: 4217)
  }
  return MessageView(userID: 1)
    .environment(model)
    .frame(width: 520, height: 600)
}

#Preview("Reply, in a sheet") {
  let model = HotlineState()
  model.users = [User(id: 1, name: "Halcyon", iconID: 4217, status: [])]
  return Color.gray.opacity(0.2)
    .frame(width: 700, height: 560)
    .sheet(isPresented: .constant(true)) {
      ComposeMessageView(userID: 1, username: "Halcyon", quoting: "Have you seen the **new** `hotline://` links? They're in *Files* now.")
        .environment(model)
    }
}

#Preview("To someone who's left") {
  ComposeMessageView(userID: 9, username: "Away Person")
    .environment(HotlineState())
}

#Preview("New private message") {
  let model = HotlineState()
  model.users = [
    User(id: 1, name: "Halcyon", iconID: 4217, status: []),
    User(id: 2, name: "PowerMac G3", iconID: 31337, status: []),
  ]
  return ComposeMessageView(userID: 2, username: "PowerMac G3", quoting: "Have you seen the **new** `hotline://` links? They're in *Files* now.")
    .environment(model)
}
