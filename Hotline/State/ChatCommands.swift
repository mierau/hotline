import Foundation

/// A command typed in chat in place of a message: a slash and its name at the start, like
/// “/me waves”, for what the menus do, like a private message to someone, without leaving the chat.
enum ChatCommand: String, CaseIterable, Identifiable {
  case me
  case msg
  case away
  case back
  /// /name, which changes yours.
  case rename = "name"
  case icon
  case invite
  case topic
  case leave
  case info
  case broadcast
  case kick
  case ban

  var id: Self {
    self
  }

  /// As it's typed, with its slash.
  var name: String {
    "/" + self.rawValue
  }

  /// The other names it goes by, without their slashes, as other chat apps have them.
  var aliases: [String] {
    switch self {
    case .msg:
      return ["pm", "tell"]
    case .away:
      return ["afk"]
    case .rename:
      return ["nick"]
    case .topic:
      return ["subject"]
    case .info:
      return ["whois"]
    default:
      return []
    }
  }

  /// What's typed after a command's name.
  enum Argument: Equatable {
    case none
    /// Words, which it needs.
    case text
    /// Words, which it can do without.
    case optionalText
    /// Someone, by name, and for /msg, what to say to them after it.
    case person(thenText: Bool)
    /// People, by name, one after another, and in the public chat, a subject after them.
    case people
    /// An icon, by its number, or chosen from all of them.
    case icon
  }

  var argument: Argument {
    switch self {
    case .me, .rename, .topic, .broadcast:
      return .text
    case .msg:
      return .person(thenText: true)
    case .away:
      return .optionalText
    case .back, .leave:
      return .none
    case .icon:
      return .icon
    case .invite:
      return .people
    case .info, .kick, .ban:
      return .person(thenText: false)
    }
  }

  /// What's typed after its name, as the list of commands shows it, and the field, until it's typed.
  func placeholder(inPrivateChat: Bool) -> String {
    switch self {
    case .me:
      return "action"
    case .msg:
      return "name message"
    case .away, .broadcast:
      return "message"
    case .back, .leave:
      return ""
    case .rename, .info, .kick, .ban:
      return "name"
    case .icon:
      return "number"
    case .invite:
      return inPrivateChat ? "names" : "names subject"
    case .topic:
      return "subject"
    }
  }

  /// What it does, for the list of commands, as it does it in a private chat, or the public one.
  func summary(inPrivateChat: Bool) -> String {
    switch self {
    case .me:
      return "Send as an action"
    case .msg:
      return "Send a private message"
    case .away:
      return "Turn on auto-reply"
    case .back:
      return "Turn off auto-reply"
    case .rename:
      return "Change your name"
    case .icon:
      return "Change your icon"
    case .invite:
      return inPrivateChat ? "Invite people to this chat" : "Start a private chat"
    case .topic:
      return "Change this chat’s subject"
    case .leave:
      return "Leave this chat"
    case .info:
      return "Get someone’s info"
    case .broadcast:
      return "Send a message to everyone"
    case .kick:
      return "Disconnect someone"
    case .ban:
      return "Ban someone"
    }
  }

  /// The command a word after a slash is, by its name or another it goes by, in any case.
  init?(word: String) {
    let word = word.lowercased()
    guard let command = Self.allCases.first(where: { $0.answers(to: word) }) else {
      return nil
    }
    self = command
  }

  /// Whether it goes by a word, already in lowercase.
  func answers(to word: String) -> Bool {
    self.rawValue == word || self.aliases.contains(word)
  }
}

/// Where a command's typed, and what you can do there: which commands there are, and who they can
/// be for.
struct ChatCommandContext {
  /// The private chat it's typed in, or nil for the public chat.
  var privateChatID: UInt32? = nil
  /// Who's in the private chat.
  var members: Set<UInt16> = []
  /// What your account can do.
  var access: HotlineUserAccessOptions = []
  /// Everyone on the server, you too, the ones who spoke here last first.
  var people: [User] = []
  /// You, among them.
  var ownUserID: UInt16? = nil
  /// Whether auto-reply's on, and what it replies with.
  var automaticResponseOn = false
  var automaticResponse = ""

  var isPrivateChat: Bool {
    self.privateChatID != nil
  }
}

// MARK: - What Can Be Run

