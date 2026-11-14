import SwiftUI

enum InstantMessageType: String {
  /// Written by whoever sent it.
  case message
  /// Their automatic response, sent back by the server for a message of yours.
  case automaticResponse
  /// That they don't take private messages, or private chat, sent back by the server.
  case refusal
}

/// Whether one of yours got to them, as the server says.
enum InstantMessageDelivery: Equatable {
  /// On its way, till the server says.
  case sending
  /// The server has it, and passed it on to them.
  case delivered
  /// The server didn't say, as one might not, while they were still on it, so most likely
  /// delivered.
  case unconfirmed
  /// The server turned it away, or they'd gone, or they don't take private messages, with why, when
  /// that's known.
  case notDelivered(String?)

  /// As it's saved, with why it wasn't delivered apart. See `init(saved:reason:)`.
  var saved: String {
    switch self {
    case .sending:
      "sending"
    case .delivered:
      "delivered"
    case .unconfirmed:
      "unconfirmed"
    case .notDelivered:
      "notDelivered"
    }
  }

  /// Why it wasn't delivered, when it wasn't, and that's known.
  var reason: String? {
    if case .notDelivered(let reason) = self {
      return reason
    }
    return nil
  }

  /// As it was saved, if it was. One saved on its way is unconfirmed now, as the server's answer, if
  /// it came, came to a visit that's over.
  init?(saved: String?, reason: String?) {
    switch saved {
    case "sending", "unconfirmed":
      self = .unconfirmed
    case "delivered":
      self = .delivered
    case "notDelivered":
      self = .notDelivered(reason)
    default:
      return nil
    }
  }
}

enum InstantMessageDirection {
  case incoming
  case outgoing
}

struct InstantMessage: Identifiable {
  let id: UUID
  let direction: InstantMessageDirection
  let senderName: String
  let senderIconID: UInt
  let receiverName: String
  let receiverIconID: UInt
  let text: String
  let type: InstantMessageType
  /// When it was sent, or, for one of yours sent again, when it was last.
  var date: Date
  var isRead: Bool
  let senderIsAdmin: Bool
  /// The message it's a reply to, as it quotes it, when it's a reply.
  let quoting: String?
  /// Whether it got to them, for one of yours sent since the server's been asked, and nil for
  /// theirs, and for yours from before.
  var delivery: InstantMessageDelivery?

  init(id: UUID = UUID(), direction: InstantMessageDirection, senderName: String, senderIconID: UInt = 0, receiverName: String = "", receiverIconID: UInt = 0, text: String, type: InstantMessageType, date: Date, isRead: Bool = true, senderIsAdmin: Bool = false, quoting: String? = nil, delivery: InstantMessageDelivery? = nil) {
    self.id = id
    self.direction = direction
    self.senderName = senderName
    self.senderIconID = senderIconID
    self.receiverName = receiverName
    self.receiverIconID = receiverIconID
    self.text = text
    self.type = type
    self.date = date
    self.isRead = isRead
    self.senderIsAdmin = senderIsAdmin
    self.quoting = quoting
    self.delivery = delivery
  }

  /// Whether it can be replied to: what someone wrote, and not what the server sent for them.
  var canBeRepliedTo: Bool {
    self.type == .message
  }

  // MARK: - Quoting

  /// As much of a quote as the original server keeps of one, in bytes, which is as much as a reply
  /// quotes, so what it quotes is what arrives.
  static let maximumQuoteLength = 4_000

  /// What a reply to a message quotes of it: all it says, or, for a long one, as much as fits.
  static func quote(of text: String) -> String {
    let text = Self.normalized(text)
    guard text.utf8.count > Self.maximumQuoteLength else {
      return text
    }
    var quote = ""
    for character in text {
      guard quote.utf8.count + String(character).utf8.count <= Self.maximumQuoteLength else {
        break
      }
      quote.append(character)
    }
    return quote
  }

  /// Whether a reply's quote is of this message: all of what it says, with its line breaks however
  /// they came, or the start of it, for a long one cut short.
  func isQuoted(by quote: String) -> Bool {
    let quote = Self.normalized(quote)
    let text = Self.normalized(self.text)
    guard !quote.isEmpty else {
      return false
    }
    return quote == text || (quote.utf8.count >= 200 && text.hasPrefix(quote))
  }

