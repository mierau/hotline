import SwiftUI

// MARK: - Chat & Messaging

extension HotlineState {

  /// The most messages the chat keeps, and the most lines about people connecting and
  /// disconnecting among them, which don't count toward the messages, since they can be hidden.
  static let maxChatMessages = 2000
  /// How much older chat's brought in at a time, as the chat's scrolled back: this many messages,
  /// and the lines about people connecting and disconnecting among them. Few enough to show
  /// within a frame, and enough to stay ahead of scrolling.
  static let chatPageSize = 100
  /// How many of the oldest messages go at once when the chat passes its limit. Removing text
  /// from the top of the chat view makes it lay out everything below again, about as slow for
  /// one message as for a few hundred, so a batch at a time keeps that to every couple hundred
  /// messages rather than every one.
  static let chatTrimBatch = 200

  @MainActor
  func sendBroadcast(_ message: String) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.sendBroadcast(message)
  }

  @MainActor
  func sendChat(_ text: String, announce: Bool = false) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.sendChat(text, announce: announce)
  }

  /// Sends someone a private message, and, for a reply, the message of theirs it's a reply to, as
  /// it quotes it, which the server passes on with it. It's in your conversation with them at once,
  /// as on its way, and then as delivered, once the server says it has it, or as not, and why.
  @MainActor
  func sendInstantMessage(_ text: String, userID: UInt16, quoting: String? = nil) throws {
    guard self.client != nil else {
      throw HotlineClientError.notConnected
    }

    let user = self.users.first(where: { $0.id == userID })
    let selfUser = self.users.first(where: { $0.name == self.username })

    let message = InstantMessage(
      direction: .outgoing,
      senderName: self.username,
      senderIconID: UInt(self.iconID),
      receiverName: user?.name ?? "",
      receiverIconID: user?.iconID ?? 0,
      text: text,
      type: .message,
      date: Date(),
      isRead: false,
      senderIsAdmin: selfUser?.isAdmin ?? false,
      quoting: quoting,
      delivery: .sending
    )

    let conversation = self.conversations.file(message, with: userID, name: user?.name ?? "", iconID: user?.iconID ?? 0)
    self.recordPrivateMessage(message, peerName: conversation.name)
    self.deliver(message, to: userID)
  }

  /// Sends one of yours that didn't get to them again, as it was, to them as they are now, in its
  /// place in your conversation.
  @MainActor
  func resendPrivateMessage(id: UUID, userID: UInt16) {
    guard self.client != nil,
          let current = self.currentUserID(of: userID),
          let conversation = self.conversations[userID],
          var message = conversation.messages.first(where: { $0.id == id }),
          case .notDelivered? = message.delivery else {
      return
    }

    message.delivery = .sending
    self.conversations.update(conversation.id) { conversation in
      if let i = conversation.messages.firstIndex(where: { $0.id == id }) {
        conversation.messages[i].delivery = .sending
      }
    }
    self.recordPrivateMessage(message, peerName: conversation.name)
    self.deliver(message, to: current)
  }

  /// Waits, apart from whatever sent it, for the server to say whether one of yours got to them,
  /// and says so on it, and where it's saved.
  @MainActor
  private func deliver(_ message: InstantMessage, to userID: UInt16) {
    guard let client = self.client else {
      return
    }
    let name = self.conversations[userID]?.name ?? message.receiverName

    Task { [weak self] in
      let delivery: InstantMessageDelivery
      do {
        try await client.sendInstantMessage(message.text, to: userID, quoting: message.quoting)
        delivery = .delivered
      }
      catch HotlineClientError.timeout where self?.users.contains(where: { $0.id == userID }) == true {
        // No answer, which a server might not give, while they're still here.
        delivery = .unconfirmed
      }
      catch {
        delivery = .notDelivered(Self.undeliveredReason(for: error, to: name))
      }

      guard let self, let delivered = self.conversations.deliver(message.id, with: userID, as: delivery), let conversation = self.conversations[userID] else {
        return
      }
      self.recordPrivateMessage(delivered, peerName: conversation.name)
    }
  }

  /// Why one of yours didn't get to them: as the server said, or, when it didn't answer, that they'd
  /// gone, as Mobius doesn't answer for someone who isn't there. Nil otherwise, as when the
  /// connection's lost.
  static func undeliveredReason(for error: Error, to name: String?) -> String? {
    switch error {
    case HotlineClientError.serverError(_, let message?) where !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
      return message
    case HotlineClientError.timeout:
      if let name, !name.isEmpty {
        return "\(name) isn't on the server anymore."
      }
      return "They aren't on the server anymore."
    default:
      return nil
    }
  }

  @MainActor
  func sendAgree() async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let options = self.userOptions
    let autoresponse = self.automaticResponseOn ? self.automaticResponse : nil

    // Old servers (<150) don't support the agreed transaction.
    if self.serverVersion >= 150 {
      print("HotlineState.sendAgree(): Sending agreed transaction...")
      do {
        try await client.sendAgree(options: options, autoresponse: autoresponse)
        print("HotlineState.sendAgree(): Agreed sent successfully")
      } catch let error as HotlineClientError {
        // Some third-party servers send showAgreement but don't recognize the
        // agreed transaction. Treat this as non-fatal since the user already
        // accepted the agreement in the UI.
        if case .serverError(_, _) = error {
          print("HotlineState.sendAgree(): Server rejected agreed transaction (\(error)), continuing anyway")
        } else {
          throw error
        }
      }
    } else {
      print("HotlineState.sendAgree(): Old server (v\(self.serverVersion)), skipping agreed transaction")
    }
    self.agreed = true
    self.agreementText = nil

    // For new servers, the login flow was deferred until agreement.
    // For old servers, login already completed — just dismiss the sheet.
    if self.status != .loggedIn {
      try await self.completeLogin()
    }
  }

  /// Sends your name and icon from Settings, and your options on this server.
  @MainActor
  func sendUserPreferences() async throws {
    print("HotlineState.sendUserPreferences(): Updating user info with server")

    try await self.sendUserInfo(
      username: Prefs.shared.username,
      iconID: Prefs.shared.userIconID,
      options: self.userOptions,
      autoresponse: self.automaticResponse
    )
  }

  /// Your options on this server, as the server's told them.
  private var userOptions: HotlineUserOptions {
    var options: HotlineUserOptions = []
    if self.refusePrivateMessages {
      options.update(with: .refusePrivateMessages)
    }
    if self.refusePrivateChat {
      options.update(with: .refusePrivateChat)
    }
    if self.automaticResponseOn {
      options.update(with: .automaticResponse)
    }
    return options
  }

  /// Changes your options on this server, from the Server menu, or from Settings, which changes them
  /// in every window, and tells the server, if you're connected. What isn't given stays as it is.
  @MainActor
  func setOptions(refusePrivateMessages: Bool? = nil, refusePrivateChat: Bool? = nil, automaticResponseOn: Bool? = nil, automaticResponse: String? = nil) {
    if let refusePrivateMessages {
      self.refusePrivateMessages = refusePrivateMessages
    }
    if let refusePrivateChat {
      self.refusePrivateChat = refusePrivateChat
    }
    if let automaticResponseOn {
      self.automaticResponseOn = automaticResponseOn
    }
    if let automaticResponse {
      self.automaticResponse = automaticResponse
    }
    guard self.status == .loggedIn else {
      return
    }
    Task {
      try? await self.sendUserPreferences()
    }
  }

  func sendUserInfo(username: String, iconID: Int, options: HotlineUserOptions = [], autoresponse: String? = nil) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    self.username = username
    self.iconID = iconID

    try await client.setClientUserInfo(
      username: username,
      iconID: UInt16(iconID),
      options: options,
      autoresponse: autoresponse
    )
  }

  func markBoardAsRead() {
    if self.unreadBoardPosts > 0 {
      self.unreadBoardPosts = 0
    }
  }

  func markPublicChatAsRead() {
    self.unreadPublicChatCount = 0
  }

  /// How many messages, and invitations to private chats, you haven't seen from someone, as their
  /// row in the sidebar shows.
  func unreadCount(from userID: UInt16) -> Int {
    (self.conversations[userID]?.unread ?? 0) + self.privateChats.count { $0.invitation?.userID == userID && $0.unread }
  }

  /// The user ID of whoever had `userID` this visit, as it is now: the same while they're here, the
  /// one they came back with, if they have, and nil while they're gone.
  func currentUserID(of userID: UInt16) -> UInt16? {
    let current: UInt16?
    if let conversation = self.conversations[userID] {
      current = conversation.userID
    }
    else {
      current = userID
    }
    guard let current, self.users.contains(where: { $0.id == current }) else {
      return nil
    }
    return current
  }

  /// What the sidebar's counts add up to: the public chat's, the board's, each private chat's you're
  /// in, and each person's here.
  var unreadCount: Int {
    let people = self.users.reduce(0) { $0 + self.unreadCount(from: $1.id) }
    let chats = self.joinedPrivateChats.reduce(0) { $0 + $1.unreadCount }
    return self.unreadPublicChatCount + self.unreadBoardPosts + people + chats
  }

  func markPrivateMessagesAsRead(userID: UInt16) {
    guard let conversation = self.conversations[userID], conversation.unread > 0 else { return }
    self.conversations.update(conversation.id) { $0.unread = 0 }
  }

  /// Marks what's been said with them read, here and on your computer, whether they're still here
  /// or not.
  func setPrivateMessagesRead(userID: UInt16) {
    guard let conversation = self.conversations[userID] else { return }
    let unread = conversation.messages.filter { !$0.isRead }.map(\.id)
    guard !unread.isEmpty else { return }
    self.conversations.update(conversation.id) { conversation in
      for i in conversation.messages.indices {
        conversation.messages[i].isRead = true
      }
    }

    Task {
      await ChatStore.shared.markEntriesAsRead(ids: unread)
    }
  }

  func deletePrivateMessage(id: UUID, userID: UInt16) {
    if let conversation = self.conversations[userID] {
      self.conversations.update(conversation.id) { $0.messages.removeAll(where: { $0.id == id }) }
    }

    Task {
      await ChatStore.shared.deleteEntry(id: id)
    }
  }

  /// Deletes all the conversation with them shows, here and on your computer, whether they're still
  /// here or not, and whatever names it was saved under.
  func deleteAllPrivateMessages(userID: UInt16) {
    guard let conversation = self.conversations[userID] else { return }
    let ids = conversation.messages.map(\.id)
    self.conversations.update(conversation.id) { conversation in
      conversation.messages = []
      conversation.unread = 0
    }

    Task {
      await ChatStore.shared.deleteEntries(ids: ids)
    }
  }

  /// Reads back what was saved of your conversation with them on earlier visits, by their name,
  /// once, into it, or into one started with them, for someone here you haven't talked with yet.
  func restorePrivateHistory(userID: UInt16) {
    var conversation = self.conversations[userID]
    if conversation == nil, let user = self.users.first(where: { $0.id == userID }) {
      conversation = self.conversations.start(with: user.id, name: user.name, iconID: user.iconID)
    }
    guard let conversation, !conversation.restored, let key = self.chatSessionKey else { return }

    self.conversations.update(conversation.id) { $0.restored = true }
    let id = conversation.id
    let peerName = conversation.name

    Task { [weak self] in
      guard let self else { return }
      let result = await ChatStore.shared.loadHistory(for: key, peerName: peerName)

      await MainActor.run {
        // Result is in DESC order (newest first), reverse to get chronological for storage
        let historyMessages: [InstantMessage] = result.entries.reversed().compactMap { entry in
          let direction: InstantMessageDirection = entry.type == "privateOut" ? .outgoing : .incoming
          return InstantMessage(
            id: entry.id,
            direction: direction,
            senderName: entry.username ?? peerName,
            senderIconID: entry.metadata?.iconID ?? 0,
            receiverName: entry.metadata?.receiverName ?? "",
            receiverIconID: entry.metadata?.receiverIconID ?? 0,
            text: entry.body,
            type: entry.metadata?.kind.flatMap(InstantMessageType.init(rawValue:)) ?? .message,
            date: entry.date,
            isRead: entry.isRead,
            senderIsAdmin: entry.metadata?.senderIsAdmin ?? false,
            quoting: entry.metadata?.quoting,
            delivery: InstantMessageDelivery(saved: entry.metadata?.delivery, reason: entry.metadata?.undeliveredReason)
          )
        }

        guard !historyMessages.isEmpty else { return }

        self.conversations.update(id) { conversation in
          let currentIDs = Set(conversation.messages.map { $0.id })
          conversation.messages = historyMessages.filter { !currentIDs.contains($0.id) } + conversation.messages
        }
      }
    }
  }

  /// The messages in the chat with `query` in their text or sender's name, in order, along with
  /// the disconnects between them that show where sessions end.
  @MainActor
  func searchChat(query: String) -> [ChatMessage] {
    guard !query.isEmpty else {
      return []
    }
    return self.searchChat { $0.searchText.range(of: query, options: [.caseInsensitive, .literal]).location != NSNotFound }
  }

  /// The messages in the chat that `matches` finds, in order, along with the disconnects between
  /// them that show where sessions end.
  @MainActor
  func searchChat(where matches: (ChatMessage) -> Bool) -> [ChatMessage] {
    self.chat.searched(where: matches)
  }

  // MARK: - Chat Persistence

  func sessionKey(for server: Server) -> ChatStore.SessionKey {
    ChatStore.SessionKey(address: server.address.lowercased(), port: server.port)
  }

  func recordChatMessage(_ message: ChatMessage, persist: Bool = true, display: Bool = true) {
    let shouldPersist = persist && message.type != .agreement

    // Never allow back-to-back dividers (check display and persist independently)
    let skipDisplay = message.type == .signOut && display && self.chat.last?.type == .signOut
    let skipPersist = message.type == .signOut && shouldPersist && self.lastPersistedMessageType == .signOut

    if skipDisplay && skipPersist { return }

    if display && !skipDisplay {
      if self.isReadingBack, message.type == .message {
        self.newWhileReadingBack += 1
      }
      // With whatever's been scrolled back to.
      let limit = Self.maxChatMessages + self.chatScrollback
      // While you're reading back through a chat that's full, what comes waits, rather than pushing
      // out what you're reading, and after anything else that's waiting.
      if self.isReadingBack, !self.newerChat.isEmpty || Self.trimmed(self.chat + [message], to: limit) != nil {
        self.newerChat.append(message)
        if let trimmed = Self.trimmed(self.newerChat, to: Self.maxChatMessages, batch: Self.chatTrimBatch) {
          self.newerChat = trimmed
        }
      }
      else {
        self.chat.append(message)
        if self.chat.count > limit, let trimmed = Self.trimmed(self.chat, to: limit, batch: Self.chatTrimBatch) {
          self.chatScrollback = max(0, self.chatScrollback - (self.chat.count - trimmed.count))
          self.hasOlderChat = true
          self.chat = trimmed
          self.chatRenderedText = nil
          self.chatRenderedCount = 0
        }
      }
    }

    guard shouldPersist && !skipPersist, let key = self.chatSessionKey else { return }
    self.lastPersistedMessageType = message.type
    self.lastPersistedMessageDate = message.date

    var entryMetadata: ChatStore.EntryMetadata? = message.metadata
    if message.iconID != nil || message.isAdmin {
      if entryMetadata == nil {
        entryMetadata = ChatStore.EntryMetadata()
      }
      entryMetadata?.iconID = message.iconID
      entryMetadata?.senderIsAdmin = message.isAdmin ? true : nil
    }

    let entry = ChatStore.Entry(
      id: message.id,
      body: message.text,
      username: message.username,
      type: message.type.storageKey,
      date: message.date,
      metadata: entryMetadata
    )
    let serverName = self.serverName ?? self.server?.name

    Task {
      await ChatStore.shared.append(entry: entry, for: key, serverName: serverName)
    }
  }

  /// The chat without its oldest lines, once it has more than `limit` of either kind: messages, or
  /// lines about people connecting and disconnecting, which are counted apart, so lots of them
  /// don't push out what's said, and lots said doesn't push them out. Whichever's over goes down
  /// to `batch` fewer, so it isn't trimmed again with every line. Nil if neither's over.
  static func trimmed(_ chat: [ChatMessage], to limit: Int, batch: Int = 0) -> [ChatMessage]? {
    let connections = chat.reduce(0) { $0 + ($1.isConnection ? 1 : 0) }
    let messages = chat.count - connections
    guard messages > limit || connections > limit else {
      return nil
    }
    // How many of the oldest of each go.
    var messagesGoing = messages > limit ? messages - (limit - batch) : 0
    var connectionsGoing = connections > limit ? connections - (limit - batch) : 0
    return chat.filter { line in
      if line.isConnection {
        guard connectionsGoing > 0 else {
          return true
        }
        connectionsGoing -= 1
        return false
      }
      guard messagesGoing > 0 else {
        return true
      }
      messagesGoing -= 1
      return false
    }
  }

  func recordPrivateMessage(_ message: InstantMessage, peerName: String) {
    guard let key = self.chatSessionKey, !peerName.isEmpty else { return }

    let entryType = message.direction == .outgoing ? "privateOut" : "privateIn"
    let entry = ChatStore.Entry(
      id: message.id,
      body: message.text,
      username: message.senderName,
      type: entryType,
      date: message.date,
      metadata: ChatStore.EntryMetadata(iconID: message.senderIconID, receiverName: message.receiverName, receiverIconID: message.receiverIconID, senderIsAdmin: message.senderIsAdmin ? true : nil, quoting: message.quoting, kind: message.type == .message ? nil : message.type.rawValue, delivery: message.delivery?.saved, undeliveredReason: message.delivery?.reason),
      isRead: message.isRead
    )
    let serverName = self.serverName ?? self.server?.name

    Task {
      await ChatStore.shared.append(entry: entry, for: key, serverName: serverName, peerName: peerName)
    }
  }

  func restoreChatHistory(for key: ChatStore.SessionKey) {
    if self.restoredChatSessionKey == key {
      return
    }

    Task { [weak self] in
      guard let self else { return }
      // The newest of it, with room for more to come before the oldest are trimmed, and more as
      // the chat's scrolled back.
      let entries = await ChatStore.shared.loadPage(for: key, count: Self.maxChatMessages - Self.chatTrimBatch)

      await MainActor.run {
        guard self.chatSessionKey == key, self.restoredChatSessionKey != key else { return }

        let currentMessages = self.chat
        // Without what's come since, which is saved as it comes, so may be among it.
        let current = Set(currentMessages.map(\.id))
        let historyMessages = entries.compactMap(ChatMessage.init(entry:)).filter { !current.contains($0.id) }

        // Skip history that has no real content (only sign-out/divider messages)
        let hasContent = historyMessages.contains { $0.type != .signOut }
        let effectiveHistory = hasContent ? historyMessages : []

        let combined = effectiveHistory + currentMessages
        self.chat = Self.trimmed(combined, to: Self.maxChatMessages) ?? combined
        self.chatScrollback = 0
        self.hasOlderChat = true
        let lastEntry = entries.last
        self.lastPersistedMessageType = lastEntry.flatMap { ChatMessageType(storageKey: $0.type) }
        self.lastPersistedMessageDate = lastEntry?.date
        self.unreadPublicChatCount = 0
        self.restoredChatSessionKey = key
      }
    }
  }

  /// Brings in a page of chat from before what's shown, from what's saved, as the chat's scrolled
  /// back to its start.
  @MainActor
  func loadOlderChat() async {
    guard self.hasOlderChat, !self.isLoadingOlderChat, let key = self.chatSessionKey, let oldest = self.chat.first else {
      return
    }
    self.isLoadingOlderChat = true
    // One more, for the oldest that's here, which comes again.
    let entries = await ChatStore.shared.loadPage(for: key, through: oldest.date, count: Self.chatPageSize + 1)
    self.isLoadingOlderChat = false
    // Only if the chat still starts there, on the same server.
    guard self.chatSessionKey == key, self.chat.first?.id == oldest.id else {
      return
    }
    // Without the lines that are here already, from the same moment as the oldest.
    let here = Set(self.chat.prefix { $0.date <= oldest.date }.map(\.id))
    let older = entries.compactMap(ChatMessage.init(entry:)).filter { !here.contains($0.id) }
    guard !older.isEmpty else {
      self.hasOlderChat = false
      return
    }
    self.chat.insert(contentsOf: older, at: 0)
    self.chatScrollback += older.count
    self.chatRenderedText = nil
    self.chatRenderedCount = 0
  }

  /// Reading back through the chat, from its newest.
  func startReadingBack() {
    guard !self.isReadingBack else {
      return
    }
    self.isReadingBack = true
    self.newWhileReadingBack = 0
  }

  /// Back at the newest of the chat, after reading back: what came meanwhile, after what was there,
  /// and only as much as the chat usually keeps.
  func catchUpChat() {
    let wasReadingBack = self.isReadingBack
    self.isReadingBack = false
    if self.newWhileReadingBack != 0 {
      self.newWhileReadingBack = 0
    }
    guard wasReadingBack, !self.newerChat.isEmpty || self.chatScrollback > 0 else {
      return
    }
    let caughtUp = self.chat + self.newerChat
    self.newerChat = []
    self.chat = Self.trimmed(caughtUp, to: Self.maxChatMessages, batch: Self.chatTrimBatch) ?? caughtUp
    self.chatScrollback = 0
    self.hasOlderChat = true
    self.chatRenderedText = nil
    self.chatRenderedCount = 0
  }

  func handleChatHistoryCleared() {
    self.chat = []
    self.newerChat = []
    self.chatRenderedText = nil
    self.chatRenderedCount = 0
    self.chatScrollback = 0
    self.hasOlderChat = true
    self.unreadPublicChatCount = 0
    self.restoredChatSessionKey = nil
    self.lastPersistedMessageType = nil
  }
}