extension ChatCommand {
  /// Why it can't be run where it's typed, or nil when it can: a private chat's own only in one,
  /// and the rest only when your account can do what they do.
  func unavailable(in context: ChatCommandContext) -> String? {
    switch self {
    case .topic:
      return context.isPrivateChat ? nil : "Only a private chat has a subject."
    case .leave:
      return context.isPrivateChat ? nil : "Only a private chat can be left. To leave the server, disconnect."
    case .msg:
      return context.access.contains(.canSendMessages) ? nil : "Your account can’t send private messages."
    case .invite:
      return context.access.contains(.canCreateChat) ? nil : "Your account can’t start private chats."
    case .info:
      return context.access.contains(.canGetClientInfo) ? nil : "Your account can’t get people’s info."
    case .broadcast:
      return context.access.contains(.canBroadcast) ? nil : "Your account can’t broadcast."
    case .kick:
      return context.access.contains(.canDisconnectUsers) ? nil : "Your account can’t disconnect people."
    case .ban:
      return context.access.contains(.canDisconnectUsers) ? nil : "Your account can’t ban people."
    case .me, .away, .back, .rename, .icon:
      return nil
    }
  }

  /// Whether it's in the list of commands where it's typed: when it can be run there, and /back
  /// only while auto-reply's on.
  func isListed(in context: ChatCommandContext) -> Bool {
    self.unavailable(in: context) == nil && (self != .back || context.automaticResponseOn)
  }

  /// The commands whose names, or the others they go by, start with what's typed of one, in the
  /// list's order, but for the one it is, when it's one, which comes first.
  static func matching(_ typed: String, in context: ChatCommandContext) -> [ChatCommand] {
    let typed = typed.lowercased()
    let matches = Self.allCases.filter { command in
      command.isListed(in: context) && ([command.rawValue] + command.aliases).contains { $0.hasPrefix(typed) }
    }
    return matches.filter { $0.answers(to: typed) } + matches.filter { !$0.answers(to: typed) }
  }

  /// The commands a word after a slash that isn't one might have been meant as: the ones it's the
  /// start of, as when Return comes before the rest of the name, and the ones it's a letter off.
  static func suggestions(for word: String, in context: ChatCommandContext) -> [ChatCommand] {
    let word = word.lowercased()
    return Self.allCases.filter { command in
      command.isListed(in: context) && ([command.rawValue] + command.aliases).contains { $0.hasPrefix(word) || Self.isALetterOff(word, $0) }
    }
  }

  /// Whether two words are a letter apart: one more, one less, one different, or two side by side
  /// swapped.
  static func isALetterOff(_ a: String, _ b: String) -> Bool {
    let a = Array(a)
    let b = Array(b)
    guard a != b else {
      return false
    }
    if a.count == b.count {
      let different = a.indices.filter { a[$0] != b[$0] }
      return different.count == 1
        || (different.count == 2 && different[1] == different[0] + 1 && a[different[0]] == b[different[1]] && a[different[1]] == b[different[0]])
    }
    guard abs(a.count - b.count) == 1 else {
      return false
    }
    // The shorter is the longer without one of its letters.
    let (short, long) = a.count < b.count ? (a, b) : (b, a)
    var same = 0
    while same < short.count, short[same] == long[same] {
      same += 1
    }
    return short[same...] == long[(same + 1)...]
  }
}

// MARK: - Reading What's Typed

/// What's typed in chat, read for a command.
enum ChatCommandInput: Equatable {
  /// A message, to send as it's typed, but for one that starts with two slashes, which loses one,
  /// so a message can start with a slash without being taken for a command.
  case message(String)
  /// A command, and what's typed after its name.
  case command(ChatCommand, arguments: String)
  /// /help, which lists the commands.
  case help
  /// A word after a slash that isn't a command, but might have been meant as one of these.
  case unknown(String, suggestions: [ChatCommand])

  init(_ text: String, in context: ChatCommandContext) {
    if text.hasPrefix("//") {
      self = .message(String(text.dropFirst()))
      return
    }
    guard let (word, arguments) = Self.split(text) else {
      self = .message(text)
      return
    }
    if let command = ChatCommand(word: word) {
      self = .command(command, arguments: arguments)
    }
    else if ["help", "?"].contains(word.lowercased()) {
      self = .help
    }
    else {
      // A slash and a word that's nothing like a command, like “/Uploads is full”, goes as it is,
      // as do commands that servers, or someone's bot, might have of their own.
      let suggestions = ChatCommand.suggestions(for: word, in: context)
      self = suggestions.isEmpty ? .message(text) : .unknown(word, suggestions: suggestions)
    }
  }