  /// With new lines as line feeds, as they come as returns, and without the space around it.
  private static func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Conversations

/// A private conversation with someone on a server: what the two of you have said, and who they are
/// there now. It's with them, not with the user ID the server gives them, which is theirs only for
/// as long as they're connected, so it waits while they're gone, and goes on once they're back, as
/// whoever comes with their name.
struct PrivateConversation: Identifiable {
  let id = UUID()
  /// Who they are on the server, to send to, while they're on it, and nil once they've gone.
  var userID: UInt16?
  /// Their name as it is now, or as it was when they left.
  var name: String
  var iconID: UInt
  var messages: [InstantMessage] = []
  /// How many of their messages you haven't seen.
  var unread = 0
  /// Whether what was saved of it on earlier visits has been read back into it, as that's done once.
  var restored = false
  /// When they left, in the order people come and go, as only someone who comes after takes it up.
  /// See `PrivateConversations.follow(_:)`.
  fileprivate var left: Int?
}

/// Your private conversations on a server, each with someone, as people come, go, come back and
/// change their names.
struct PrivateConversations {
  private var conversations: [UUID: PrivateConversation] = [:]
  /// Which conversation each user ID seen this visit is, those of people who've gone too, so what had
  /// their ID, like the notification of a message of theirs, still finds it.
  private var byUserID: [UInt16: UUID] = [:]
  /// When each person here came, in the order people come and go, to tell who's come since someone
  /// left.
  private var arrivals: [UInt16: Int] = [:]
  private var clock = 0

  /// The conversation with whoever has the user ID, or had it, this visit.
  subscript(userID: UInt16) -> PrivateConversation? {
    self.byUserID[userID].flatMap { self.conversations[$0] }
  }

  /// The conversation with whoever has the user ID, or a new one with them, by the name and icon
  /// they have.
  mutating func start(with userID: UInt16, name: String, iconID: UInt) -> PrivateConversation {
    // Theirs, or theirs from before they left, or came back as another ID, as an ID given to
    // someone else since has none till they start one. See `follow(_:)`.
    if let conversation = self[userID] {
      return conversation
    }
    let conversation = PrivateConversation(userID: userID, name: name, iconID: iconID)
    self.conversations[conversation.id] = conversation
    self.byUserID[userID] = conversation.id
    return conversation
  }

  /// Puts a message, to or from whoever has the user ID, in their conversation, and counts it among
  /// those you haven't seen, when it's one.
  @discardableResult
  mutating func file(_ message: InstantMessage, with userID: UInt16, name: String, iconID: UInt, unseen: Bool = false) -> PrivateConversation {
    let id = self.start(with: userID, name: name, iconID: iconID).id
    self.update(id) { conversation in
      conversation.messages.append(message)
      if unseen {
        conversation.unread += 1
      }
    }
    return self.conversations[id]!
  }

  /// Changes the conversation, where it is, as a copy of its messages would cost a copy of them all.
  mutating func update(_ id: UUID, _ change: (inout PrivateConversation) -> Void) {
    if self.conversations[id] != nil {
      change(&self.conversations[id]!)
    }
  }

  /// Says whether one of yours, to whoever has or had the user ID, got to them, once the server
  /// answers, unless it's been said already that it didn't, as a refusal can come before the
  /// answer. Gives the message as it is now, when it changed, to save.
  @discardableResult
  mutating func deliver(_ messageID: UUID, with userID: UInt16, as delivery: InstantMessageDelivery) -> InstantMessage? {
    guard let id = self.byUserID[userID] else {
      return nil
    }
    var delivered: InstantMessage?
    self.update(id) { conversation in
      guard let i = conversation.messages.lastIndex(where: { $0.id == messageID }), conversation.messages[i].delivery == .sending else {
        return
      }
      conversation.messages[i].delivery = delivery
      delivered = conversation.messages[i]
    }
    return delivered
  }

