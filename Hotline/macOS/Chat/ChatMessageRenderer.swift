import AppKit

import UniformTypeIdentifiers

/// Builds the text for each chat message: who said it, their icon, links and simple formatting,
/// code blocks, links to files on Hotline servers shown as the file, and previews of linked images.
///
/// Each message is one paragraph, so it gets one layout fragment in the transcript. Line breaks
/// inside a message become line separators (U+2028) to keep it that way. Code blocks are the
/// exception: each is a paragraph of its own, to get a background with room around it, and so is
/// any text after one.
enum ChatMessageRenderer {

  // MARK: Attributes the transcript reads back

  /// The message a range of text belongs to.
  static let messageIDKey = NSAttributedString.Key("chatMessageID")
  /// When the message was sent, for its tooltip.
  static let messageDateKey = NSAttributedString.Key("chatMessageDate")
  /// Who sent a message, on its first paragraph, which gets their icon.
  static let senderNameKey = NSAttributedString.Key("chatSenderName")
  /// The name a message starts with, with who it's from, so clicking it opens a menu for them.
  static let userNameKey = NSAttributedString.Key("chatUserName")
  /// The icon saved with a message, if it was known when the message came in.
  static let iconIDKey = NSAttributedString.Key("chatIconID")
  /// Marks a code block, which gets a rounded background.
  static let codeBlockKey = NSAttributedString.Key("chatCodeBlock")
  /// The language a code block names, like lua in ```lua, which shows above its code.
  static let codeLanguageKey = NSAttributedString.Key("chatCodeLanguage")
  /// Marks a message that goes on from the one before it, from the same person, which goes
  /// without their name and icon.
  static let groupedKey = NSAttributedString.Key("chatGrouped")
  /// Marks server messages, which get a rounded background.
  static let serverMessageKey = NSAttributedString.Key("chatServerMessage")
  /// Marks date dividers between sessions, which get a line above them.
  static let dividerKey = NSAttributedString.Key("chatDivider")
  /// Text that watch words shouldn't highlight, like names and your own messages.
  static let skipHighlightKey = NSAttributedString.Key("chatSkipHighlight")
  /// A link to a file on a Hotline server, shown as the file's icon and name. The link itself, so
  /// copying gives the link rather than the name.
  static let fileLinkKey = NSAttributedString.Key("chatFileLink")
  /// A long link shown shorter, as it was written, so copying gives all of it.
  static let fullLinkKey = NSAttributedString.Key("chatFullLink")

  /// How messages are shown: what the settings ask for, and which server the chat is on.
  struct Options: Equatable {
    /// Whether messages have their sender's icon before them. Without, there's no icon column.
    var showsIcons = true
    /// Whether links to images have a preview under them.
    var previewsImages = true
    /// Admins' names, and when they come and go, in place of Hotline's red, as a server's theme has
    /// them.
    var adminColor: NSColor? = nil
    /// What matters less, like emotes, and people coming and going, in place of the system's
    /// secondary color, as a server's theme has it.
    var secondaryColor: NSColor? = nil
    /// What matters least, like the days between messages, in place of the system's tertiary color,
    /// as a server's theme has it.
    var tertiaryColor: NSColor? = nil
  }

  // MARK: Layout

  /// The space between messages from different people, and around anything else in the chat.
  /// Every paragraph has the space for messages in a row from the same person after it, and the
  /// rest before it, unless it goes on from the message before.
  static let messageSpacing: CGFloat = 8
  /// The space between messages in a row from the same person.
  static let groupedSpacing: CGFloat = 2

  /// The frame for the sender's icon at the start of each message, spaced like the user list: 2 pt
  /// in, 16 pt wide, then 2 pt and 5 pt before the name. Icons are centered in it, and wide ones
  /// spill out of it, under the name.
  static let iconInset: CGFloat = 2
  static let iconColumnWidth: CGFloat = 16
  /// Where a message's text starts, after the icon.
  static let textIndent: CGFloat = 25
  /// How much further in a message's wrapped lines start, so the name stands out.
  static let hangingIndent: CGFloat = 16
  /// At most this many image previews under a message.
  static let previewLimit = 3
  /// How far a code block's background reaches past its code. The background starts where a
  /// message's wrapped lines do.
  static let codeBlockPadding = NSSize(width: 8, height: 6)
  /// The room above a code block's code for the language it names.
  static let codeLanguageHeight: CGFloat = 15

