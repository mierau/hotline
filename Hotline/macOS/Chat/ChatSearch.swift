import Foundation

/// What a search of the chat finds: messages with some text in them, and for "links" or "files",
/// every message with a link, or a link to a file or folder on a Hotline server, too.
struct ChatSearch {
  let text: String
  /// The links that bring a message into the results whatever its text.
  let kinds: ChatLinkIndex.Kinds

  init(_ query: String) {
    self.text = query
    switch query.trimmingCharacters(in: .whitespaces).lowercased() {
    case "links":
      self.kinds = .link
    case "files":
      self.kinds = .file
    default:
      self.kinds = []
    }
  }

  func matches(_ message: ChatMessage, links: ChatLinkIndex) -> Bool {
    if message.searchText.range(of: self.text, options: [.caseInsensitive, .literal]).location != NSNotFound {
      return true
    }
    return !self.kinds.isEmpty && !links.kinds(in: message).isDisjoint(with: self.kinds)
  }
}

/// Which messages have links, and links to files, worked out once for each, since finding links
/// in a long chat takes a moment.
final class ChatLinkIndex {
  struct Kinds: OptionSet {
    let rawValue: UInt8
    static let link = Kinds(rawValue: 1 << 0)
    static let file = Kinds(rawValue: 1 << 1)
  }

  private var known: [UUID: Kinds] = [:]

  func kinds(in message: ChatMessage) -> Kinds {
    if let kinds = self.known[message.id] {
      return kinds
    }
    var kinds: Kinds = []
    for url in ChatMessageRenderer.links(in: message.text) {
      kinds.insert(.link)
      if ChatMessageRenderer.fileName(ofHotlineLink: url) != nil {
        kinds.insert(.file)
        break
      }
    }
    self.known[message.id] = kinds
    return kinds
  }
}
