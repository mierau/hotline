import SwiftUI
import UserNotifications

// MARK: - Event Handlers

extension HotlineState {

  func handleChatMessage(_ text: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.chatMessage)
    }

    var chatMessage = ChatMessage(text: text, type: .message, date: Date(), names: self.users.map(\.name))

    if let username = chatMessage.username,
       let user = self.users.first(where: { $0.name == username }) {
      chatMessage.iconID = user.iconID
      chatMessage.isAdmin = user.isAdmin
    }

    self.recordChatMessage(chatMessage)

    // Not your own, which come back to you too.
    let isOwnMessage = chatMessage.username?.lowercased() == Prefs.shared.username.lowercased()
    if !isOwnMessage {
      self.unreadPublicChatCount += 1
    }

    #if os(macOS)
    // Said as what it is, a mention or a word you highlight, when it's one.
    if !isOwnMessage && !self.notifyIfWatched(chatMessage, userInfo: ["type": "chat"]) && Prefs.shared.showChatNotifications {
      // Each in place of the one before, so a busy chat doesn't fill Notification Center.
      self.notify("chat", body: Self.chatLine(chatMessage), userInfo: ["type": "chat"])
    }
    #endif
  }

  func handleUserChanged(_ user: HotlineUser) {
    // Until the user list is in. See `getUserList()`.
    if self.heldUserEvents != nil {
      self.heldUserEvents?.append(.userChanged(user))
      return
    }
    self.addOrUpdateHotlineUser(user)
  }

  func handleUserDisconnected(_ userID: UInt16, playsSound: Bool = true) {
    // Until the user list is in. See `getUserList()`.
    if self.heldUserEvents != nil {
      self.heldUserEvents?.append(.userDisconnected(userID))
      return
    }
    if let existingUserIndex = self.users.firstIndex(where: { $0.id == UInt(userID) }) {
      let user = self.users.remove(at: existingUserIndex)

      // Kept whether or not the chat shows them, so turning them on shows them all.
      var chatMessage = ChatMessage(text: "\(user.name) disconnected", type: .left, date: Date())
      chatMessage.isAdmin = user.isAdmin
      self.recordChatMessage(chatMessage)

      if playsSound && Prefs.shared.playSounds && Prefs.shared.playLeaveSound {
        SoundEffects.play(.userLogout)
      }
    }
    // Their conversation waits for them.
    self.followConversations()
    self.removeFromPrivateChats(userID: userID)
  }

  func handleServerMessage(_ message: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.serverMessage)
    }

    print("HotlineState: received server message:\n\(message)")
    let chatMessage = ChatMessage(text: message, type: .server, date: Date())
    self.recordChatMessage(chatMessage)

    #if os(macOS)
    if Prefs.shared.showBroadcastNotifications {
      self.notify("broadcast-\(chatMessage.id)", body: message, userInfo: ["type": "chat"])
    }
    #endif
  }

  /// A private message from someone: one they wrote, maybe a reply to one of yours, as it quotes
  /// it, or one the server sent for them, like their automatic response. From someone in the user
  /// list, or else by the name the server sends with it, as for someone the list doesn't have.
  func handlePrivateMessage(userID: UInt16, name: String?, message: String, quoting: String? = nil, kind: HotlinePrivateMessageKind = .message) {
    // Until the user list is in, to know who it's from. See `getUserList()`.
    if self.heldUserEvents != nil {
      self.heldUserEvents?.append(.privateMessage(userID: userID, name: name, message: message, quoting: quoting, kind: kind))
      return
    }

    let user = self.users.first(where: { $0.id == userID })
    guard let senderName = user?.name ?? name else {
      return
    }
    print("HotlineState: received private message from \(senderName): \(message)")

    // That they don't take private messages, for one of yours just sent: said on it, rather than as
    // a message of its own.
    if kind == .refusedMessage, let refused = self.conversations.refuse(latestTo: userID, reason: message), let conversation = self.conversations[userID] {
      self.recordPrivateMessage(refused, peerName: conversation.name)
      return
    }

    if Prefs.shared.playPrivateMessageSound {
      if (self.conversations[userID]?.unread ?? 0) == 0 {
        SoundEffects.play(.serverMessage)
      } else {
        SoundEffects.play(.chatMessage)
      }
    }

    let iconID = user?.iconID ?? self.conversations[userID]?.iconID ?? 0
    let instantMessage = InstantMessage(
      direction: .incoming,
      senderName: senderName,
      senderIconID: iconID,
      receiverName: self.username,
      receiverIconID: UInt(self.iconID),
      text: message,
      type: Self.messageType(of: kind),
      date: Date(),
      isRead: false,
      senderIsAdmin: user?.isAdmin ?? false,
      quoting: quoting
    )

    let conversation = self.conversations.file(instantMessage, with: userID, name: senderName, iconID: iconID, unseen: true)
    self.recordPrivateMessage(instantMessage, peerName: conversation.name)

    #if os(macOS)
    if Prefs.shared.showPrivateMessageNotifications {
      // Said when it's not from them, as their automatic response isn't.
      let name = kind == .automaticResponse ? "\(senderName) (Auto-Reply)" : senderName
      self.notify("pm-\(userID)", subtitle: "Private Message", body: "\(name): \(message)", userInfo: ["userID": userID])
    }
    #endif
  }

  /// What kind of message it's kept as, from what the server said it is.
  static func messageType(of kind: HotlinePrivateMessageKind) -> InstantMessageType {
    switch kind {
    case .message:
      .message
    case .automaticResponse:
      .automaticResponse
    case .refusedMessage, .refusedChat:
      .refusal
    }
  }

  func handleNewsPost(_ message: String) {
    let normalized = message.replacing(/\r\n?/, with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

    // Strip divider lines from the incoming post, and the board's own, if it has one.
    let delimiter = self.messageBoardDelimiter
    let cleaned = lines
      .filter { !HotlineClient.isMessageBoardDivider($0) && $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) != delimiter }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if !cleaned.isEmpty {
      let post = MessageBoardPost.parse(cleaned)
      self.messageBoard.insert(post, at: 0)
      self.announceBoardPost(post)

      // Not your own, which comes back to you too.
      let isOwnPost = post.username?.lowercased() == Prefs.shared.username.lowercased()
      if !isOwnPost {
        self.unreadBoardPosts += 1
      }

      #if os(macOS)
      // Clicked, it goes to the post.
      if Prefs.shared.showBoardPostNotifications && !isOwnPost {
        let body = post.username.map { "\($0): \(post.body)" } ?? post.body
        self.notify("board-\(post.id)", subtitle: "New Board Post", body: body, userInfo: ["type": "board", "post": post.reference])
      }
      #endif
    }

    SoundEffects.play(.newNews)
  }
}

