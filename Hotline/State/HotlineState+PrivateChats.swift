import SwiftUI
import UserNotifications

// MARK: - Private Chats

extension HotlineState {

  /// A private chat, by its ID.
  func privateChat(_ chatID: UInt32) -> PrivateChat? {
    self.privateChats.first(where: { $0.id == chatID })
  }

  /// The private chats you're in, for the sidebar, without the ones you're only invited to, which
  /// wait with your messages with whoever invited you.
  var joinedPrivateChats: [PrivateChat] {
    self.privateChats.filter { $0.invitation == nil }
  }

  /// The private chats someone's invited you to.
  func privateChatInvitations(from userID: UInt16) -> [PrivateChat] {
    self.privateChats.filter { $0.invitation?.userID == userID }
  }

  /// Whether someone's invited you to a private chat since you last looked at your messages with
  /// them, which the user list shows as it does a message.
  func hasUnreadInvitation(from userID: UInt16) -> Bool {
    self.privateChats.contains { $0.invitation?.userID == userID && $0.unread }
  }

  func markInvitationsAsRead(from userID: UInt16) {
    for i in self.privateChats.indices where self.privateChats[i].invitation?.userID == userID && self.privateChats[i].unread {
      self.privateChats[i].unread = false
    }
  }

  /// The private chats you're in that someone could be invited to: the ones they're not in.
  func privateChats(toInvite userID: UInt16) -> [PrivateChat] {
    self.privateChats.filter { $0.invitation == nil && !$0.users.contains(where: { $0.id == userID }) }
  }

  /// What a private chat goes by: its subject, or without one, who else is in it, or for an
  /// invitation, who it's from.
  func title(of chat: PrivateChat) -> String {
    if let invitation = chat.invitation {
      return "\(invitation.name) invited you"
    }
    if !chat.subject.isBlank {
      return chat.subject
    }
    let others = chat.users.filter { $0.id != self.ownUserID }.map(\.name)
    return others.isEmpty ? "Private Chat" : ListFormatter.localizedString(byJoining: others)
  }

  // MARK: Starting, Joining, and Leaving

  /// Starts a private chat, inviting people to it, and gives back its ID. You're in it right away,
  /// and they're in it once they join. A subject's set once it's started, as starting one can't
  /// have one, and it has it, as any subject, once the server says so.
  @MainActor
  func startPrivateChat(with userIDs: [UInt16], subject: String = "") async throws -> UInt32 {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    // Started with the first, and the rest invited to it, as some servers, like Mobius, invite only
    // the first of the people it's started with.
    let chatID = try await client.inviteToNewChat(userIDs: Array(userIDs.prefix(1)))
    if self.privateChat(chatID) == nil {
      self.privateChats.append(PrivateChat(id: chatID, users: self.ownUser.map { [$0] } ?? []))
      self.recordPresence("started the chat", in: self.privateChats.count - 1)
    }
    for userID in userIDs.dropFirst() {
      try await client.inviteToChat(userID: userID, chatID: chatID)
    }
    if !subject.isBlank {
      try await client.setChatSubject(subject, chatID: chatID)
    }
    return chatID
  }