  /// The word after the slash a command starts with, and what's typed after it, without the space
  /// between, or nil for text that doesn't start with a slash and a word.
  static func split(_ text: String) -> (word: String, arguments: String)? {
    guard text.hasPrefix("/"), !text.hasPrefix("//") else {
      return nil
    }
    let rest = text.dropFirst()
    let word = rest.prefix { !$0.isWhitespace }
    guard !word.isEmpty else {
      return nil
    }
    return (String(word), rest.dropFirst(word.count).trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

/// Where the caret is in a command being typed, for what the list above the field shows: in the
/// command's name, with what's typed of it, and all of the word, for a name to go in place of; in
/// the name of who it's for, the same way; in an icon's number; or past them.
enum ChatCommandPlace: Equatable {
  case name(typed: String, range: NSRange)
  case person(ChatCommand, typed: String, range: NSRange)
  case icon(typed: String, range: NSRange)
  case after(ChatCommand)

  /// Where the caret is in the command `text` starts with, or nil when it doesn't start with one, or
  /// the caret's past its first line. Who it's for is being typed while what's typed is the start of
  /// a name of someone it can be for, or of a word in one, until it's a whole name and a space, and
  /// for /invite, the next name after that, while there's one being typed.
  init?(text: String, caret: Int, in context: ChatCommandContext) {
    let string = text as NSString
    guard caret >= 1, caret <= string.length, string.character(at: 0) == Self.slash,
          string.length < 2 || string.character(at: 1) != Self.slash else {
      return nil
    }
    let lineEnd = string.rangeOfCharacter(from: .newlines).location
    guard lineEnd == NSNotFound || caret <= lineEnd else {
      return nil
    }

    // The command's name: the word after the slash.
    var end = 1
    while end < string.length, !Self.isSpace(string.character(at: end)) {
      end += 1
    }
    if caret <= end {
      self = .name(typed: string.substring(with: NSRange(location: 1, length: caret - 1)), range: NSRange(location: 1, length: end - 1))
      return
    }
    guard let command = ChatCommand(word: string.substring(with: NSRange(location: 1, length: end - 1))) else {
      return nil
    }
    switch command.argument {
    case .person, .people, .icon:
      break
    default:
      self = .after(command)
      return
    }

    // What's typed for it: from past the spaces after the name to the caret, and on to the end of
    // the word the caret's in.
    var start = end
    while start < caret, Self.isSpace(string.character(at: start)) {
      start += 1
    }
    var wordEnd = caret
    while wordEnd < string.length, !Self.isSpace(string.character(at: wordEnd)) {
      wordEnd += 1
    }
    var typed = string.substring(with: NSRange(location: start, length: caret - start))
    let people = command.candidates(in: context)

    switch command.argument {
    case .icon:
      // Its number, or nothing yet.
      guard typed.allSatisfy({ $0.isASCII && $0.isNumber }) else {
        self = .after(command)
        return
      }
      self = .icon(typed: typed, range: NSRange(location: start, length: wordEnd - start))

    case .people:
      // Past the names before it, which are done.
      let named = ChatCommand.names(in: typed, among: context.people, typing: true)
      typed = (typed as NSString).substring(from: named.restStart)
      start += named.restStart
      // Someone's, while it's the start of their name, or a word in it. Everyone's, with nothing
      // typed, for the first, as after that, what's typed could be a subject.
      guard typed.isEmpty ? named.names.isEmpty : !ChatCommand.people(matching: typed, among: people).isEmpty else {
        self = .after(command)
        return
      }
      self = .person(command, typed: typed, range: NSRange(location: start, length: wordEnd - start))

    default:
      let isWholeName = typed.last?.isWhitespace == true
        && people.contains { $0.name.compare(typed.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
      guard typed.isEmpty || (!isWholeName && !ChatCommand.people(matching: typed, among: people).isEmpty) else {
        self = .after(command)
        return
      }
      self = .person(command, typed: typed, range: NSRange(location: start, length: wordEnd - start))
    }
  }

  private static let slash: unichar = 0x2F

  /// Spaces, tabs and new lines, which end a word.
  private static func isSpace(_ character: unichar) -> Bool {
    Unicode.Scalar(character).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
  }
}

// MARK: - Who It's For

/// Who's named at the start of what's typed after a command: everyone with the name, as more than
/// one person can have one, the name as they have it, how much of what's typed it takes, in UTF-16,
/// and what's typed after it.
struct ChatCommandNamed {
  var people: [User]
  var name: String
  var length: Int
  var rest: String
}

/// Who's named one after another at the start of what's typed after a command, as /invite has them:
/// each name, and where what's typed after them starts, in UTF-16.
struct ChatCommandNames {
  /// A name: everyone with it, as more than one person can have one, the name as they have it, and
  /// where it's typed, in UTF-16, quotes and all.
  struct Name {
    var people: [User]
    var name: String
    var range: NSRange
  }

  var names: [Name] = []
  var restStart = 0
}

extension ChatCommand {
  /// Who it can be for, to choose from: anyone but you, and for /invite in a private chat, anyone
  /// who isn't in it already. /info can be for you too, and /msg, last, as servers take a message
  /// to yourself.
  func candidates(in context: ChatCommandContext) -> [User] {
    switch self {
    case .info:
      return context.people
    case .msg:
      return context.people.filter { $0.id != context.ownUserID } + context.people.filter { $0.id == context.ownUserID }
    case .invite:
      return context.people.filter { $0.id != context.ownUserID && !context.members.contains($0.id) }
    default:
      return context.people.filter { $0.id != context.ownUserID }
    }
  }

  /// Whoever's name is what's typed, so Return is for them, then the people whose names start with
  /// it, then those with a word in their names that does, each in the order given, in any case. All
  /// of them, for nothing typed.
  static func people(matching typed: String, among people: [User]) -> [User] {
    let typed = typed.hasPrefix("\"") ? String(typed.dropFirst()) : typed
    guard !typed.isEmpty else {
      return people
    }
    let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive]
    let isNamed: (User) -> Bool = { $0.name.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    let starting = people.filter { $0.name.range(of: typed, options: options) != nil }
    let inside = people.filter { user in
      user.name.range(of: typed, options: options) == nil
        && user.name.split(whereSeparator: \.isWhitespace).dropFirst().contains { $0.range(of: typed, options: options) != nil }
    }
    return starting.filter(isNamed) + starting.filter { !isNamed($0) } + inside
  }

  /// Who's named at the start of what's typed after a command: the longest name of any of `people`
  /// it starts with, in any case, with a space or a comma after it, or nothing, or a name in quotes.
  /// Nil when it starts with no one's.
  static func person(in arguments: String, among people: [User]) -> ChatCommandNamed? {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    func everyone(named name: String) -> [User] {
      people.filter { $0.name.compare(name, options: options) == .orderedSame }
    }

    if arguments.hasPrefix("\""), let close = arguments.dropFirst().firstIndex(of: "\"") {
      let named = everyone(named: String(arguments[arguments.index(after: arguments.startIndex)..<close]))
      guard let first = named.first else {
        return nil
      }
      let end = arguments.index(after: close)
      return ChatCommandNamed(people: named, name: first.name, length: arguments[..<end].utf16.count, rest: Self.rest(after: arguments[end...]))
    }

    var longest: (end: String.Index, name: String)?
    for user in people where !user.name.isEmpty {
      guard let range = arguments.range(of: user.name, options: options.union(.anchored)),
            range.upperBound == arguments.endIndex || arguments[range.upperBound].isWhitespace || arguments[range.upperBound] == ",",
            longest.map({ range.upperBound > $0.end }) ?? true else {
        continue
      }
      longest = (range.upperBound, user.name)
    }
    guard let longest else {
      return nil
    }
    return ChatCommandNamed(
      people: everyone(named: longest.name),
      name: longest.name,
      length: arguments[..<longest.end].utf16.count,
      rest: Self.rest(after: arguments[longest.end...])
    )
  }

  /// What's typed after a name: past the spaces after it, and a comma, as in “Maria, hi”.
  private static func rest(after text: Substring) -> String {
    let rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return rest.hasPrefix(",") ? rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) : rest
  }

  /// Who's named one after another at the start of `arguments`: each the longest name of any of
  /// `people` that's typed there, or a name in quotes, with spaces or a comma between them. While
  /// they're being typed, a name at the end isn't one yet, until there's a space after it, nor is one
  /// that what's typed after it could still be the start of a longer name of, as “Mac G” is of
  /// “Mac Guy”.
  static func names(in arguments: String, among people: [User], typing: Bool = false) -> ChatCommandNames {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    var names = ChatCommandNames()
    var index = arguments.startIndex
    while index < arguments.endIndex {
      let remaining = String(arguments[index...])
      if typing {
        let isWholeName = remaining.last?.isWhitespace == true
          && people.contains { $0.name.compare(remaining.trimmingCharacters(in: .whitespacesAndNewlines), options: options) == .orderedSame }
        let isStartOfName = people.contains { $0.name.range(of: remaining, options: options.union(.anchored)) != nil }
        if isStartOfName && !isWholeName {
          break
        }
      }
      guard let named = Self.person(in: remaining, among: people) else {
        break
      }
      let nameEnd = arguments.utf16.index(index, offsetBy: named.length)
      if typing, nameEnd == arguments.endIndex, !remaining.hasPrefix("\"") {
        break
      }
      let location = arguments.utf16.distance(from: arguments.startIndex, to: index)
      names.names.append(ChatCommandNames.Name(people: named.people, name: named.name, range: NSRange(location: location, length: named.length)))

      // Past the spaces after it, and a comma.
      index = nameEnd
      var comma = false
      while index < arguments.endIndex, arguments[index].isWhitespace || (!comma && arguments[index] == ",") {
        comma = comma || arguments[index] == ","
        index = arguments.index(after: index)
      }
    }
    names.restStart = arguments.utf16.distance(from: arguments.startIndex, to: index)
    return names
  }

  /// The first word typed, or a name in quotes, without them, and how much of what's typed it
  /// takes, in UTF-16, quotes and all.
  static func firstWord(of arguments: String) -> (word: String, length: Int) {
    if arguments.hasPrefix("\"") {
      let inside = arguments.dropFirst()
      let name = inside.prefix { $0 != "\"" }
      return (String(name), 1 + name.utf16.count + (name.endIndex < inside.endIndex ? 1 : 0))
    }
    let word = arguments.prefix { !$0.isWhitespace }
    return (String(word), word.utf16.count)
  }
}

// MARK: - Running

/// What a command does, once what's typed after its name has been read.
enum ChatCommandRequest {
  case emote(String)
  case privateMessage(User, String)
  case away(String)
  case back
  case rename(String)
  case icon(Int)
  /// A private chat with them, with a subject, or in a private chat, them invited to it. No one,
  /// for a private chat with only you in it, to invite people to.
  case invite([User], subject: String)
  /// The sheet for choosing who to invite to the private chat it's typed in.
  case chooseWhoToInvite
  case topic(String)
  case leave
  case info(User)
  case broadcast(String)
  case kick(User)
  case ban(User)
}

/// Why a command can't be run as it's typed, to say above the field, and when it's who it's for
/// that isn't clear, the people it could be, to choose from, and where what's typed after the
/// command's name for them is, in UTF-16, for the one chosen to go in place of.
struct ChatCommandProblem: Error {
  var message: String
  var people: [User] = []
  var nameStart = 0
  var nameLength = 0
}

extension ChatCommand {
  /// What it does with what's typed after its name, or why it can't. `chosen` are people chosen from
  /// a list of everyone with the same name, for which of them it's for.
  func request(_ arguments: String, in context: ChatCommandContext, chosen: Set<UInt16> = []) -> Result<ChatCommandRequest, ChatCommandProblem> {
    if let reason = self.unavailable(in: context) {
      return .failure(ChatCommandProblem(message: reason))
    }
    switch self {
    case .me:
      return arguments.isEmpty ? .failure(ChatCommandProblem(message: "Type an action after /me, like “/me waves”.")) : .success(.emote(arguments))
    case .topic:
      return arguments.isEmpty ? .failure(ChatCommandProblem(message: "Type the new subject after /topic.")) : .success(.topic(arguments))
    case .broadcast:
      return arguments.isEmpty ? .failure(ChatCommandProblem(message: "Type what to broadcast after /broadcast.")) : .success(.broadcast(arguments))
    case .away:
      if !arguments.isEmpty {
        return .success(.away(arguments))
      }
      // The reply you had, when there's one.
      let saved = context.automaticResponse.trimmingCharacters(in: .whitespacesAndNewlines)
      return saved.isEmpty ? .failure(ChatCommandProblem(message: "Type what to reply with after /away, like “/away Back in 10”.")) : .success(.away(saved))
    case .back:
      return context.automaticResponseOn ? .success(.back) : .failure(ChatCommandProblem(message: "Auto-reply is already off."))
    case .rename:
      return arguments.isEmpty ? .failure(ChatCommandProblem(message: "Type your new name after /name.")) : .success(.rename(arguments))
    case .icon:
      guard let iconID = Int(arguments), (0...Int(UInt16.max)).contains(iconID) else {
        return .failure(ChatCommandProblem(message: "Type an icon’s number after /icon, or choose one, like “/icon 141”."))
      }
      return .success(.icon(iconID))
    case .leave:
      return .success(.leave)
    case .invite:
      return self.invite(arguments, in: context, chosen: chosen)
    case .msg, .info, .kick, .ban:
      let person: User
      let rest: String
      switch self.person(in: arguments, context: context, chosen: chosen) {
      case .success(let found):
        (person, rest) = found
      case .failure(let problem):
        return .failure(problem)
      }
      let isYou = person.id == context.ownUserID
      switch self {
      case .msg:
        if person.refusesPrivateMessages {
          return .failure(ChatCommandProblem(message: "\(person.name) isn’t accepting private messages."))
        }
        if rest.isEmpty {
          return .failure(ChatCommandProblem(message: "Type a message for \(person.name) after their name."))
        }
        return .success(.privateMessage(person, rest))
      case .info:
        return .success(.info(person))
      default:
        if isYou {
          return .failure(ChatCommandProblem(message: "That’s you."))
        }
        return .success(self == .ban ? .ban(person) : .kick(person))
      }
    }
  }

  /// Who /invite is for, named one after another, but you, who's in any chat you start, and in the
  /// public chat, the subject after them, once there's someone named, you too, so a word that isn't
  /// anyone's name, and isn't after one, is someone who isn't here, rather than a subject. In a
  /// private chat, with no one named, the sheet for choosing who.
  private func invite(_ arguments: String, in context: ChatCommandContext, chosen: Set<UInt16>) -> Result<ChatCommandRequest, ChatCommandProblem> {
    let named = Self.names(in: arguments, among: context.people)
    let rest = (arguments as NSString).substring(from: named.restStart)
    if context.isPrivateChat && arguments.isEmpty {
      return .success(.chooseWhoToInvite)
    }
    if !rest.isEmpty && (context.isPrivateChat || named.names.isEmpty) {
      let (word, length) = Self.firstWord(of: rest)
      return .failure(ChatCommandProblem(message: "No one named “\(word)” is here.", people: Self.people(matching: word, among: self.candidates(in: context)), nameStart: named.restStart, nameLength: length))
    }

    var people: [User] = []
    for name in named.names {
      guard let person = name.people.count == 1 ? name.people.first : name.people.first(where: { chosen.contains($0.id) }) else {
        return .failure(ChatCommandProblem(message: "\(name.people.count) people are named “\(name.name)”. Choose one.", people: name.people, nameStart: name.range.location, nameLength: name.range.length))
      }
      if person.id == context.ownUserID {
        if context.isPrivateChat {
          return .failure(ChatCommandProblem(message: "You’re in this chat already."))
        }
        continue
      }
      if context.members.contains(person.id) {
        return .failure(ChatCommandProblem(message: "\(person.name) is already in this chat."))
      }
      if person.refusesPrivateChat {
        return .failure(ChatCommandProblem(message: "\(person.name) isn’t accepting private chat invitations."))
      }
      if !people.contains(where: { $0.id == person.id }) {
        people.append(person)
      }
    }
    return .success(.invite(people, subject: context.isPrivateChat ? "" : rest))
  }

  /// Who it's for, of everyone, and what's typed after their name, or why that isn't clear, with who
  /// it could be for, to choose from.
  private func person(in arguments: String, context: ChatCommandContext, chosen: Set<UInt16>) -> Result<(User, String), ChatCommandProblem> {
    let candidates = self.candidates(in: context)
    guard !arguments.isEmpty else {
      return .failure(ChatCommandProblem(message: self.whoToType, people: candidates))
    }
    guard let named = Self.person(in: arguments, among: context.people) else {
      let (word, length) = Self.firstWord(of: arguments)
      return .failure(ChatCommandProblem(message: "No one named “\(word)” is here.", people: Self.people(matching: word, among: candidates), nameLength: length))
    }
    guard named.people.count > 1 else {
      return .success((named.people[0], named.rest))
    }
    if let person = named.people.first(where: { chosen.contains($0.id) }) {
      return .success((person, named.rest))
    }
    return .failure(ChatCommandProblem(message: "\(named.people.count) people are named “\(named.name)”. Choose one.", people: named.people, nameLength: named.length))
  }

  /// What to type, for a command that's for someone, when no one is.
  private var whoToType: String {
    switch self {
    case .msg:
      return "Type who it’s for after /msg, then the message."
    case .info:
      return "Type whose info to get after /info."
    case .ban:
      return "Type who to ban after /ban."
    default:
      return "Type who to disconnect after /kick."
    }
  }
}
