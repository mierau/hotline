import SwiftUI

enum ChatMessageType {
  case agreement
  case joined
  case left
  /// Someone changing their name.
  case renamed
  /// Someone posting to the message board.
  case boardPost
  /// A private chat's subject changing.
  case subject
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
    case .subject:
      return "subject"
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
    case "subject":
      self = .subject
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

  /// Someone connecting or disconnecting, which the chat can be set not to show. They're kept
  /// either way, so turning them back on shows them all.
  var isConnection: Bool {
    self.type == .joined || self.type == .left
  }

  /// - Parameter names: The names of the people it could be from, those on the server, so it's from
  ///   the one whose whole name it starts with, rather than from whoever has the start of someone's
  ///   name with a colon in it, like "Dustin: new server at…".
  init(text: String, type: ChatMessageType, date: Date, id: UUID = UUID(), names: [String] = []) {
    self.id = id
    self.type = type
    self.date = date
    self.iconID = nil
    self.isAdmin = false
    self.metadata = nil

    // An emote before a name and what they said, as one with a link in it has a colon too.
    if
      type == .message,
      text.firstMatch(of: ChatMessage.emoteParser) != nil {
      self.username = nil
      self.text = text
      self.isEmote = true
    }
    else if
      type == .message,
      let (name, said) = Self.sender(of: text, among: names) {
      self.username = name
      self.text = said
      self.isEmote = false
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

  /// Who said a line of chat, "name:  what they said", and what: the longest of `names` it starts
  /// with, and a colon after it, or otherwise what's before its first colon.
  static func sender(of line: String, among names: [String]) -> (name: String, text: String)? {
    let start = line.drop(while: \.isWhitespace)
    // The longest, as one that starts with someone else's name, and a colon, is still its own.
    guard let name = names.filter({ !$0.isEmpty && start.hasPrefix($0 + ":") }).max(by: { $0.count < $1.count }) else {
      return line.firstMatch(of: Self.parser).map { (String($0.1), String($0.2)) }
    }
    let said = start.dropFirst(name.count + 1)
    let text = said.drop(while: \.isWhitespace)
    // Only spaces, kept, or nothing at all, which isn't something anyone said.
    guard !said.isEmpty else {
      return nil
    }
    return (name, String(text.isEmpty ? said : text))
  }
}

extension ChatMessage {
  /// A message as it was saved in the chat store, or nil for a kind of message that isn't kept.
  init?(entry: ChatStore.Entry) {
    guard let type = ChatMessageType(storageKey: entry.type) else {
      return nil
    }
    if type == .message, let username = entry.username, !username.isEmpty {
      // An emote with a link in it, saved before emotes were told apart first as if what came
      // before the link's colon were a name, put back as it was.
      let separator = username.firstMatch(of: ChatMessage.emoteParser) != nil && entry.body.hasPrefix("//") ? ":" : ": "
      // From who it was saved as being from, even with a colon in their name.
      self.init(text: username + separator + entry.body, type: type, date: entry.date, id: entry.id, names: [username])
    }
    else {
      self.init(text: entry.body, type: type, date: entry.date, id: entry.id)
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
