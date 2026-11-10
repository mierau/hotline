import SwiftUI

enum InstantMessageType: String {
  /// Written by whoever sent it.
  case message
  /// Their automatic response, sent back by the server for a message of yours.
  case automaticResponse
  /// That they don't take private messages, or private chat, sent back by the server.
  case refusal
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
  let date: Date
  var isRead: Bool
  let senderIsAdmin: Bool
  /// The message it's a reply to, as it quotes it, when it's a reply.
  let quoting: String?

  init(id: UUID = UUID(), direction: InstantMessageDirection, senderName: String, senderIconID: UInt = 0, receiverName: String = "", receiverIconID: UInt = 0, text: String, type: InstantMessageType, date: Date, isRead: Bool = true, senderIsAdmin: Bool = false, quoting: String? = nil) {
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