  /// Invites people to a private chat you're in.
  @MainActor
  func inviteToPrivateChat(_ chatID: UInt32, userIDs: [UInt16]) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    for userID in userIDs {
      try await client.inviteToChat(userID: userID, chatID: chatID)
    }
  }

  /// Joins a private chat you're invited to. When it's gone, as when everyone in it has left, so is
  /// the invitation, with an error saying so.
  @MainActor
  func joinPrivateChat(_ chatID: UInt32) async {
    guard let client = self.client else {
      return
    }

    do {
      let (subject, users) = try await client.joinChat(chatID)
      guard let i = self.privateChats.firstIndex(where: { $0.id == chatID }) else {
        return
      }
      var members = users.map { User(hotlineUser: $0) }
      // Servers don't all list you among them.
      if let you = self.ownUser, !members.contains(where: { $0.id == you.id }) {
        members.append(you)
      }
      self.privateChats[i].users = members
      self.privateChats[i].subject = subject
      self.privateChats[i].invitation = nil
      self.privateChats[i].unread = false
      self.recordPresence("joined", in: i)
    }
    catch {
      self.removePrivateChat(chatID)
      self.displayError(error, message: "The private chat is no longer there to join.")
    }
  }

  /// Turns down an invitation to a private chat.
  @MainActor
  func declinePrivateChat(_ chatID: UInt32) async {
    self.removePrivateChat(chatID)
    try? await self.client?.rejectChatInvite(chatID)
  }

  /// Leaves a private chat. With nothing in it kept, it's gone.
  @MainActor
  func leavePrivateChat(_ chatID: UInt32) async {
    self.removePrivateChat(chatID)
    try? await self.client?.leaveChat(chatID)
  }

  private func removePrivateChat(_ chatID: UInt32) {
    self.privateChats.removeAll(where: { $0.id == chatID })
    self.privateChatDrafts[chatID] = nil
  }

  // MARK: Talking

  /// Sets what a private chat's about, for everyone in it. It's what it's about once the server says
  /// so, as it does to everyone in it, you too, which says the server has it.
  @MainActor
  func setPrivateChatSubject(_ subject: String, chatID: UInt32) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.setChatSubject(subject, chatID: chatID)
  }

  /// A line in a private chat about you, like your joining it: your name, as the chat has the
  /// others', and then what you did.
  private func recordPresence(_ what: String, in index: Int) {
    let you = self.ownUser
    var line = ChatMessage(text: "\(you?.name ?? self.username) \(what)", type: .joined, date: Date())
    line.isAdmin = you?.isAdmin ?? false
    self.privateChats[index].messages.append(line)
  }

  @MainActor
  func sendPrivateChat(_ text: String, chatID: UInt32, announce: Bool = false) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.sendChat(text, announce: announce, chatID: chatID)
  }

  func markPrivateChatAsRead(_ chatID: UInt32) {
    if let i = self.privateChats.firstIndex(where: { $0.id == chatID }), self.privateChats[i].unread {
      self.privateChats[i].unread = false
    }
  }

  // MARK: Events

  func handleChatInvitation(chatID: UInt32, userID: UInt16, name: String, subject: String = "") {
    // Turned down for you if you'd rather not be asked. Servers from 1.5.1 on do it themselves, and
    // older ones leave it to the client with an automatic response on, too.
    if Prefs.shared.refusePrivateChat || (self.serverVersion < 151 && Prefs.shared.enableAutomaticMessage) {
      Task {
        try? await self.client?.rejectChatInvite(chatID)
      }
      return
    }
    guard self.privateChat(chatID) == nil else {
      return
    }

    let name = name.isEmpty ? self.users.first(where: { $0.id == userID })?.name ?? "Someone" : name
    self.privateChats.append(PrivateChat(id: chatID, subject: subject, invitation: PrivateChat.Invitation(userID: userID, name: name), unread: true))

    if Prefs.shared.playSounds && Prefs.shared.playChatInvitationSound {
      SoundEffects.play(.serverMessage)
    }

    #if os(macOS)
    if Prefs.shared.showPrivateMessageNotifications && !NSApplication.shared.isActive {
      let content = UNMutableNotificationContent()
      content.title = name
      content.body = "Invited you to a private chat"
      content.sound = .default
      // To your messages with them, where it waits.
      content.userInfo = ["userID": userID]

      let request = UNNotificationRequest(identifier: "chat-invitation-\(chatID)", content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
    #endif
  }

  func handlePrivateChatMessage(chatID: UInt32, text: String) {
    guard let i = self.privateChats.firstIndex(where: { $0.id == chatID }) else {
      return
    }

    var message = ChatMessage(text: text, type: .message, date: Date())
    if let username = message.username,
       let user = self.users.first(where: { $0.name == username }) {
      message.iconID = user.iconID
      message.isAdmin = user.isAdmin
    }
    self.privateChats[i].messages.append(message)
    if self.privateChats[i].messages.count > Self.maxChatMessages {
      self.privateChats[i].messages.removeFirst(self.privateChats[i].messages.count - (Self.maxChatMessages - Self.chatTrimBatch))
    }
    self.privateChats[i].unread = true

    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.chatMessage)
    }

    #if os(macOS)
    // As for a private message, while you're in another app, unless it's yours.
    let isOwnMessage = message.username?.lowercased() == Prefs.shared.username.lowercased()
    if !isOwnMessage && Prefs.shared.showPrivateMessageNotifications && !NSApplication.shared.isActive {
      let content = UNMutableNotificationContent()
      content.title = self.title(of: self.privateChats[i])
      content.body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      content.sound = .default
      content.userInfo = ["type": "privateChat", "chatID": chatID]

      let request = UNNotificationRequest(identifier: "chat-\(chatID)", content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
    #endif
  }

  /// Someone joining a private chat you're in, or their name, icon, or status changing there.
  func handlePrivateChatUserChanged(chatID: UInt32, user hotlineUser: HotlineUser) {
    guard let i = self.privateChats.firstIndex(where: { $0.id == chatID }) else {
      return
    }

    let user = User(hotlineUser: hotlineUser)
    if let j = self.privateChats[i].users.firstIndex(where: { $0.id == user.id }) {
      self.privateChats[i].users[j] = user
    }
    else {
      self.privateChats[i].users.append(user)
      var line = ChatMessage(text: "\(user.name) joined", type: .joined, date: Date())
      line.isAdmin = user.isAdmin
      self.privateChats[i].messages.append(line)
    }
  }

  /// Someone leaving a private chat you're in, which they do too when they leave the server.
  func handlePrivateChatUserLeft(chatID: UInt32, userID: UInt16) {
    guard let i = self.privateChats.firstIndex(where: { $0.id == chatID }),
          let j = self.privateChats[i].users.firstIndex(where: { $0.id == userID }) else {
      return
    }

    let user = self.privateChats[i].users.remove(at: j)
    var line = ChatMessage(text: "\(user.name) left", type: .left, date: Date())
    line.isAdmin = user.isAdmin
    self.privateChats[i].messages.append(line)
  }

  /// A private chat's new subject, whoever set it, you too, and a line in it saying so, once you're in
  /// it. The server doesn't say who.
  func handlePrivateChatSubject(chatID: UInt32, subject: String) {
    guard let i = self.privateChats.firstIndex(where: { $0.id == chatID }),
          self.privateChats[i].subject != subject else {
      return
    }

    self.privateChats[i].subject = subject
    guard self.privateChats[i].invitation == nil else {
      return
    }
    let text = subject.isBlank ? "The subject was cleared" : "Subject changed to “\(subject)”"
    self.privateChats[i].messages.append(ChatMessage(text: text, type: .subject, date: Date()))
  }

  /// Someone's new name, icon, or status, in the private chats they're in, as servers send it only
  /// for the server's user list, with a new name said there, as it is in chat.
  func updatePrivateChats(for user: User, renamedFrom oldName: String?) {
    for i in self.privateChats.indices {
      if let j = self.privateChats[i].users.firstIndex(where: { $0.id == user.id }) {
        self.privateChats[i].users[j] = user
        if let oldName {
          var line = ChatMessage(text: "\(oldName) is now known as \(user.name)", type: .renamed, date: Date())
          line.isAdmin = user.isAdmin
          self.privateChats[i].messages.append(line)
        }
      }
    }
  }

  /// A line in each private chat you're in, as for someone posting to the board, which is news in
  /// all of them. Made for each, as each line is its own.
  func recordInPrivateChats(_ line: () -> ChatMessage) {
    for i in self.privateChats.indices where self.privateChats[i].invitation == nil {
      self.privateChats[i].messages.append(line())
    }
  }

  /// Someone leaving the server, out of the private chats they were in, as not every server says,
  /// and with them, their invitations, which wait with their messages, which are gone too.
  func removeFromPrivateChats(userID: UInt16) {
    self.privateChats.removeAll(where: { $0.invitation?.userID == userID })
    for chat in self.privateChats {
      self.handlePrivateChatUserLeft(chatID: chat.id, userID: userID)
    }
  }
}