// MARK: - Notifications

#if os(macOS)
extension HotlineState {
  /// Posts a notification from this server, while you're in another app: titled with the server's
  /// name, and with `subtitle` saying what it is when that needs saying. It's grouped with the
  /// server's others, and in place of one from the server with the same `identifier`. Clicked, it
  /// brings this server's window forward, to what `userInfo` says.
  func notify(_ identifier: String, subtitle: String? = nil, body: String, userInfo: [String: Any] = [:]) {
    guard !NSApplication.shared.isActive else {
      return
    }

    let content = UNMutableNotificationContent()
    content.title = self.serverTitle
    // With swearing and slurs hidden, as they are in the window, if Settings has them hidden.
    if let subtitle {
      content.subtitle = subtitle.hidingOffensiveWords
    }
    content.body = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)).hidingOffensiveWords
    content.sound = .default
    content.threadIdentifier = self.id.uuidString
    content.userInfo = userInfo.merging(["server": self.id.uuidString]) { $1 }

    let request = UNNotificationRequest(identifier: "\(self.id.uuidString)-\(identifier)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  /// Posts a notification for a message in a chat that mentions you, or a word you highlight, when
  /// those are on, and says whether it did. It looks like the chat's others, with its `subtitle`,
  /// as what it says shows why it came. Only what they said counts, not their name.
  func notifyIfWatched(_ message: ChatMessage, subtitle: String? = nil, userInfo: [String: Any]) -> Bool {
    let text = message.text.lowercased()
    let username = Prefs.shared.username

    if Prefs.shared.showMentionNotifications && !username.isBlank && text.contains(username.lowercased()) {
      self.notify("mention-\(message.id)", subtitle: subtitle, body: Self.chatLine(message), userInfo: userInfo)
      return true
    }

    if Prefs.shared.showWatchWordNotifications,
       let watched = Prefs.shared.watchWords.first(where: { !$0.word.isBlank && text.contains($0.word.lowercased()) }) {
      self.notify("watchword-\(watched.word.lowercased())", subtitle: subtitle, body: Self.chatLine(message), userInfo: userInfo)
      return true
    }

    return false
  }

  /// A message as chat shows it: who said it, then what they said, or an emote as it is.
  static func chatLine(_ message: ChatMessage) -> String {
    message.username.map { "\($0): \(message.text)" } ?? message.text
  }
}
#endif
