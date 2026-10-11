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

  /// How many lines of what's saved a search finds at a time, before more are looked for.
  static let savedPageSize = 100

  /// A page of what's saved of a server's chat that this finds, the newest, or from before the
  /// oldest of `results`, in front of them, as the chat shows them: oldest first, with the
  /// dividers where sessions ended between them. And whether there might be more before.
  @MainActor
  func savedResults(for key: ChatStore.SessionKey, before results: [ChatMessage] = [], links: ChatLinkIndex, showsConnections: Bool) async -> (messages: [ChatMessage], more: Bool) {
    let linkSearch: ChatStore.LinkSearch = self.kinds.contains(.file) ? .files : self.kinds.contains(.link) ? .links : .none
    let first = results.first { $0.type != .signOut }
    let entries = await ChatStore.shared.search(for: key, text: self.text, links: linkSearch, before: first?.date, limit: Self.savedPageSize)
    guard let oldest = entries.last?.date, let newest = entries.first?.date else {
      return (results, false)
    }
    // Told for itself, as for links what's saved only knows which lines might have them.
    let found = entries.reversed().compactMap(ChatMessage.init(entry:)).filter { message in
      (showsConnections || !message.isConnection) && self.matches(message, links: links)
    }
    let dividers = await ChatStore.shared.dividers(for: key, from: oldest, through: first?.date ?? newest).compactMap(ChatMessage.init(entry:))
    let known = Set(results.map(\.id))
    let page = (found + dividers).filter { !known.contains($0.id) }.sorted { $0.date < $1.date }
    return ((page + results).searched { _ in true }, entries.count == Self.savedPageSize)
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
