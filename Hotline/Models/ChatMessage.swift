import SwiftUI

enum ChatMessageType {
  case agreement
  case joined
  case left
  /// Someone changing their name.
  case renamed
  /// Someone posting to the message board.
  case boardPost
  case message
  case server
  case signOut
}

extension ChatMessageType {
  var storageKey: String {
    switch self {
    case .agreement:
      return "agreement"
    case .joined:
      return "joined"
    case .left:
      return "left"
    case .renamed:
      return "renamed"
    case .boardPost:
      return "boardPost"
    case .message:
      return "message"
    case .server:
      return "server"
    case .signOut:
      return "signOut"
    }
  }

  init?(storageKey: String) {
    switch storageKey {
    case "agreement":
      self = .agreement
    case "joined":
      self = .joined
    case "left":
      self = .left
    case "renamed":
      self = .renamed
    case "boardPost":
      self = .boardPost
    case "message":
      self = .message
    case "server":
      self = .server
    case "signOut":
      self = .signOut
    default:
      return nil
    }
  }
}

struct ChatMessage: Identifiable {
  let id: UUID

  let text: String
  let type: ChatMessageType
  let date: Date
  let username: String?
  let isEmote: Bool
  var iconID: UInt?
  var isAdmin: Bool
  var metadata: ChatStore.EntryMetadata?
  /// The sender's name and the text, for searching. An NSString, since searching a Swift string
  /// converts it to one each time, which made that most of the work of searching a long chat.
  let searchText: NSString

  static let parser = /^\s*([^\:]+):\s*([\s\S]+)$/
  static let emoteParser = /^\s*\*{3}\s+(.+)$/

  init(text: String, type: ChatMessageType, date: Date) {
    self.id = UUID()
    self.type = type
    self.date = date
    self.iconID = nil
    self.isAdmin = false
    self.metadata = nil

    if
      type == .message,
      let match = text.firstMatch(of: ChatMessage.parser) {
      self.username = String(match.1)
      self.text = String(match.2)
      self.isEmote = false
    }
    else if
      type == .message,
      text.firstMatch(of: ChatMessage.emoteParser) != nil {
      self.username = nil
      self.text = text
      self.isEmote = true
    }
    else {
      self.username = nil
      self.text = text
      self.isEmote = false
    }

    // With links decoded too, so a file's name finds a link to it, spaces and all.
    let body = self.text
    var searchText = body
    if let username = self.username {
      searchText = "\(username)\n\(body)"
    }
    if body.contains("%"), let decoded = body.removingPercentEncoding, decoded != body {
      searchText += "\n" + decoded
    }
    self.searchText = NSString(string: searchText)
  }
}

extension ChatMessage {
  /// A message as it was saved in the chat store, or nil for a kind of message that isn't kept.
  init?(entry: ChatStore.Entry) {
    guard let type = ChatMessageType(storageKey: entry.type) else {
      return nil
    }
    if type == .message, let username = entry.username, !username.isEmpty {
      self.init(text: "\(username): \(entry.body)", type: type, date: entry.date)
    }
    else {
      self.init(text: entry.body, type: type, date: entry.date)
    }
    self.metadata = entry.metadata
    self.iconID = entry.metadata?.iconID
    self.isAdmin = entry.metadata?.senderIsAdmin ?? false
  }
}

extension Array where Element == ChatMessage {
  /// The messages that `matches` finds, in order, along with the disconnects between them that
  /// show where sessions end.
  func searched(where matches: (ChatMessage) -> Bool) -> [ChatMessage] {
    var results: [ChatMessage] = []
    var lastWasDisconnect = false
    for message in self where message.type != .agreement {
      let isDisconnect = message.type == .signOut
      // One disconnect at a time, without the messages in between.
      if isDisconnect ? lastWasDisconnect : !matches(message) {
        continue
      }
      results.append(message)
      lastWasDisconnect = isDisconnect
    }

    // Disconnects only between results.
    if results.first?.type == .signOut {
      results.removeFirst()
    }
    if results.last?.type == .signOut {
      results.removeLast()
    }
    return results
  }
}
