import AppKit

import UniformTypeIdentifiers

/// Builds the text for each chat message: who said it, their icon, and what they said, in Markdown,
/// as it's shown everywhere: formatted, with its links, code blocks, quotes and lists, links to
/// files on Hotline servers shown as the file, and previews of linked images.
///
/// Each line of a message is a paragraph of its own, the first with the sender's name and icon,
/// and the rest lined up under the first's wrapped lines.
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
  /// Marks a message that goes on from the one before it, from the same person, which goes
  /// without their name and icon.
  static let groupedKey = NSAttributedString.Key("chatGrouped")
  /// Marks server messages, which get a rounded background.
  static let serverMessageKey = NSAttributedString.Key("chatServerMessage")
  /// Marks date dividers between sessions, which get a line above them.
  static let dividerKey = NSAttributedString.Key("chatDivider")
  /// Text that watch words shouldn't highlight, like names and your own messages.
  static let skipHighlightKey = NSAttributedString.Key("chatSkipHighlight")

  /// How messages are shown: what the settings ask for, and which server the chat is on.
  struct Options: Equatable {
    /// Whether messages have their sender's icon before them. Without, there's no icon column.
    var showsIcons = true
    /// Whether links to images have a preview under them.
    var previewsImages = true
    /// Whether people connecting and disconnecting are shown.
    var showsConnections = true
    /// Admins' names, and when they come and go, in place of Hotline's red, as a server's theme has
    /// them.
    var adminColor: NSColor? = nil
    /// What matters less, like emotes, and people coming and going, in place of the system's
    /// secondary color, as a server's theme has it.
    var secondaryColor: NSColor? = nil
    /// What matters least, like the days between messages, in place of the system's tertiary color,
    /// as a server's theme has it.
    var tertiaryColor: NSColor? = nil

    /// How what's said is laid out: in chat's font, starting after the icon column, and further in
    /// than the name, where a message's wrapped lines start, with code blocks closer to what's
    /// around them, previews, if images are previewed, and in the server's theme's colors.
    var layout: Markdown.Layout {
      Markdown.Layout(
        font: ChatMessageRenderer.baseFont,
        lineSpacing: 3,
        indent: (self.showsIcons ? ChatMessageRenderer.textIndent : 0) + ChatMessageRenderer.hangingIndent,
        codePadding: ChatMessageRenderer.codeBlockPadding,
        codeBlockSpacing: 6,
        imagePreviews: self.previewsImages ? ChatMessageRenderer.previewLimit : 0,
        colors: Markdown.Colors(secondary: self.secondaryColor, tertiary: self.tertiaryColor)
      )
    }
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

  static let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  static let semiboldFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
  static let linkColor = NSColor(named: "Link Color") ?? .linkColor
  private static let adminColor = NSColor(named: "Hotline Red") ?? .systemRed

  // MARK: Rendering

  /// A message's text. One `continuing` the message before it, from the same person, goes without
  /// their name and icon.
  static func render(_ message: ChatMessage, continuing: Bool = false, options: Options = Options()) -> NSAttributedString {
    let text: NSMutableAttributedString
    switch message.type {
    case .message:
      if !message.isEmote {
        return self.chat(message, continuing: continuing, options: options)
      }
      text = self.emote(message, options: options)
    case .joined:
      text = self.presence(message, marker: .arrow("\u{2192}"), options: options)
    case .left:
      text = self.presence(message, marker: .arrow("\u{2190}"), options: options)
    case .renamed:
      text = self.presence(message, marker: .arrow("\u{2197}"), options: options)
    case .boardPost:
      text = self.presence(message, marker: .symbol("pin.fill"), options: options)
      // To the post, from the words, not the pin or the space after it.
      if let link = message.metadata?.link.flatMap({ URL(string: $0) }) {
        let start = text.length - (message.text as NSString).length
        text.addAttribute(.link, value: link, range: NSRange(location: start, length: text.length - start))
      }
    case .subject:
      text = self.presence(message, marker: .symbol("quote.closing"), options: options)
    case .signOut:
      text = self.divider(message, options: options)
    case .server:
      text = self.serverMessage(message)
    case .agreement:
      text = NSMutableAttributedString()
    }

    // Which message it is, and when it was sent, all through it.
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
    // Words on a line, as most messages are, made all at once.
    if !Markdown.mightBeMoreThanWords(message.text) {
      return self.words(message, continuing: continuing, options: options)
    }
    let layout = options.layout
    let text = Markdown.shownText(message.text, layout: layout)
    let start = options.showsIcons ? self.textIndent : 0
    let named = message.username != nil && !continuing

    // A message starts where the name does, unless it goes on from the one before it, under its
    // first line, as the rest of its lines are. A quote, a list's item, a heading, or code, at the
    // start, goes on the line after the name.
    let startsWithWords = text.length == 0 || text.attribute(Markdown.blockKey, at: 0, effectiveRange: nil) == nil
    if named, !startsWithWords {
      text.insert(NSAttributedString(string: "\n", attributes: [.font: self.baseFont, .paragraphStyle: layout.paragraph()]), at: 0)
    }
    // Room before the message, from the one before it, but for one going on from it, and after it,
    // as much as messages from the same person have between them, or more, after code.
    let movesFirstLine = !continuing && (named || startsWithWords)
    if text.length > 0 {
      let string = text.string as NSString
      let first = string.paragraphRange(for: NSRange(location: 0, length: 0))
      let last = string.paragraphRange(for: NSRange(location: text.length - 1, length: 0))
      self.restyleParagraph(first, in: text) { paragraph in
        if movesFirstLine {
          paragraph.firstLineHeadIndent = start
        }
        paragraph.paragraphSpacingBefore = max(paragraph.paragraphSpacingBefore, continuing ? 0 : self.messageSpacing - self.groupedSpacing)
        if first == last {
          paragraph.paragraphSpacing = max(paragraph.paragraphSpacing, self.groupedSpacing)
        }
      }
      if first != last {
        self.restyleParagraph(last, in: text) { paragraph in
          paragraph.paragraphSpacing = max(paragraph.paragraphSpacing, self.groupedSpacing)
        }
      }
    }

    if let username = message.username, !continuing {
      // In the first line's style, or a message's, with nothing after the name.
      let paragraph = text.length > 0 ? text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
      let nameAttributes: [NSAttributedString.Key: Any] = [
        .font: self.semiboldFont,
        .foregroundColor: message.isAdmin ? options.adminColor ?? self.adminColor : NSColor.textColor,
        .paragraphStyle: paragraph ?? self.messageParagraph(showsIcons: options.showsIcons),
        self.skipHighlightKey: true,
      ]
      let name = NSMutableAttributedString(string: "\(username): ", attributes: nameAttributes)
      // The name, with the icon they had, to tell apart people with the same name.
      let nameRange = NSRange(location: 0, length: (username as NSString).length)
      name.addAttribute(self.userNameKey, value: username, range: nameRange)
      if let iconID = message.iconID {
        name.addAttribute(self.iconIDKey, value: NSNumber(value: iconID), range: nameRange)
      }
      text.insert(name, at: 0)
    }

    let range = NSRange(location: 0, length: text.length)
    guard range.length > 0 else {
      return text
    }
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
    text.addAttribute(self.messageIDKey, value: message.id, range: range)
    text.addAttribute(self.messageDateKey, value: message.date, range: range)
    return text
  }

  /// A message of words on one line, with nothing that could be Markdown, as most are, made all at
  /// once, as Markdown would make it, with the name before it, as fewer changes to its text are
  /// quicker.
  private static func words(_ message: ChatMessage, continuing: Bool, options: Options) -> NSMutableAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: self.baseFont,
      .foregroundColor: NSColor.textColor,
      .paragraphStyle: self.messageParagraph(continuing: continuing, showsIcons: options.showsIcons),
      self.messageIDKey: message.id,
      self.messageDateKey: message.date,
    ]
    if continuing {
      attributes[self.groupedKey] = true
    }
    // Watch words don't highlight in your own messages.
    if let username = message.username, username.lowercased() == Prefs.shared.username.lowercased() {
      attributes[self.skipHighlightKey] = true
    }
    if let username = message.username, options.showsIcons, !continuing {
      attributes[self.senderNameKey] = username
      if let iconID = message.iconID {
        attributes[self.iconIDKey] = NSNumber(value: iconID)
      }
    }
    // Without the spaces at its end, as Markdown has it.
    var words = Substring(message.text)
    while let last = words.last, last.isWhitespace {
      words = words.dropLast()
    }
    let text = NSMutableAttributedString(string: String(words), attributes: attributes)

    if let username = message.username, !continuing {
      attributes[.font] = self.semiboldFont
      attributes[.foregroundColor] = message.isAdmin ? options.adminColor ?? self.adminColor : NSColor.textColor
      attributes[self.skipHighlightKey] = true
      let name = NSMutableAttributedString(string: "\(username): ", attributes: attributes)
      // The name, with the icon they had, to tell apart people with the same name.
      let nameRange = NSRange(location: 0, length: (username as NSString).length)
      name.addAttribute(self.userNameKey, value: username, range: nameRange)
      if let iconID = message.iconID {
        name.addAttribute(self.iconIDKey, value: NSNumber(value: iconID), range: nameRange)
      }
      text.insert(name, at: 0)
    }
    return text
  }

  /// Changes the style of a paragraph.
  private static func restyleParagraph(_ paragraph: NSRange, in text: NSMutableAttributedString, _ change: (NSMutableParagraphStyle) -> Void) {
    text.enumerateAttribute(.paragraphStyle, in: paragraph) { value, part, _ in
      let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
      change(style)
      text.addAttribute(.paragraphStyle, value: style, range: part)
    }
  }

  private static func emote(_ message: ChatMessage, options: Options) -> NSMutableAttributedString {
    let paragraph = self.messageParagraph(showsIcons: options.showsIcons)
    let italic = NSFont(descriptor: self.baseFont.fontDescriptor.withSymbolicTraits(.italic), size: self.baseFont.pointSize) ?? self.baseFont

    // Without the "*** " that marks an emote.
    let displayText = self.lineSeparated(message.text.firstMatch(of: ChatMessage.emoteParser).map { String($0.1) } ?? message.text)
    let text = NSMutableAttributedString(
      string: displayText,
      attributes: [
        .font: italic,
        .foregroundColor: options.secondaryColor ?? NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph,
      ]
    )
    // Its links, as a message's are.
    if self.mightHaveLinks(displayText) {
      for link in displayText.detectedLinks() {
        text.addAttributes([.link: link.url, .foregroundColor: self.linkColor], range: NSRange(link.range, in: displayText))
      }
      Markdown.shortenLongLinks(in: text)
      Markdown.showFileLinks(in: text)
    }
    return text
  }

  /// What marks a line about someone in the icon column: an arrow, or an SF Symbol.
  private enum Marker {
    case arrow(String)
    case symbol(String)
  }

  /// Someone connecting, disconnecting, changing their name, or posting to the board, or a private
  /// chat's subject changing, with what marks it in the icon column. Without icons, that goes first, and the text where messages'
  /// wrapped lines start.
  private static func presence(_ message: ChatMessage, marker: Marker, options: Options) -> NSMutableAttributedString {
    let color = message.isAdmin ? options.adminColor ?? self.adminColor : options.secondaryColor ?? NSColor.secondaryLabelColor
    let mark: NSAttributedString
    let markWidth: CGFloat
    switch marker {
    case .arrow(let arrow):
      mark = NSAttributedString(string: arrow)
      markWidth = (arrow as NSString).size(withAttributes: [.font: self.baseFont]).width
    case .symbol(let name):
      let attachment = self.symbolAttachment(name, color: color)
      mark = NSAttributedString(attachment: attachment)
      markWidth = attachment.bounds.width
    }

    let paragraph = NSMutableParagraphStyle()
    let textStart = options.showsIcons ? self.textIndent : self.hangingIndent
    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
    paragraph.headIndent = textStart
    if options.showsIcons {
      // In the middle of the icon column, where messages have the sender's icon.
      paragraph.firstLineHeadIndent = max(0, self.iconInset + self.iconColumnWidth / 2 - markWidth / 2)
    }
    paragraph.lineSpacing = 2
    paragraph.paragraphSpacingBefore = self.messageSpacing - self.groupedSpacing
    paragraph.paragraphSpacing = self.groupedSpacing

    let text = NSMutableAttributedString(attributedString: mark)
    text.append(NSAttributedString(string: "\t\(message.text)"))
    text.addAttributes([
      .font: self.baseFont,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
      self.skipHighlightKey: true,
    ], range: NSRange(location: 0, length: text.length))
    return text
  }

  /// How big an SF Symbol marking a line is, to look as big as the arrows marking the others. A
  /// narrow one, like the pin, is taller than they are.
  private static let markerSymbolSize: CGFloat = 10

  /// An SF Symbol marking a line, in the line's color, its middle level with the arrows' on the
  /// lines around it.
  private static func symbolAttachment(_ name: String, color: NSColor) -> NSTextAttachment {
    let attachment = NSTextAttachment()
    let configuration = NSImage.SymbolConfiguration(pointSize: self.markerSymbolSize, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
      // Rather than the 32 points square an attachment without bounds takes.
      attachment.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
      return attachment
    }
    // The color where the symbol is, as the text has it. A symbol's own colors make one you can see
    // through lighter, as the secondary color is.
    let image = NSImage(size: symbol.size, flipped: false) { rect in
      color.set()
      rect.fill()
      symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
      return true
    }
    // Drawn each time, for a color that's different in dark mode.
    image.cacheMode = .never
    attachment.image = image
    let y = self.arrowMidY - symbol.alignmentRect.midY
    attachment.bounds = CGRect(x: 0, y: y.rounded(), width: symbol.size.width, height: symbol.size.height)
    return attachment
  }

  /// How far above the baseline the middle of the arrows marking lines is.
  private static var arrowMidY: CGFloat {
    let font = self.baseFont as CTFont
    var character = UniChar(0x2192)
    var glyph = CGGlyph()
    CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
    return CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, nil, 1).midY
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

  /// Chat lines start after the icon column, and wrap further in than the name. A message going on
  /// from the one before it starts where those wrapped lines do, close under it.
  private static func messageParagraph(continuing: Bool = false, showsIcons: Bool = true) -> NSParagraphStyle {
    self.messageParagraphs[(continuing ? 1 : 0) + (showsIcons ? 2 : 0)]
  }

  /// Each way a message's paragraph can be, made once.
  private static let messageParagraphs = [(false, false), (true, false), (false, true), (true, true)].map { continuing, showsIcons in
    ChatMessageRenderer.makeMessageParagraph(continuing: continuing, showsIcons: showsIcons)
  }

  private static func makeMessageParagraph(continuing: Bool, showsIcons: Bool) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    let start = showsIcons ? self.textIndent : 0
    paragraph.firstLineHeadIndent = continuing ? start + self.hangingIndent : start
    paragraph.headIndent = start + self.hangingIndent
    paragraph.lineSpacing = 3
    paragraph.paragraphSpacingBefore = continuing ? 0 : self.messageSpacing - self.groupedSpacing
    paragraph.paragraphSpacing = self.groupedSpacing
    return paragraph
  }

  /// An emote's text with its line breaks as line separators, so it stays one paragraph. Classic
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
