import SwiftUI
import UserNotifications

// MARK: - Event Handlers

extension HotlineState {

  func handleChatMessage(_ text: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.chatMessage)
    }

    var chatMessage = ChatMessage(text: text, type: .message, date: Date())

    if let username = chatMessage.username,
       let user = self.users.first(where: { $0.name == username }) {
      chatMessage.iconID = user.iconID
      chatMessage.isAdmin = user.isAdmin
    }

    self.recordChatMessage(chatMessage)
    self.unreadPublicChat = true

    #if os(macOS)
    let senderName = chatMessage.username
    let ownUsername = Prefs.shared.username
    let isOwnMessage = senderName?.lowercased() == ownUsername.lowercased()

    if !isOwnMessage && !NSApplication.shared.isActive {
      let lowercasedText = text.lowercased()
      var didNotify = false

      // Check for mention of our username
      if Prefs.shared.showMentionNotifications
          && !ownUsername.isEmpty
          && lowercasedText.contains(ownUsername.lowercased()) {
        let content = UNMutableNotificationContent()
        content.title = senderName.map { "\($0) mentioned you" } ?? "You were mentioned"
        content.body = String(chatMessage.text.prefix(200))
        content.sound = .default
        content.userInfo = ["type": "mention"]

        let request = UNNotificationRequest(identifier: "mention-\(chatMessage.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        didNotify = true
      }

      // Check for watch words (skip if we already notified for a mention)
      let watchWords = Prefs.shared.watchWords
      if !didNotify && !watchWords.isEmpty && Prefs.shared.showWatchWordNotifications {
        for highlightWord in watchWords {
          if lowercasedText.contains(highlightWord.word.lowercased()) {
            let content = UNMutableNotificationContent()
            content.title = senderName ?? "Watch Word: \(highlightWord.word)"
            content.body = String(chatMessage.text.prefix(200))
            content.sound = .default
            content.userInfo = ["type": "watchWord"]

            let identifier = "watchword-\(highlightWord.word.hashValue)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            break
          }
        }
      }
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
    self.removeFromPrivateChats(userID: userID)
  }

  func handleServerMessage(_ message: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.serverMessage)
    }

    print("HotlineState: received server message:\n\(message)")
    let chatMessage = ChatMessage(text: message, type: .server, date: Date())
    self.recordChatMessage(chatMessage)
  }

  func handlePrivateMessage(userID: UInt16, message: String) {
    if let existingUserIndex = self.users.firstIndex(where: { $0.id == UInt(userID) }) {
      let user = self.users[existingUserIndex]
      print("HotlineState: received private message from \(user.name): \(message)")

      if Prefs.shared.playPrivateMessageSound {
        if self.unreadPrivateMessages[userID] == nil {
          SoundEffects.play(.serverMessage)
        } else {
          SoundEffects.play(.chatMessage)
        }
      }

      let instantMessage = InstantMessage(
        direction: .incoming,
        senderName: user.name,
        senderIconID: user.iconID,
        receiverName: self.username,
        receiverIconID: UInt(self.iconID),
        text: message,
        type: .message,
        date: Date(),
        isRead: false,
        senderIsAdmin: user.isAdmin
      )

      if self.privateMessages[userID] == nil {
        self.privateMessages[userID] = [instantMessage]
      } else {
        self.privateMessages[userID]!.append(instantMessage)
      }

      self.recordPrivateMessage(instantMessage, userID: userID, peerName: user.name)
      self.unreadPrivateMessages[userID] = userID

      #if os(macOS)
      if Prefs.shared.showPrivateMessageNotifications && !NSApplication.shared.isActive {
        let content = UNMutableNotificationContent()
        content.title = user.name
        content.body = String(message.prefix(200))
        content.sound = .default
        content.userInfo = ["userID": userID]

        let request = UNNotificationRequest(identifier: "pm-\(userID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
      }
      #endif
    }
  }

  func handleNewsPost(_ message: String) {
    let normalized = message.replacing(/\r\n?/, with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
    let dividerRegex = /^[ \t]*([_\-=~*]{15,}|[_\-=~*]{5,}.+[_\-=~*]{5,})[ \t]*$/

    // Strip divider lines from the incoming post
    let cleaned = lines
      .filter { $0.wholeMatch(of: dividerRegex) == nil }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if !cleaned.isEmpty {
      let post = MessageBoardPost.parse(cleaned)
      self.messageBoard.insert(post, at: 0)
      self.announceBoardPost(post)
    }

    SoundEffects.play(.newNews)
  }
}