  static var baseFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
  static var semiboldFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold) }
  static var linkColor: NSColor { NSColor(named: "Link Color") ?? .linkColor }
  private static var adminColor: NSColor { NSColor(named: "Hotline Red") ?? .systemRed }

  // MARK: Rendering

  /// A message's text. One `continuing` the message before it, from the same person, goes without
  /// their name and icon.
  static func render(_ message: ChatMessage, continuing: Bool = false, options: Options = Options()) -> NSAttributedString {
    let text: NSMutableAttributedString
    switch message.type {
    case .message:
      text = message.isEmote ? self.emote(message, options: options) : self.chat(message, continuing: continuing, options: options)
    case .joined:
      text = self.presence(message, arrow: "\u{2192}", options: options)
    case .left:
      text = self.presence(message, arrow: "\u{2190}", options: options)
    case .signOut:
      text = self.divider(message, options: options)
    case .server:
      text = self.serverMessage(message)
    case .agreement:
      text = NSMutableAttributedString()
    }

    let range = NSRange(location: 0, length: text.length)
    text.addAttribute(self.messageIDKey, value: message.id, range: range)
    text.addAttribute(self.messageDateKey, value: message.date, range: range)
    return text
  }

  /// Whether a message goes on from the one before it: both chat from the same person, as far as
  /// can be told, with nothing between them, like a date divider or someone connecting.
  static func continues(_ message: ChatMessage, after previous: ChatMessage?) -> Bool {
    guard let previous,
          message.type == .message, previous.type == .message,
          !message.isEmote, !previous.isEmote,
          let username = message.username, username == previous.username else {
      return false
    }
    // Names aren't accounts, so someone with another icon is someone else.
    return message.iconID == previous.iconID && message.isAdmin == previous.isAdmin
  }

  private static func chat(_ message: ChatMessage, continuing: Bool, options: Options) -> NSMutableAttributedString {
    let paragraph = self.messageParagraph(continuing: continuing, showsIcons: options.showsIcons)
    let text = NSMutableAttributedString()

    if let username = message.username, !continuing {
      let nameAttributes: [NSAttributedString.Key: Any] = [
        .font: self.semiboldFont,
        .foregroundColor: message.isAdmin ? options.adminColor ?? self.adminColor : NSColor.textColor,
        .paragraphStyle: paragraph,
        self.skipHighlightKey: true,
      ]
      let name = NSMutableAttributedString(string: "\(username): ", attributes: nameAttributes)
      // The name, with the icon they had, to tell apart people with the same name.
      let nameRange = NSRange(location: 0, length: (username as NSString).length)
      name.addAttribute(self.userNameKey, value: username, range: nameRange)
      if let iconID = message.iconID {
        name.addAttribute(self.iconIDKey, value: NSNumber(value: iconID), range: nameRange)
      }
      text.append(name)
    }

    let body = self.formattedText(self.lineSeparated(message.text), paragraph: paragraph)
    // A code block at the start goes on the line after the name, or first if there's no name.
    if message.username == nil || continuing, body.length > 0, (body.string as NSString).character(at: 0) == 0x0A {
      body.deleteCharacters(in: NSRange(location: 0, length: 1))
    }
    self.showFileLinks(in: body)
    text.append(body)
    if options.previewsImages {
      self.appendImagePreviews(to: text, paragraph: paragraph)
    }

    let range = NSRange(location: 0, length: text.length)
    if let username = message.username, options.showsIcons, !continuing {
      let firstParagraph = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
      text.addAttribute(self.senderNameKey, value: username, range: firstParagraph)
      if let iconID = message.iconID {
        text.addAttribute(self.iconIDKey, value: NSNumber(value: iconID), range: firstParagraph)
      }
    }
    if continuing {
      text.addAttribute(self.groupedKey, value: true, range: range)
    }
    // Watch words don't highlight in your own messages.
    if let username = message.username, username.lowercased() == Prefs.shared.username.lowercased() {
      text.addAttribute(self.skipHighlightKey, value: true, range: range)
    }
    return text
  }

  private static func emote(_ message: ChatMessage, options: Options) -> NSMutableAttributedString {
    let paragraph = self.messageParagraph(showsIcons: options.showsIcons)
    let italic = NSFont(descriptor: self.baseFont.fontDescriptor.withSymbolicTraits(.italic), size: self.baseFont.pointSize) ?? self.baseFont

    // Without the "*** " that marks an emote.
    let displayText = message.text.firstMatch(of: ChatMessage.emoteParser).map { String($0.1) } ?? message.text
    return NSMutableAttributedString(
      string: self.lineSeparated(displayText),
      attributes: [
        .font: italic,
        .foregroundColor: options.secondaryColor ?? NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph,
      ]
    )
  }

  /// Someone connecting or disconnecting, with the arrow in the icon column. Without icons, the
  /// arrow goes first, and the text where messages' wrapped lines start.
  private static func presence(_ message: ChatMessage, arrow: String, options: Options) -> NSMutableAttributedString {
    let paragraph = NSMutableParagraphStyle()
    let textStart = options.showsIcons ? self.textIndent : self.hangingIndent
    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
    paragraph.headIndent = textStart
    if options.showsIcons {
      // The arrow in the middle of the icon column, where messages have the sender's icon.
      let arrowWidth = (arrow as NSString).size(withAttributes: [.font: self.baseFont]).width
      paragraph.firstLineHeadIndent = max(0, self.iconInset + self.iconColumnWidth / 2 - arrowWidth / 2)
    }
    paragraph.lineSpacing = 2
    paragraph.paragraphSpacingBefore = self.messageSpacing - self.groupedSpacing
    paragraph.paragraphSpacing = self.groupedSpacing

    return NSMutableAttributedString(
      string: "\(arrow)\t\(message.text)",
      attributes: [
        .font: self.baseFont,
        .foregroundColor: message.isAdmin ? options.adminColor ?? self.adminColor : options.secondaryColor ?? NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph,
        self.skipHighlightKey: true,
      ]
    )
  }

  /// The day and time a session starts, in a line across the chat, where people coming and going
  /// have what they did.
  private static func divider(_ message: ChatMessage, options: Options) -> NSMutableAttributedString {
    let paragraph = NSMutableParagraphStyle()
    let textStart = options.showsIcons ? self.textIndent : self.hangingIndent
    paragraph.firstLineHeadIndent = textStart
    paragraph.headIndent = textStart
    // 28 above the date and 18 below it, with what's around it.
    paragraph.paragraphSpacingBefore = 28 - self.groupedSpacing
    paragraph.paragraphSpacing = 18 - (self.messageSpacing - self.groupedSpacing)

    let text = NSMutableAttributedString(
      string: self.dividerDate(message.date),
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: options.tertiaryColor ?? NSColor.tertiaryLabelColor,
        .paragraphStyle: paragraph,
      ]
    )
    text.addAttribute(self.dividerKey, value: true, range: NSRange(location: 0, length: text.length))
    return text
  }

  private static func serverMessage(_ message: ChatMessage) -> NSMutableAttributedString {
    let paragraph = NSMutableParagraphStyle()
    // 24 above and below it, with what's around it.
    paragraph.paragraphSpacingBefore = 24 - self.groupedSpacing
    paragraph.paragraphSpacing = 24 - (self.messageSpacing - self.groupedSpacing)
    paragraph.alignment = .center
    paragraph.lineSpacing = 3
    paragraph.firstLineHeadIndent = 16
    paragraph.headIndent = 28
    paragraph.tailIndent = -16

    let text = NSMutableAttributedString()
    if let image = NSImage(named: "Server Message") {
      let attachment = NSTextAttachment()
      attachment.image = image
      attachment.bounds = CGRect(x: 0, y: -4, width: 20, height: 20)
      text.append(NSAttributedString(attachment: attachment))
      text.append(NSAttributedString(string: "  "))
    }

    // One paragraph, so the indents apply to every line and the spacing doesn't repeat.
    let displayText = message.text.replacingOccurrences(of: "\\n\\s*", with: "\u{2028}", options: .regularExpression)
    text.append(NSAttributedString(string: displayText, attributes: [.font: self.semiboldFont, .foregroundColor: NSColor.textColor]))

    let range = NSRange(location: 0, length: text.length)
    text.addAttribute(.paragraphStyle, value: paragraph, range: range)
    text.addAttribute(self.serverMessageKey, value: true, range: range)
    return text
  }

  // MARK: Formatting

  /// A message's text with its line breaks as line separators, so it stays one paragraph. Classic
  /// clients break lines with \r.
  private static func lineSeparated(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else {
      return text
    }
    return text
      .replacingOccurrences(of: "\r\n", with: "\u{2028}")
      .replacingOccurrences(of: "\r", with: "\u{2028}")
      .replacingOccurrences(of: "\n", with: "\u{2028}")
  }

  /// A message's text with its links, and formatting the way chat apps like Slack do it rather
  /// than all of Markdown: *bold* or **bold**, _italic_, ~strikethrough~ or ~~strikethrough~~,
  /// __underline__, `code`, and code blocks between ``` and ```, colored when they name a language
  /// we know, as in ```lua. Everything else shows as it was typed. Most messages have no
  /// formatting, or nothing that could be a link, and skip straight past looking for them.
  static func formattedText(_ string: String, paragraph: NSParagraphStyle) -> NSMutableAttributedString {
    let blocks = string.utf8.contains(UInt8(ascii: "`")) && string.contains("```") ? self.codeBlocks(in: string as NSString) : []
    guard !blocks.isEmpty else {
      return self.inlineFormattedText(string, paragraph: paragraph)
    }

    // Each code block is a paragraph of its own, and so is the text after one, which lines up with
    // the message's wrapped lines. Blocks have room around them, so blank lines next to one go.
    let source = string as NSString
    func isSpace(_ character: unichar) -> Bool {
      character == 0x20 || character == 0x09 || character == 0x0A || character == 0x0D || character == 0x2028
    }
    func trimmed(_ range: NSRange, leading: Bool) -> NSRange {
      var range = range
      while leading && range.length > 0 && isSpace(source.character(at: range.location)) {
        range.location += 1
        range.length -= 1
      }
      while range.length > 0 && isSpace(source.character(at: NSMaxRange(range) - 1)) {
        range.length -= 1
      }
      return range
    }

    let text = NSMutableAttributedString()
    let codeParagraph = self.codeParagraph(after: paragraph)
    let continuedParagraph = self.continuedParagraph(after: paragraph)
    var start = 0
    for block in blocks {
      let before = trimmed(NSRange(location: start, length: block.range.location - start), leading: start > 0)
      if before.length > 0 {
        if start > 0 {
          text.append(self.paragraphBreak(after: text, paragraph: paragraph))
        }
        text.append(self.inlineFormattedText(source.substring(with: before), paragraph: start > 0 ? continuedParagraph : paragraph))
      }
      text.append(self.paragraphBreak(after: text, paragraph: paragraph))
      text.append(self.codeBlock(source.substring(with: block.code), language: block.language, paragraph: codeParagraph))
      start = NSMaxRange(block.range)
    }
    let after = trimmed(NSRange(location: start, length: source.length - start), leading: true)
    if after.length > 0 {
      text.append(self.paragraphBreak(after: text, paragraph: paragraph))
      text.append(self.inlineFormattedText(source.substring(with: after), paragraph: continuedParagraph))
    }
    return text
  }

  /// A code block in a message's text. Ranges count UTF-16 code units, as NSString does.
  struct CodeBlock: Equatable {
    /// All of it, from the opening ``` to the closing one.
    var range: NSRange
    var code: NSRange
    /// The language named after the opening ```, like lua in ```lua.
    var language: String?
  }

  /// The code blocks in a message, as GitHub and Discord have them: the code starts on the line
  /// after the opening ``` if there's nothing else on that line but a language, and otherwise
  /// right after it, as in ```ls -la```. A ``` with no closing one stays as it was typed.
  static func codeBlocks(in string: NSString) -> [CodeBlock] {
    let length = string.length
    func isLineBreak(_ index: Int) -> Bool {
      let character = string.character(at: index)
      return character == 0x0A || character == 0x0D || character == 0x2028
    }
    func fence(from index: Int) -> Int? {
      guard index < length else {
        return nil
      }
      let found = string.range(of: "```", options: .literal, range: NSRange(location: index, length: length - index))
      return found.location == NSNotFound ? nil : found.location
    }

    var blocks: [CodeBlock] = []
    var index = 0
    while let open = fence(from: index) {
      var start = open + 3
      var language: String?
      var lineEnd = start
      while lineEnd < length && !isLineBreak(lineEnd) {
        lineEnd += 1
      }
      if lineEnd < length {
        let name = string.substring(with: NSRange(location: start, length: lineEnd - start)).trimmingCharacters(in: .whitespaces)
        if name.unicodeScalars.allSatisfy({ self.languageNameCharacters.contains($0) }) {
          language = name.isEmpty ? nil : name
          start = lineEnd + 1
        }
      }
      guard let close = fence(from: start) else {
        break
      }
      // The line break before the closing ``` isn't part of the code.
      var end = close
      if end > start && isLineBreak(end - 1) {
        end -= 1
      }
      if end > start {
        blocks.append(CodeBlock(range: NSRange(location: open, length: close + 3 - open), code: NSRange(location: start, length: end - start), language: language))
      }
      index = close + 3
    }
    return blocks
  }

  private static let languageNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+#-_."))

  /// A code block's code, colored if it names a language we know. Whatever language it names goes
  /// above the code, with room made for it.
  private static func codeBlock(_ code: String, language: String?, paragraph: NSParagraphStyle) -> NSMutableAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: self.codeFont,
      .foregroundColor: NSColor.textColor,
      .paragraphStyle: paragraph,
      self.codeBlockKey: true,
    ]
    if let language {
      let labeled = (paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
      labeled.paragraphSpacingBefore += self.codeLanguageHeight
      attributes[.paragraphStyle] = labeled
      attributes[self.codeLanguageKey] = language
    }
    let text = NSMutableAttributedString(string: code, attributes: attributes)
    if let language = language.flatMap({ ChatCodeHighlighter.language(named: $0) }) {
      ChatCodeHighlighter.highlight(text, in: NSRange(location: 0, length: text.length), as: language)
    }
    return text
  }

  /// A code block's lines start inside its background, which starts where the message's wrapped
  /// lines do, and they wrap before its right edge.
  private static func codeParagraph(after paragraph: NSParagraphStyle) -> NSParagraphStyle {
    let code = NSMutableParagraphStyle()
    code.firstLineHeadIndent = paragraph.headIndent + self.codeBlockPadding.width
    code.headIndent = code.firstLineHeadIndent
    code.tailIndent = -self.codeBlockPadding.width
    code.lineSpacing = 2
    // 12 above from the text before it, and 14 below to what comes next, padding included.
    code.paragraphSpacingBefore = 12 - self.groupedSpacing
    code.paragraphSpacing = 14 - (self.messageSpacing - self.groupedSpacing)
    // Tabs four spaces wide, as most code is written.
    code.tabStops = []
    code.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: self.codeFont]).width
    return code
  }

  /// Text after a code block lines up with the message's wrapped lines.
  private static func continuedParagraph(after paragraph: NSParagraphStyle) -> NSParagraphStyle {
    let continued = (paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    continued.firstLineHeadIndent = paragraph.headIndent
    continued.paragraphSpacingBefore = self.messageSpacing - self.groupedSpacing
    return continued
  }

  /// The break that ends a paragraph of a message, in that paragraph's font, so it doesn't change
  /// the height of the last line.
  private static func paragraphBreak(after text: NSAttributedString, paragraph: NSParagraphStyle) -> NSAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [.font: self.baseFont, .paragraphStyle: paragraph]
    if text.length > 0 {
      let last = text.attributes(at: text.length - 1, effectiveRange: nil)
      attributes[.paragraphStyle] = last[.paragraphStyle] ?? paragraph
      if last[self.codeBlockKey] != nil {
        attributes[.font] = self.codeFont
        attributes[self.codeBlockKey] = true
      }
    }
    return NSAttributedString(string: "\n", attributes: attributes)
  }

  /// Text with its links and formatting, all in one paragraph.
  private static func inlineFormattedText(_ string: String, paragraph: NSParagraphStyle) -> NSMutableAttributedString {
    let text = NSMutableAttributedString(string: string, attributes: [
      .font: self.baseFont,
      .foregroundColor: NSColor.textColor,
      .paragraphStyle: paragraph,
    ])
    var linkRanges: [NSRange] = []
    if self.mightHaveLinks(string) {
      for link in string.detectedLinks() {
        let range = NSRange(link.range, in: string)
        text.addAttributes([.link: link.url, .foregroundColor: self.linkColor], range: range)
        linkRanges.append(range)
      }
    }
    if string.unicodeScalars.contains(where: { self.markCharacters.contains($0) }) {
      self.applyFormatting(to: text, outside: linkRanges)
    }
    if !linkRanges.isEmpty {
      self.shortenLongLinks(in: text)
    }
    return text
  }

  /// How long a link can be before most of what's after its ? is hidden.
  private static let longLinkLength = 80
  /// The longest a long link's first parameter can be and still show, like YouTube's v=…, which
  /// says which video.
  private static let shownParameterLength = 24

  /// Web links longer than `longLinkLength` with parameters, shown without them.
  private static func shortenLongLinks(in text: NSMutableAttributedString) {
    var long: [(range: NSRange, shown: String, written: String)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
      guard range.length > self.longLinkLength, let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return
      }
      let written = (text.string as NSString).substring(with: range)
      if let shown = self.shortLink(written) {
        long.append((range, shown, written))
      }
    }
    // From the end, so earlier ranges stay put.
    for link in long.reversed() {
      var attributes = text.attributes(at: link.range.location, effectiveRange: nil)
      attributes[self.fullLinkKey] = link.written
      text.replaceCharacters(in: link.range, with: NSAttributedString(string: link.shown, attributes: attributes))
    }
  }

  /// A link shown up to its ? or #, with its first parameter if that's short, then …. Nil if
  /// there's nothing after that to hide.
  static func shortLink(_ link: String) -> String? {
    guard let cut = link.firstIndex(where: { $0 == "?" || $0 == "#" }) else {
      return nil
    }
    var shown = String(link[..<cut])
    if link[cut] == "?" {
      let parameters = link[link.index(after: cut)...]
      let first = parameters.prefix { $0 != "&" && $0 != "#" }
      if !first.isEmpty, first.count <= self.shownParameterLength {
        guard first.endIndex < parameters.endIndex else {
          return nil
        }
        shown += "?" + first
      }
    }
    return shown + "\u{2026}"
  }

  /// Whether there's anything a link could be: an @, a scheme's ://, or a dot with something right
  /// after it, as in a domain. A dot at the end of a sentence doesn't count.
  private static func mightHaveLinks(_ string: String) -> Bool {
    var afterDot = false
    for scalar in string.unicodeScalars {
      if scalar == "@" || (afterDot && CharacterSet.alphanumerics.contains(scalar)) {
        return true
      }
      afterDot = scalar == "."
    }
    return string.contains("://")
  }

  private enum Style {
    case bold, italic, strikethrough, underline, code
  }

  private static let markCharacters: Set<Unicode.Scalar> = ["*", "_", "~", "`"]

  /// Each mark and what it does, longer ones first so ** isn't read as two *, and code first,
  /// since nothing inside it is formatted.
  private static let marks: [(mark: String, style: Style)] = [
    ("`", .code), ("**", .bold), ("__", .underline), ("~~", .strikethrough), ("*", .bold), ("_", .italic), ("~", .strikethrough),
  ]

  /// Formats text between pairs of marks, and takes the marks out. A mark opens only at the start
  /// of a word and closes only at the end of one, the way Slack has it, so snake_case_names and
  /// 2*3*4 stay as they are. Formatting stays on one line, and never inside a link.
  private static func applyFormatting(to text: NSMutableAttributedString, outside links: [NSRange]) {
    let string = text.string as NSString
    let length = string.length
    var taken = [Bool](repeating: false, count: length)
    for link in links {
      for index in link.location..<NSMaxRange(link) {
        taken[index] = true
      }
    }

    func isWordCharacter(_ index: Int) -> Bool {
      guard index >= 0, index < length, let scalar = Unicode.Scalar(string.character(at: index)) else {
        return false
      }
      return CharacterSet.alphanumerics.contains(scalar)
    }
    func isSpace(_ index: Int) -> Bool {
      guard index >= 0, index < length, let scalar = Unicode.Scalar(string.character(at: index)) else {
        return true
      }
      return CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "\u{2028}"
    }
    func hasMark(_ mark: NSString, at index: Int) -> Bool {
      guard index >= 0, index + mark.length <= length else {
        return false
      }
      for offset in 0..<mark.length where taken[index + offset] || string.character(at: index + offset) != mark.character(at: offset) {
        return false
      }
      return true
    }

    var spans: [(content: NSRange, style: Style)] = []
    var removed: [NSRange] = []
    for (markString, style) in self.marks {
      let mark = markString as NSString
      let markLength = mark.length
      let markCharacter = mark.character(at: 0)
      var index = 0
      while index < length {
        // Opens: at the start of a word, with something other than a space after it.
        guard hasMark(mark, at: index),
              !isWordCharacter(index - 1),
              index == 0 || string.character(at: index - 1) != markCharacter,
              !isSpace(index + markLength),
              index + markLength < length, string.character(at: index + markLength) != markCharacter else {
          index += 1
          continue
        }
        // Closes: on the same line, at the end of a word.
        var close = index + markLength + 1
        var found: Int?
        while close + markLength <= length {
          if isSpace(close) && (string.character(at: close) == 0x2028 || string.character(at: close) == 0x0A) {
            break
          }
          if hasMark(mark, at: close), !isSpace(close - 1), string.character(at: close - 1) != markCharacter,
             !isWordCharacter(close + markLength), close + markLength == length || string.character(at: close + markLength) != markCharacter {
            found = close
            break
          }
          close += 1
        }
        guard let close = found else {
          index += 1
          continue
        }
        let content = NSRange(location: index + markLength, length: close - index - markLength)
        spans.append((content, style))
        removed.append(NSRange(location: index, length: markLength))
        removed.append(NSRange(location: close, length: markLength))
        for offset in 0..<markLength {
          taken[index + offset] = true
          taken[close + offset] = true
        }
        if style == .code {
          for offset in content.location..<NSMaxRange(content) {
            taken[offset] = true
          }
        }
        index = close + markLength
      }
    }
    guard !spans.isEmpty else {
      return
    }

    // Bold and italic can go together, so they're worked out a character at a time.
    var traits = [NSFontDescriptor.SymbolicTraits](repeating: [], count: length)
    for span in spans {
      switch span.style {
      case .bold, .italic:
        for index in span.content.location..<NSMaxRange(span.content) {
          traits[index].insert(span.style == .bold ? .bold : .italic)
        }
      case .strikethrough:
        text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
      case .underline:
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
      case .code:
        text.addAttributes([.font: self.codeFont, .backgroundColor: self.codeBackground], range: span.content)
      }
    }
    var start = 0
    while start < length {
      var end = start + 1
      while end < length && traits[end] == traits[start] {
        end += 1
      }
      if !traits[start].isEmpty {
        let font = NSFont(descriptor: self.baseFont.fontDescriptor.withSymbolicTraits(traits[start]), size: self.baseFont.pointSize) ?? self.baseFont
        text.addAttribute(.font, value: font, range: NSRange(location: start, length: end - start))
      }
      start = end
    }

    // The marks themselves go, from the end so the earlier ones stay put.
    for range in removed.sorted(by: { $0.location > $1.location }) {
      text.deleteCharacters(in: range)
    }
  }

  private static var codeFont: NSFont {
    .monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
  }

  private static var codeBackground: NSColor {
    NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.06) }
  }

  static var codeBlockBackground: NSColor {
    NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04) }
  }

  // MARK: Parts

  /// Chat lines start after the icon column, and wrap further in than the name. A message going on
  /// from the one before it starts where those wrapped lines do, close under it.
  private static func messageParagraph(continuing: Bool = false, showsIcons: Bool = true) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    let start = showsIcons ? self.textIndent : 0
    paragraph.firstLineHeadIndent = continuing ? start + self.hangingIndent : start
    paragraph.headIndent = start + self.hangingIndent
    paragraph.lineSpacing = 3
    paragraph.paragraphSpacingBefore = continuing ? 0 : self.messageSpacing - self.groupedSpacing
    paragraph.paragraphSpacing = self.groupedSpacing
    return paragraph
  }

  /// The name of the file or folder a hotline:// link points to, like
  /// hotline://server/files/Folder/File.zip, or nil if it isn't a link to one. A link that ends in
  /// a slash is to a folder.
  static func fileName(ofHotlineLink url: URL) -> String? {
    guard url.scheme?.lowercased() == "hotline" else {
      return nil
    }
    let path = url.pathComponents.filter { $0 != "/" }
    guard path.count >= 2, path[0] == "files", let name = path.last, !name.isEmpty else {
      return nil
    }
    return name
  }

  /// The links a message's text shows: those outside its code blocks, where nothing is a link.
  static func links(in text: String) -> [URL] {
    let source = text as NSString
    var outside: [NSRange] = []
    var start = 0
    for block in self.codeBlocks(in: source) {
      outside.append(NSRange(location: start, length: block.range.location - start))
      start = NSMaxRange(block.range)
    }
    outside.append(NSRange(location: start, length: source.length - start))
    return outside.flatMap { range -> [URL] in
      let part = source.substring(with: range)
      return self.mightHaveLinks(part) ? part.detectedLinks().map(\.url) : []
    }
  }

  /// Links to files and folders on Hotline servers, shown as the icon and name the Files list shows
  /// rather than the link, which goes in the tooltip. A link with a title of its own keeps it, with
  /// the icon before it.
  private static func showFileLinks(in text: NSMutableAttributedString) {
    var links: [(range: NSRange, url: URL, name: String)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
      if let url, let name = self.fileName(ofHotlineLink: url) {
        links.append((range, url, name))
      }
    }

    // From the end, so earlier ranges stay put.
    for link in links.reversed() {
      var attributes = text.attributes(at: link.range.location, effectiveRange: nil)
      attributes[self.fileLinkKey] = link.url
      let shown = (text.string as NSString).substring(with: link.range)
      let isBareLink = shown.lowercased().hasPrefix("hotline://")
      let file = NSMutableAttributedString(string: isBareLink ? link.name : shown, attributes: attributes)

      let attachment = NSTextAttachment()
      attachment.image = link.url.hasDirectoryPath ? self.folderIcon : self.fileIcon(forName: link.name)
      attachment.bounds = CGRect(x: 0, y: -3, width: 16 + self.fileIconGap, height: 16)
      let icon = NSMutableAttributedString(attachment: attachment)
      icon.addAttributes(attributes, range: NSRange(location: 0, length: icon.length))
      file.insert(icon, at: 0)
      text.replaceCharacters(in: link.range, with: file)
    }
  }

  /// The space between a file's icon and its name. It's part of the icon, since TextKit 2 doesn't
  /// kern attachments.
  private static let fileIconGap: CGFloat = 4

  /// The small folder the Files list shows.
  static let folderIcon = spaced(NSImage(named: "Folder") ?? NSWorkspace.shared.icon(for: .folder))

  private static var fileIcons: [String: NSImage] = [:]

  /// A file's icon from its name, as the Files browser shows it, 16 pt.
  private static func fileIcon(forName name: String) -> NSImage {
    let fileExtension = (name as NSString).pathExtension.lowercased()
    if let icon = self.fileIcons[fileExtension] {
      return icon
    }
    let type = fileExtension.isEmpty ? nil : UTType(filenameExtension: fileExtension)
    let icon = self.spaced(NSWorkspace.shared.icon(for: type ?? .data))
    self.fileIcons[fileExtension] = icon
    return icon
  }

  /// A 16 pt icon with the gap after it.
  private static func spaced(_ icon: NSImage) -> NSImage {
    NSImage(size: NSSize(width: 16 + self.fileIconGap, height: 16), flipped: false) { _ in
      icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
      return true
    }
  }

  /// A small preview, each on its own line, for links to images.
  private static func appendImagePreviews(to text: NSMutableAttributedString, paragraph: NSParagraphStyle) {
    var urls: [URL] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, stop in
      let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
      guard let url, ChatImagePreview.canPreview(url), !urls.contains(url) else {
        return
      }
      urls.append(url)
      if urls.count == self.previewLimit {
        stop.pointee = true
      }
    }

    // After a code block, the previews are a paragraph of their own, like text would be.
    let afterCode = text.length > 0 && text.attribute(self.codeBlockKey, at: text.length - 1, effectiveRange: nil) != nil
    let paragraph = afterCode ? self.continuedParagraph(after: paragraph) : paragraph
    for (index, url) in urls.enumerated() {
      if index == 0 && afterCode {
        text.append(self.paragraphBreak(after: text, paragraph: paragraph))
      }
      else {
        text.append(NSAttributedString(string: "\u{2028}", attributes: [.font: self.baseFont, .paragraphStyle: paragraph]))
      }
      let preview = NSMutableAttributedString(attachment: ChatImageAttachment(url: url))
      // In a tiny font, so its line is only as tall as the preview, which is nothing until its
      // image starts to come in.
      preview.addAttributes([.paragraphStyle: paragraph, self.skipHighlightKey: true, .font: NSFont.systemFont(ofSize: 1)], range: NSRange(location: 0, length: preview.length))
      text.append(preview)
    }
  }

  /// Like "October 2nd • 3:42 PM", with the year when it isn't this year.
  private static func dividerDate(_ date: Date) -> String {
    let day = Calendar.current.component(.day, from: date)
    let suffix: String
    switch day {
    case 11, 12, 13: suffix = "th"
    default:
      switch day % 10 {
      case 1: suffix = "st"
      case 2: suffix = "nd"
      case 3: suffix = "rd"
      default: suffix = "th"
      }
    }

    let isCurrentYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
    let formatter = DateFormatter()
    formatter.dateFormat = isCurrentYear
      ? "MMMM d'\(suffix)' \u{2022} h:mm a"
      : "MMMM d'\(suffix)', yyyy \u{2022} h:mm a"
    return formatter.string(from: date)
  }
}