  /// Puts one of yours that didn't get to them on its way again, as of `date`, after all that's been
  /// said since, as it's said again now. Gives it as it is now, to send and save.
  mutating func resend(_ messageID: UUID, with userID: UInt16, at date: Date = .now) -> InstantMessage? {
    guard let id = self.byUserID[userID] else {
      return nil
    }
    var resent: InstantMessage?
    self.update(id) { conversation in
      guard let i = conversation.messages.firstIndex(where: { $0.id == messageID }), case .notDelivered? = conversation.messages[i].delivery else {
        return
      }
      var message = conversation.messages.remove(at: i)
      message.date = date
      message.delivery = .sending
      conversation.messages.append(message)
      resent = message
    }
    return resent
  }

  /// How long after one of yours a server's saying they don't take private messages is about it.
  static let refusalWindow: TimeInterval = 60

  /// Says your latest message to whoever has the user ID didn't get to them, and why, as a server
  /// says once they don't take private messages, for a message of yours, whether before or after it
  /// answers that it has it. Gives the message as it is now, to save, or nil if there's none sent
  /// in the last minute, for what the server said to stand on its own.
  mutating func refuse(latestTo userID: UInt16, reason: String, now: Date = .now) -> InstantMessage? {
    guard let id = self.byUserID[userID] else {
      return nil
    }
    var refused: InstantMessage?
    self.update(id) { conversation in
      guard let i = conversation.messages.lastIndex(where: { $0.direction == .outgoing && $0.delivery != nil }),
            now.timeIntervalSince(conversation.messages[i].date) < Self.refusalWindow else {
        return
      }
      switch conversation.messages[i].delivery {
      case .sending, .delivered, .unconfirmed:
        conversation.messages[i].delivery = .notDelivered(reason)
        refused = conversation.messages[i]
      default:
        break
      }
    }
    return refused
  }

  /// Follows people as they are on the server now, given who's on it: each conversation goes on with
  /// its person, under the name they have now, waits for them once they've gone, and goes to whoever
  /// comes after them with their name. Says whether anything changed.
  @discardableResult
  mutating func follow(_ users: [User]) -> Bool {
    var changed = false
    let here = Set(users.map(\.id))

    // Those who've gone, as of now.
    let now = self.clock
    for (id, conversation) in self.conversations {
      if let userID = conversation.userID, !here.contains(userID) {
        self.update(id) { conversation in
          conversation.userID = nil
          conversation.left = now
        }
        changed = true
      }
    }
    // Their IDs, which are someone new's if they're given out again.
    for userID in self.arrivals.keys where !here.contains(userID) {
      self.arrivals[userID] = nil
      changed = true
    }

    // Those who've come, in the order they're seen.
    for user in users where self.arrivals[user.id] == nil {
      self.clock += 1
      self.arrivals[user.id] = self.clock
      changed = true
    }

    for user in users {
      if let id = self.byUserID[user.id], let conversation = self.conversations[id] {
        if conversation.userID == user.id {
          // Theirs, as they are now.
          if conversation.name != user.name || conversation.iconID != user.iconID {
            self.update(id) { conversation in
              conversation.name = user.name
              conversation.iconID = user.iconID
            }
            changed = true
          }
          continue
        }
        // From before they had the ID: someone else's, or theirs from before they left, which goes
        // to them again below, as anyone's would.
        self.byUserID[user.id] = nil
        changed = true
      }
      // Of those waiting for someone with their name since before they came, the latest said.
      guard let arrival = self.arrivals[user.id] else {
        continue
      }
      let waiting = self.conversations.values.filter { conversation in
        guard conversation.userID == nil, conversation.name == user.name, !conversation.messages.isEmpty, let left = conversation.left else {
          return false
        }
        return left < arrival
      }
      let latest = waiting.max { first, second in
        let firstSaid: Date = first.messages.last?.date ?? .distantPast
        let secondSaid: Date = second.messages.last?.date ?? .distantPast
        return firstSaid < secondSaid
      }
      if let latest {
        self.update(latest.id) { conversation in
          conversation.userID = user.id
          conversation.iconID = user.iconID
        }
        self.byUserID[user.id] = latest.id
        changed = true
      }
    }
    return changed
  }
}
