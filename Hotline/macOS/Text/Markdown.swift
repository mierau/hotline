import AppKit

/// The Markdown people write in the app, in chat, on the board, in the news and in private
/// messages, styled the same wherever it is: as it's written, in the board's editor, with its marks
/// kept, faint, and everywhere else as it's shown, without them. Bold, italic and both, with * or _,
/// underline with __, strikethrough with ~ or ~~, `code`, code blocks between ```, colored as chat
/// colors them when they name a language, links, links to images, and addresses, which are made
/// links, headings, quotes, lists, and lines across. A mark opens at the start of a word, with
/// something other than a space after it, and closes at the end of one, with something other than
/// a space before it, so snake_case_names, 2*3*4 and ~5-~10 stay as they are. Nothing's styled
/// inside code, or where a link goes. Drawings, made of what would otherwise be marks, show in a fixed-width font,
/// as they were drawn.
enum Markdown {
  /// The most a post can be, as a field holds no more.
  static let maximumLength = HotlineTransactionField.maximumDataSize

  /// As the board's posts are.
  static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

  /// As what's written in the board's editor is.
  static var attributes: [NSAttributedString.Key: Any] {
    Layout.board.attributes
  }

  /// Code's font, and drawings'.
  static let codeFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)

  /// How wide a tab is in code, and drawings: four of their characters.
  private static let codeTabWidth = ("    " as NSString).size(withAttributes: [.font: Markdown.codeFont]).width

  private static let widths = NSCache<NSString, NSNumber>()

  /// How wide some words are in a font, measured once for each.
  static func width(of words: String, in font: NSFont) -> CGFloat {
    let key = "\(font.fontName) \(font.pointSize) \(words)" as NSString
    if let width = self.widths.object(forKey: key) {
      return CGFloat(width.doubleValue)
    }
    let width = (words as NSString).size(withAttributes: [.font: font]).width
    self.widths.setObject(NSNumber(value: Double(width)), forKey: key)
    return width
  }

  private static let styledFonts = NSCache<NSString, NSFont>()

  /// A font with traits added, like bold or italic, made once for each.
  static func font(_ font: NSFont, adding traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
    let key = "\(font.fontName) \(font.pointSize) \(traits.rawValue)" as NSString
    if let styled = self.styledFonts.object(forKey: key) {
      return styled
    }
    let styled = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)), size: font.pointSize) ?? font
    self.styledFonts.setObject(styled, forKey: key)
    return styled
  }

  static let linkColor = NSColor(named: "Link Color") ?? .linkColor

  // MARK: Layout

  /// How a place shows Markdown: its words' font, the room between its lines and where they start,
  /// the room code blocks have, and how many images it previews.
  struct Layout: Equatable {
    var font: NSFont = Markdown.font
    var lineSpacing: CGFloat = 4
    /// Where lines start, past anything before them, as chat's messages start past the sender's
    /// icon.
    var indent: CGFloat = 0
    /// How far a code block's background reaches past its code: across, and above and below it.
    var codePadding = NSSize(width: 10, height: 10)
    /// The room between a code block and what's above and below it.
    var codeBlockSpacing: CGFloat = 12
    /// At most how many links to images have a preview, under the line they're on.
    var imagePreviews = 10
    /// The colors of what matters less and least, and code's backgrounds, as a server's theme has
    /// them, or the system's.
    var colors = Colors()

    /// As the board shows posts, and the news shows articles.
    static let board = Layout()

    var attributes: [NSAttributedString.Key: Any] {
      [.font: self.font, .foregroundColor: NSColor.textColor, .paragraphStyle: self.paragraph()]
    }

    /// A line starting `firstLineHeadIndent` in from where lines start, with its wrapped lines
    /// `headIndent` in.
    func paragraph(firstLineHeadIndent: CGFloat = 0, headIndent: CGFloat = 0) -> NSParagraphStyle {
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineSpacing = self.lineSpacing
      paragraph.firstLineHeadIndent = self.indent + firstLineHeadIndent
      paragraph.headIndent = self.indent + headIndent
      return paragraph
    }

    /// What's shown is kept by this, as well as by what it shows.
    var key: String {
      [self.font.pointSize, self.lineSpacing, self.indent, self.codePadding.width, self.codePadding.height, self.codeBlockSpacing, CGFloat(self.imagePreviews)]
        .map { "\($0)" }
        .joined(separator: ",") + self.colors.key
    }
  }

  /// The colors Markdown's shown in, but for its words and links: what matters less, like a quote's
  /// words and a list's marks, what matters least, like marks as they're written, and lines across,
  /// and the backgrounds behind code. A server's theme's, or the system's, without one.
  struct Colors: Equatable {
    var secondary: NSColor = .secondaryLabelColor
    var tertiary: NSColor = .tertiaryLabelColor
    /// Behind `code` among words.
    var codeSpan: NSColor = .quaternarySystemFill
    /// Behind a code block.
    var codeBlock: NSColor = Colors.codeBlock

    /// A code block's background without a theme: a little darker than what's around it, or
    /// lighter, in dark mode.
    static let codeBlock = NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04) }

    /// In a theme's colors for what matters less and least, with code's backgrounds a faint wash of
    /// the first, or the system's, for any it doesn't have.
    init(secondary: NSColor? = nil, tertiary: NSColor? = nil) {
      if let secondary {
        self.secondary = secondary
        self.codeSpan = secondary.withAlphaComponent(0.14)
        self.codeBlock = secondary.withAlphaComponent(0.09)
      }
      if let tertiary {
        self.tertiary = tertiary
      }
    }

    fileprivate var key: String {
      [self.secondary, self.tertiary, self.codeSpan, self.codeBlock].map(\.description).joined(separator: "|")
    }
  }

  // MARK: Code

  /// Where a line of a code block is in it, for the fragment that draws its part of the block's
  /// background: rounded at the block's top and bottom, and square where its lines meet.
  static let codeLineKey = NSAttributedString.Key("markdownCodeLine")

  enum CodeLine: Int {
    case first, middle, last, only
    /// In the editor, a line of words that a code block opens at the end of, with the block's
    /// background behind its ``` and down into the block, and the block's first line under it, or
    /// its only one, joined to it.
    case opening, firstAfterOpening, onlyAfterOpening

    /// Whether the line has the bottom of its block.
    var isBottom: Bool {
      self == .last || self == .only || self == .onlyAfterOpening
    }
  }

  /// The ``` that opens a code block at the end of a line of words, and the language after it, for
  /// the fragment that draws the block's background behind them, in the editor.
  static let codeFenceKey = NSAttributedString.Key("markdownCodeFence")

  /// How far in from a code block's background its code is, in the editor.
  static let codePadding: CGFloat = 10

  /// How far a code block's background reaches past its ``` lines, in the editor, above and below.
  static let codeEditorPadding: CGFloat = 5

  /// The room between a code block and what's above and below it, in the editor.
  static let codeBlockSpacing: CGFloat = 12

  /// The language a code block names, on its first line as it's shown, for the fragment that draws
  /// it above the code, and not as words to select.
  static let codeLanguageKey = NSAttributedString.Key("markdownCodeLanguage")

  /// The room above a code block's code, as it's shown, for the language it names.
  static let codeLanguageHeight: CGFloat = 16

  /// The kind of code something's in: a code block, or `code` among the words, or a drawing,
  /// where what would be marks are what it's drawn with.
  enum CodeContext {
    case block
    case span
    case drawing
  }

  /// A code block. Ranges count UTF-16 code units, as NSString does.
  struct CodeBlock: Equatable {
    /// All of it, from the start of its opening ``` to the end of its closing one.
    var range: NSRange
    /// Its code, the lines between its ```, if there are any.
    var code: NSRange
    /// The language named after the opening ```, like lua in ```lua.
    var language: String?
    /// Whether it has its closing ```, which only one asked for still open doesn't.
    var isClosed: Bool
    /// How many ` open it, which as many or more close.
    var ticks = 3
    /// Whether it opens at the start of a line, rather than at the end of one, after words that
    /// stay on their line, above it.
    var opensOwnLine = true
  }

  /// Where the code is: code blocks, and `code`, with its marks, and drawings, which aren't styled
  /// either.
  struct CodeRanges {
    var blocks: [CodeBlock] = []
    var spans: [NSRange] = []
    var drawings: [NSRange] = []

    /// The code a selection is in, or for where you're typing, inside, past the opening mark and
    /// not yet past the closing one, or anywhere on a drawing's lines.
    func context(of selection: NSRange) -> CodeContext? {
      func holds(_ range: NSRange) -> Bool {
        selection.length > 0 ? NSIntersectionRange(range, selection).length > 0 : selection.location > range.location && selection.location < NSMaxRange(range)
      }
      if self.blocks.contains(where: { holds($0.range) }) {
        return .block
      }
      if self.drawings.contains(where: { selection.length > 0 ? NSIntersectionRange($0, selection).length > 0 : NSLocationInRange(selection.location, $0) }) {
        return .drawing
      }
      return self.spans.contains(where: holds) ? .span : nil
    }

    /// The code block a selection's in, if it's in one.
    func block(holding selection: NSRange) -> CodeBlock? {
      self.blocks.first { selection.location > $0.range.location && NSMaxRange(selection) < NSMaxRange($0.range) }
    }

    func intersects(_ range: NSRange) -> Bool {
      (self.blocks.map(\.range) + self.spans + self.drawings).contains { NSIntersectionRange($0, range).length > 0 || (range.length == 0 && NSLocationInRange(range.location, $0)) }
    }
  }

  /// A line of a code block in the editor, in from its background's edges, and for its first and
  /// last lines, with room to what's above and below the block.
  private static func codeParagraph(_ place: CodeLine) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = self.codePadding
    paragraph.headIndent = self.codePadding
    paragraph.tailIndent = -self.codePadding
    paragraph.lineSpacing = 3
    switch place {
    case .first, .only:
      paragraph.paragraphSpacingBefore = self.codeBlockSpacing
    case .firstAfterOpening, .onlyAfterOpening:
      // Close under the line it opens at the end of, with as much room as the block has inside.
      paragraph.paragraphSpacingBefore = self.codeEditorPadding
    default:
      break
    }
    paragraph.paragraphSpacing = place.isBottom ? self.codeBlockSpacing : 0
    // Tabs four spaces wide, as most code is written.
    paragraph.tabStops = []
    paragraph.defaultTabInterval = self.codeTabWidth
    return paragraph
  }

  /// A line of a code block as it's shown, without the ``` lines, in from its background's edges,
  /// and for its first and last lines, with room to them, as far as it is from its sides, and to
  /// what's above and below the block, and above the first, for the language it names.
  static func shownCodeParagraph(_ place: CodeLine, named: Bool, layout: Layout) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = layout.indent + layout.codePadding.width
    paragraph.headIndent = paragraph.firstLineHeadIndent
    paragraph.tailIndent = -layout.codePadding.width
    paragraph.lineSpacing = 3
    if place == .first || place == .only {
      paragraph.paragraphSpacingBefore = layout.codeBlockSpacing + layout.codePadding.height + (named ? self.codeLanguageHeight : 0)
    }
    if place == .last || place == .only {
      paragraph.paragraphSpacing = layout.codeBlockSpacing + layout.codePadding.height
    }
    paragraph.tabStops = []
    paragraph.defaultTabInterval = self.codeTabWidth
    return paragraph
  }

  /// What a code block's language can be named with.
  private static let languageNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+#-_."))

  /// The code blocks in some text, as GitHub and Discord have them: from three or more ` at the
  /// start of a line, with the language the code's in after them, or at the end of a line, after
  /// words, which stay above the block, to a line of as many or more `, or as many at the end of
  /// the block's last line. With more than a language after the opening ```, the code starts there,
  /// on the same line. A ``` without a closing one stays as it's typed, rather than making the rest
  /// code, and the editor puts in the closing one as the opening one's written. Asked to, it gives
  /// back one still open, at the end, as the editor needs, to do that. ```code``` on a line, with
  /// both on it, is `code` among the words, not a block.
  static func codeBlocks(in text: NSString, includingUnclosed: Bool = false) -> [CodeBlock] {
    var blocks: [CodeBlock] = []
    var open: CodeBlock?
    var lineStart = 0
    while lineStart < text.length {
      let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
      let end = self.contentEnd(of: line, in: text)
      lineStart = NSMaxRange(line)
      // Only lines with a ` in them can open or close one.
      guard end > line.location, text.range(of: "`", options: .literal, range: NSRange(location: line.location, length: end - line.location)).location != NSNotFound else {
        continue
      }
      if var block = open {
        guard let closing = self.closingFence(in: text, line: line, end: end, ticks: block.ticks) else {
          continue
        }
        // Not the line break before a closing ``` on a line of its own.
        var codeEnd = closing.codeEnd
        if codeEnd == line.location {
          if codeEnd > block.code.location, text.character(at: codeEnd - 1) == 0x0A {
            codeEnd -= 1
          }
          if codeEnd > block.code.location, text.character(at: codeEnd - 1) == 0x0D {
            codeEnd -= 1
          }
        }
        block.range.length = closing.end - block.range.location
        block.code.length = max(0, codeEnd - block.code.location)
        block.isClosed = true
        blocks.append(block)
        open = nil
      }
      else {
        open = self.openingFence(in: text, line: line, end: end)
      }
    }
    if var block = open, includingUnclosed {
      block.code.location = min(block.code.location, text.length)
      block.code.length = text.length - block.code.location
      block.range.length = text.length - block.range.location
      blocks.append(block)
    }
    return blocks
  }

  /// A code block opening on a line: at its start, after up to three spaces, with no other ` on
  /// the line, or at its end, after words with no ``` among them, with nothing after the ``` but a
  /// language. Still open, until a line closes it.
  private static func openingFence(in text: NSString, line: NSRange, end: Int) -> CodeBlock? {
    func ticks(from index: Int) -> Int {
      var count = 0
      while index + count < end, text.character(at: index + count) == 0x60 {
        count += 1
      }
      return count
    }
    func language(in range: NSRange) -> (name: String?, isName: Bool) {
      let words = text.substring(with: range).trimmingCharacters(in: .whitespaces)
      if words.isEmpty {
        return (nil, true)
      }
      let isName = words.unicodeScalars.allSatisfy { self.languageNameCharacters.contains($0) }
      return (isName ? words : nil, isName)
    }

    // At the start of the line.
    var index = line.location
    while index < min(end, line.location + 3), text.character(at: index) == 0x20 {
      index += 1
    }
    let leading = ticks(from: index)
    if leading >= 3 {
      let after = NSRange(location: index + leading, length: end - index - leading)
      guard text.range(of: "`", options: .literal, range: after).location == NSNotFound else {
        return nil
      }
      let named = language(in: after)
      // More than a language, and the code starts right after the ```.
      let code = named.isName ? NSMaxRange(line) : index + leading
      return CodeBlock(range: NSRange(location: line.location, length: 0), code: NSRange(location: code, length: 0), language: named.name, isClosed: false, ticks: leading)
    }

    // At the end of the line, after words.
    var last = end
    while last > line.location, text.character(at: last - 1) != 0x60 {
      last -= 1
    }
    var first = last
    while first > line.location, text.character(at: first - 1) == 0x60 {
      first -= 1
    }
    let words = NSRange(location: line.location, length: first - line.location)
    let named = language(in: NSRange(location: last, length: end - last))
    guard last - first >= 3, named.isName,
          !text.substring(with: words).trimmingCharacters(in: .whitespaces).isEmpty,
          text.range(of: "```", options: .literal, range: words).location == NSNotFound else {
      return nil
    }
    return CodeBlock(range: NSRange(location: first, length: 0), code: NSRange(location: NSMaxRange(line), length: 0), language: named.name, isClosed: false, ticks: last - first, opensOwnLine: false)
  }

  /// Where a code block's code ends, and its closing ``` does, on a line that closes it: a line of
  /// as many ` as opened it, or more, or one that ends with them, after code.
  private static func closingFence(in text: NSString, line: NSRange, end: Int, ticks: Int) -> (codeEnd: Int, end: Int)? {
    var last = end
    while last > line.location, text.character(at: last - 1) == 0x20 || text.character(at: last - 1) == 0x09 {
      last -= 1
    }
    var first = last
    while first > line.location, text.character(at: first - 1) == 0x60 {
      first -= 1
    }
    guard last - first >= max(ticks, 3) else {
      return nil
    }
    let before = text.substring(with: NSRange(location: line.location, length: first - line.location))
    if before.trimmingCharacters(in: .whitespaces).isEmpty {
      return (line.location, last)
    }
    return (first, last)
  }

  /// Where a line's words end, before its line break.
  static func contentEnd(of line: NSRange, in text: NSString) -> Int {
    var end = NSMaxRange(line)
    while end > line.location, text.character(at: end - 1) == 0x0A || text.character(at: end - 1) == 0x0D {
      end -= 1
    }
    return end
  }

  // MARK: Quotes and Lists

  /// Where a quote's lines start in from the bar along them.
  static let quoteIndent: CGFloat = 12

  /// On a quote's lines, for the fragment that draws the bar along them.
  static let quoteLineKey = NSAttributedString.Key("markdownQuoteLine")

  /// What a quote's line or a list's item starts with: its mark, from the start of the line through
  /// the space after it, as "> ", "- ", or "2. ".
  struct LineMark {
    enum Kind: Equatable {
      case quote
      case bullet
      case number(Int)
    }

    var kind: Kind
    /// From the start of the line, through the space after the mark, if there is one.
    var length: Int
    /// The mark as it was typed, without its space, as - or 2. or 2).
    var mark: String

    /// The mark for the line after, going on with the quote or list: a list's next number.
    var next: String {
      switch self.kind {
      case .quote, .bullet:
        return self.mark
      case .number(let number):
        return "\(number + 1)" + String(self.mark.suffix(1))
      }
    }
  }

  /// The quote or list mark a line starts with, after up to three spaces: > with a space after it,
  /// or on its own, or -, * or + with a space after it, or a number and . or ) with a space after
  /// it. Not >, with something right after it, as in >_<.
  static func lineMark(in text: NSString, line: NSRange) -> LineMark? {
    let end = self.contentEnd(of: line, in: text)
    var index = line.location
    while index < min(end, line.location + 3), text.character(at: index) == 0x20 {
      index += 1
    }
    guard index < end else {
      return nil
    }
    func spaced(_ after: Int) -> Bool {
      after < end && text.character(at: after) == 0x20
    }
    let character = text.character(at: index)
    if character == 0x3E, spaced(index + 1) || index + 1 == end {
      let length = (spaced(index + 1) ? index + 2 : index + 1) - line.location
      return LineMark(kind: .quote, length: length, mark: ">")
    }
    if character == 0x2D || character == 0x2A || character == 0x2B, spaced(index + 1) {
      return LineMark(kind: .bullet, length: index + 2 - line.location, mark: text.substring(with: NSRange(location: index, length: 1)))
    }
    var digits = index
    while digits < end, digits - index < 9, (0x30...0x39).contains(text.character(at: digits)) {
      digits += 1
    }
    if digits > index, digits < end, text.character(at: digits) == 0x2E || text.character(at: digits) == 0x29, spaced(digits + 1),
       let number = Int(text.substring(with: NSRange(location: index, length: digits - index))) {
      return LineMark(kind: .number(number), length: digits + 2 - line.location, mark: text.substring(with: NSRange(location: index, length: digits + 1 - index)))
    }
    return nil
  }

  // MARK: Headings and Lines Across

  /// A heading's level, from 1 to 6, and its mark, from the start of the line through the spaces
  /// after its #s, as "## ", for a line of #s, a space, and words, after up to three spaces.
  static func heading(in text: NSString, line: NSRange) -> (level: Int, length: Int)? {
    let end = self.contentEnd(of: line, in: text)
    var index = line.location
    while index < min(end, line.location + 3), text.character(at: index) == 0x20 {
      index += 1
    }
    var level = 0
    while index + level < end, text.character(at: index + level) == 0x23 {
      level += 1
    }
    guard (1...6).contains(level), index + level < end, text.character(at: index + level) == 0x20 else {
      return nil
    }
    var words = index + level
    while words < end, text.character(at: words) == 0x20 {
      words += 1
    }
    return words < end ? (level, words - line.location) : nil
  }

  /// A heading's font: bold, and bigger than the words around it, the higher it is, up to the
  /// fourth level, which is as big as they are.
  static func headingFont(level: Int, for font: NSFont) -> NSFont {
    let scales: [CGFloat] = [1.5, 1.3, 1.15]
    let scale = level <= scales.count ? scales[level - 1] : 1
    return .systemFont(ofSize: (font.pointSize * scale).rounded(), weight: .bold)
  }

  /// A line that's a line across, as it's shown, for the fragment that draws it.
  static let ruleKey = NSAttributedString.Key("markdownRule")

  /// Whether a line is a line across: three or more -, * or _, and nothing else but spaces.
  static func isRule(_ text: NSString, line: NSRange) -> Bool {
    let end = self.contentEnd(of: line, in: text)
    var mark: unichar = 0
    var count = 0
    for index in line.location..<end {
      let character = text.character(at: index)
      if character == 0x20 || character == 0x09 {
        continue
      }
      guard character == 0x2D || character == 0x2A || character == 0x5F, mark == 0 || character == mark else {
        return false
      }
      mark = character
      count += 1
    }
    return count >= 3
  }

  // MARK: Drawings

  /// What drawings are made of, as they're typed, the shading pictures are drawn with here too, and
  /// as they're drawn with Unicode's box drawing, blocks, shapes and braille.
  private static let drawingCharacters = CharacterSet(charactersIn: #"|/\_-=+*#@[]()<>{}^~`.:;%&$"#)
    .union(CharacterSet(charactersIn: "\u{2500}"..."\u{25FF}"))
    .union(CharacterSet(charactersIn: "\u{2800}"..."\u{28FF}"))

  /// How a line looks, to find drawings by.
  private enum LineLook: Int {
    case blank
    /// Mostly what drawings are made of, or less, with more room between what's on it than words have.
    case drawn
    /// Lined up with the lines around it, with three spaces or more between what's on it, as a
    /// table's columns are.
    case spaced
    /// With what drawings are made of at both ends, as a box's sides are.
    case framed
    case words
  }

  private static let looks = NSCache<NSString, NSNumber>()

  /// How a line looks, as it's shown, worked out once for each line: without a list's or a quote's
  /// mark, or a task's box after one, which with words after it is a list's item, or a quote, and
  /// without the marks words are styled with, or addresses, which are made of what drawings are,
  /// but aren't drawings.
  private static func look(of line: String) -> LineLook {
    if let known = self.looks.object(forKey: line as NSString), let look = LineLook(rawValue: known.intValue) {
      return look
    }
    let look: LineLook
    if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      look = .blank
    }
    else {
      // Words with nothing in them that could be a mark or an address are as they're shown already.
      let words = line.trimmingCharacters(in: .newlines)
      look = self.look(shown: self.mightBeMoreThanWords(words) ? self.shownLine(line) : words)
    }
    self.looks.setObject(NSNumber(value: look.rawValue), forKey: line as NSString)
    return look
  }

  /// A line as it's shown, for finding drawings by, or nil for a list's item or a quote with words
  /// in it.
  private static func shownLine(_ line: String) -> String? {
    var text = line as NSString
    if let mark = self.lineMark(in: text, line: NSRange(location: 0, length: text.length)) {
      text = text.substring(from: mark.length) as NSString
      // A task's box, as in - [ ] or - [x].
      if mark.kind != .quote, text.length >= 3, text.character(at: 0) == 0x5B, text.character(at: 2) == 0x5D, " xX".utf16.contains(text.character(at: 1)) {
        text = text.substring(from: min(4, text.length)) as NSString
      }
      if text.rangeOfCharacter(from: .alphanumerics).location != NSNotFound || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return nil
      }
    }
    let storage = NSMutableAttributedString(string: text as String, attributes: self.attributes)
    let shown = Shown()
    self.styleWords(in: storage, range: NSRange(location: 0, length: storage.length), skipping: [], layout: .board, shown: shown)
    var left = IndexSet(integersIn: 0..<text.length)
    left.subtract(shown.hidden)
    for address in shown.addresses {
      left.remove(integersIn: address.location..<NSMaxRange(address))
    }
    let characters = left.map { text.character(at: $0) }
    return String(utf16CodeUnits: characters, count: characters.count)
  }

  private static func look(shown line: String?) -> LineLook {
    guard let line else {
      return .words
    }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    // All marks, or an address.
    guard !trimmed.isEmpty else {
      return .words
    }
    // Letters that aren't ASCII, as in other languages, don't count either way.
    var drawing = 0, total = 0
    for scalar in trimmed.unicodeScalars where scalar != " " {
      let drawn = self.drawingCharacters.contains(scalar)
      if drawn || scalar.isASCII {
        total += 1
        drawing += drawn ? 1 : 0
      }
    }
    let share = total > 0 ? Double(drawing) / Double(total) : 0
    // Three spaces or more between what's on it.
    var spaces = 0
    var spaced = false
    for scalar in trimmed.unicodeScalars {
      if scalar == " " {
        spaces += 1
      }
      else {
        spaced = spaced || spaces >= 3
        spaces = 0
      }
    }
    if share > 0.3 || (share > 0.15 && spaced) {
      return .drawn
    }
    if spaced {
      return .spaced
    }
    if let first = trimmed.unicodeScalars.first, let last = trimmed.unicodeScalars.last, trimmed.unicodeScalars.count > 2,
       self.drawingCharacters.contains(first), self.drawingCharacters.contains(last) {
      return .framed
    }
    return .words
  }

  /// The drawings in some text, outside its code blocks: lines together, or with blank lines
  /// between them, three or more of them drawn or lined up as a table's are, or a box's top and
  /// bottom with its sides between them. Each one's from the start of its first line through the
  /// line break after its last.
  static func drawings(in text: NSString, skipping skipped: [NSRange] = []) -> [NSRange] {
    // A drawing has three lines at least.
    var lineBreaks = 0
    var searched = NSRange(location: 0, length: text.length)
    while lineBreaks < 2 {
      let found = text.rangeOfCharacter(from: .newlines, options: .literal, range: searched)
      guard found.location != NSNotFound else {
        return []
      }
      lineBreaks += 1
      searched = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
    }
    var drawings: [NSRange] = []
    var lines: [(range: NSRange, look: LineLook)] = []
    func finish() {
      while lines.last?.look == .blank {
        lines.removeLast()
      }
      let drawn = lines.filter { $0.look == .drawn }.count
      let spaced = lines.filter { $0.look == .spaced }.count
      let framed = lines.filter { $0.look == .framed }.count
      if let first = lines.first, let last = lines.last, drawn + spaced >= 3 || (drawn >= 2 && drawn + spaced + framed >= 3) {
        drawings.append(NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location))
      }
      lines = []
    }
    var lineStart = 0
    while lineStart < text.length {
      let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
      lineStart = NSMaxRange(line)
      guard !skipped.contains(where: { NSIntersectionRange($0, line).length > 0 }) else {
        finish()
        continue
      }
      switch self.look(of: text.substring(with: line)) {
      case .words:
        finish()
      case .blank:
        if !lines.isEmpty {
          lines.append((line, .blank))
        }
      case let look:
        lines.append((line, look))
      }
    }
    finish()
    return drawings
  }

  /// As a drawing's lines are, as close together as the font has them, for what's drawn across
  /// them to meet, with tabs as wide as four of its characters.
  private static func drawingParagraph(_ layout: Layout) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = layout.indent
    paragraph.headIndent = layout.indent
    paragraph.tabStops = []
    paragraph.defaultTabInterval = self.codeTabWidth
    return paragraph
  }

  /// A drawing, in the code font, so its lines line up as they were drawn, with its addresses as
  /// links, and nothing else styled, as what would be marks in words are what it's drawn with.
  static func styleDrawing(_ range: NSRange, in storage: NSMutableAttributedString, layout: Layout = .board, shown: Shown? = nil) {
    storage.addAttributes([.font: self.codeFont, .paragraphStyle: self.drawingParagraph(layout)], range: range)
    if shown != nil {
      storage.addAttribute(self.blockKey, value: true, range: range)
    }
    let string = storage.string as NSString
    var lineStart = range.location
    while lineStart < NSMaxRange(range) {
      let line = string.lineRange(for: NSRange(location: lineStart, length: 0))
      let words = string.substring(with: line)
      for link in words.detectedLinks() {
        let found = NSRange(link.range, in: words)
        let address = NSRange(location: line.location + found.location, length: found.length)
        storage.addAttribute(.foregroundColor, value: self.linkColor, range: address)
        shown?.links.append((address, link.url))
      }
      lineStart = NSMaxRange(line)
    }
  }

  // MARK: Links

  /// A link, [its words](where it goes), or with ! before it, an image, ![what it is](where it is).
  private static let linkPattern = try! NSRegularExpression(pattern: #"(!?)\[([^\]\n]*)\]\(([^)\s]*)\)"#)

  /// Where a link goes, from what's written for it: an address, with its scheme, or one that would
  /// be made a link of on its own, like example.com, or nil for nowhere, or anywhere a link that's
  /// found couldn't go, like a file on this Mac.
  private static func destination(_ written: String) -> URL? {
    if let url = URL(string: written), let scheme = url.scheme?.lowercased() {
      return String.linkSchemes.contains(scheme) ? url : nil
    }
    return written.detectedLinks().first { NSRange($0.range, in: written).length == (written as NSString).length }?.url
  }

  /// The link a range is in, all of it, and its words.
  static func link(around range: NSRange, in text: NSString) -> (range: NSRange, words: NSRange)? {
    let line = text.lineRange(for: NSRange(location: range.location, length: 0))
    for match in self.linkPattern.matches(in: text as String, range: line)
    where range.length > 0
      ? range.location >= match.range.location && NSMaxRange(range) <= NSMaxRange(match.range)
      : range.location > match.range.location && range.location < NSMaxRange(match.range) {
      return (match.range, match.range(at: 2))
    }
    return nil
  }

  // MARK: Styling

  /// Paragraphs that are something other than words, as they're shown: code, a quote, a list's
  /// item, a heading, a line across, or a drawing.
  static let blockKey = NSAttributedString.Key("markdownBlock")

  /// Styles all of the text, as it's written, in a server's theme's colors, or the system's, and
  /// gives back where the code in it is.
  @discardableResult
  static func style(_ storage: NSTextStorage, colors: Colors = Colors()) -> CodeRanges {
    let string = storage.string as NSString
    let all = NSRange(location: 0, length: string.length)
    var layout = Layout.board
    layout.colors = colors
    // Attributes only, as it's done while the text storage is still taking an edit.
    storage.setAttributes(self.attributes, range: all)
    var code = CodeRanges(blocks: self.codeBlocks(in: string))
    code.drawings = self.drawings(in: string, skipping: code.blocks.map(\.range))
    for block in code.blocks {
      self.styleBlock(block, in: storage, colors: colors)
    }
    for drawing in code.drawings {
      self.styleDrawing(drawing, in: storage)
    }
    code.spans = self.styleWords(in: storage, range: all, skipping: code.blocks.map(\.range) + code.drawings, layout: layout)
    return code
  }

  /// Styles again what an edit changed: the lines it's in, and any code block or drawing among
  /// them, when where those are hasn't changed, and otherwise, all of it. Typing in a long post only
  /// styles the line it's on.
  static func restyle(_ storage: NSTextStorage, edited: NSRange, changeInLength delta: Int, after previous: CodeRanges, colors: Colors = Colors()) -> CodeRanges {
    let string = storage.string as NSString
    let blocks = self.codeBlocks(in: string)
    let drawings = self.drawings(in: string, skipping: blocks.map(\.range))
    // What the edit replaced, where it was.
    let replaced = NSRange(location: edited.location, length: max(0, edited.length - delta))
    func moved(_ range: NSRange) -> NSRange? {
      if NSMaxRange(range) <= replaced.location {
        return range
      }
      if range.location >= NSMaxRange(replaced) {
        return NSRange(location: range.location + delta, length: range.length)
      }
      if range.location <= replaced.location && NSMaxRange(replaced) <= NSMaxRange(range) {
        return NSRange(location: range.location, length: range.length + delta)
      }
      return nil
    }
    let unmoved = previous.blocks.map { block -> CodeBlock? in
      guard let range = moved(block.range), let code = moved(block.code) else {
        return nil
      }
      var moved = block
      moved.range = range
      moved.code = code
      return moved
    }
    guard unmoved == blocks.map({ Optional($0) }), previous.drawings.map(moved) == drawings.map({ Optional($0) }) else {
      return self.style(storage, colors: colors)
    }

    // The lines the edit's in, the one it ends in too, as when it breaks one in two, and all of any
    // code block or drawing among them.
    var region = NSUnionRange(string.paragraphRange(for: edited), string.paragraphRange(for: NSRange(location: NSMaxRange(edited), length: 0)))
    for block in blocks where NSIntersectionRange(string.paragraphRange(for: block.range), region).length > 0 {
      region = NSUnionRange(region, string.paragraphRange(for: block.range))
    }
    for drawing in drawings where NSIntersectionRange(drawing, region).length > 0 {
      region = NSUnionRange(region, drawing)
    }
    storage.setAttributes(self.attributes, range: region)
    for block in blocks where NSIntersectionRange(string.paragraphRange(for: block.range), region).length > 0 {
      self.styleBlock(block, in: storage, colors: colors)
    }
    for drawing in drawings where NSIntersectionRange(drawing, region).length > 0 {
      self.styleDrawing(drawing, in: storage)
    }
    var layout = Layout.board
    layout.colors = colors
    let spans = previous.spans.compactMap(moved).filter { NSIntersectionRange($0, region).length == 0 }
      + self.styleWords(in: storage, range: region, skipping: blocks.map(\.range) + drawings, layout: layout)
    return CodeRanges(blocks: blocks, spans: spans.sorted { $0.location < $1.location }, drawings: drawings)
  }

  /// What styling takes out of the text, or changes, or finds in it, to show it.
  final class Shown {
    /// The marks, and a code block's ``` lines, which aren't shown.
    var hidden = IndexSet()
    /// Links, by their words, and addresses, by themselves, and where they go.
    var links: [(range: NSRange, url: URL)] = []
    /// Addresses, which are links by themselves.
    var addresses: [NSRange] = []
    /// Where a list's - * or + is, which shows as a bullet.
    var bullets: [Int] = []
    /// Links to images, with the end of the line each is on, for its preview, under it, and
    /// whether it was written as an image, ![like this](where it is), which is shown as the image
    /// alone.
    var images: [(lineEnd: Int, url: URL, isImage: Bool)] = []
  }

  /// A code block, as it's written: its code in the code font, colored when it names a language,
  /// its ``` and language faint, and each of its lines with its place in the block, for the
  /// background behind it, from the line it opens on, or the one after, when it opens after words.
  private static func styleBlock(_ block: CodeBlock, in storage: NSMutableAttributedString, colors: Colors) {
    let string = storage.string as NSString
    let faint = colors.tertiary
    self.styleCode(of: block, in: storage)
    storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: block.range.location, length: max(0, block.code.location - block.range.location)))
    storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: NSMaxRange(block.code), length: max(0, NSMaxRange(block.range) - NSMaxRange(block.code))))
    let opening = string.lineRange(for: NSRange(location: block.range.location, length: 0))
    let first = block.opensOwnLine ? block.range.location : NSMaxRange(opening)
    guard first < NSMaxRange(block.range) else {
      return
    }
    // Words with a ``` at the end of their line keep their line, with the block's background
    // behind the ```, down into the block.
    if !block.opensOwnLine {
      storage.addAttribute(self.codeLineKey, value: CodeLine.opening.rawValue, range: opening)
      storage.addAttribute(self.codeFenceKey, value: true, range: NSRange(location: block.range.location, length: self.contentEnd(of: opening, in: string) - block.range.location))
    }
    let paragraphs = string.paragraphRange(for: NSRange(location: first, length: NSMaxRange(block.range) - first))
    var lines: [NSRange] = []
    var start = paragraphs.location
    while start < NSMaxRange(paragraphs) {
      let line = string.paragraphRange(for: NSRange(location: start, length: 0))
      lines.append(line)
      start = NSMaxRange(line)
    }
    for (index, line) in lines.enumerated() {
      var place: CodeLine = lines.count == 1 ? .only : index == 0 ? .first : index == lines.count - 1 ? .last : .middle
      if !block.opensOwnLine && index == 0 {
        place = lines.count == 1 ? .onlyAfterOpening : .firstAfterOpening
      }
      storage.addAttributes([.paragraphStyle: self.codeParagraph(place), self.codeLineKey: place.rawValue], range: line)
    }
  }

  /// A code block's ``` and code in the code font, and its code colored, when it names a language.
  /// Not the line break after words with a ``` at the end of their line, which ends their line.
  private static func styleCode(of block: CodeBlock, in storage: NSMutableAttributedString, font: NSFont = Markdown.font) {
    storage.addAttribute(.font, value: self.codeFont, range: block.range)
    if !block.opensOwnLine {
      let string = storage.string as NSString
      let line = string.lineRange(for: NSRange(location: block.range.location, length: 0))
      let end = self.contentEnd(of: line, in: string)
      storage.addAttribute(.font, value: font, range: NSRange(location: end, length: NSMaxRange(line) - end))
    }
    if block.code.length > 0, let language = block.language.flatMap({ CodeHighlighter.language(named: $0) }) {
      CodeHighlighter.highlight(storage, in: block.code, as: language)
    }
  }

  /// A code block as it's shown: the lines of its code, without the ``` around them or the blank
  /// lines at either end of it, with the language it names on the first, or nothing at all, for
  /// one with no code in it. Words before a ``` at the end of their line stay on it, above.
  static func showBlock(_ block: CodeBlock, in storage: NSMutableAttributedString, layout: Layout, shown: Shown) {
    let string = storage.string as NSString
    self.styleCode(of: block, in: storage, font: layout.font)
    func isLineBreak(_ index: Int) -> Bool {
      string.character(at: index) == 0x0A || string.character(at: index) == 0x0D
    }
    // Where what's hidden of the opening starts: the start of its line, or for one after words,
    // the spaces before it.
    let openingLine = string.lineRange(for: NSRange(location: block.range.location, length: 0))
    var opening = block.opensOwnLine ? openingLine.location : block.range.location
    while !block.opensOwnLine, opening > openingLine.location, string.character(at: opening - 1) == 0x20 || string.character(at: opening - 1) == 0x09 {
      opening -= 1
    }
    // Through the line break after the closing ```, which ends the code's last line once the ```
    // are gone.
    let whole = NSUnionRange(openingLine, string.paragraphRange(for: NSRange(location: NSMaxRange(block.range), length: 0)))
    var start = block.code.location, end = NSMaxRange(block.code)
    while start < end, isLineBreak(start) {
      start += 1
    }
    while end > start, isLineBreak(end - 1) {
      end -= 1
    }
    guard end > start else {
      if block.opensOwnLine {
        shown.hidden.insert(integersIn: whole.location..<NSMaxRange(whole))
      }
      else {
        // But the words before it, and the line break after them.
        shown.hidden.insert(integersIn: opening..<self.contentEnd(of: openingLine, in: string))
        shown.hidden.insert(integersIn: NSMaxRange(openingLine)..<NSMaxRange(whole))
      }
      return
    }
    if block.opensOwnLine {
      shown.hidden.insert(integersIn: opening..<start)
    }
    else {
      // The words before it keep the line break after them.
      shown.hidden.insert(integersIn: opening..<self.contentEnd(of: openingLine, in: string))
      shown.hidden.insert(integersIn: NSMaxRange(openingLine)..<start)
    }
    shown.hidden.insert(integersIn: end..<NSMaxRange(block.range))
    // Nor the blank lines next to it, as it has room of its own around it.
    func isBlank(_ line: NSRange) -> Bool {
      string.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var before = block.opensOwnLine ? openingLine.location : 0
    while before > 0 {
      let line = string.lineRange(for: NSRange(location: before - 1, length: 0))
      guard isBlank(line) else {
        break
      }
      shown.hidden.insert(integersIn: line.location..<NSMaxRange(line))
      before = line.location
    }
    var after = NSMaxRange(whole)
    while after < string.length {
      let line = string.lineRange(for: NSRange(location: after, length: 0))
      guard isBlank(line) else {
        break
      }
      shown.hidden.insert(integersIn: line.location..<NSMaxRange(line))
      after = NSMaxRange(line)
    }

    var lines: [NSRange] = []
    var lineStart = start
    while lineStart < end {
      let line = string.paragraphRange(for: NSRange(location: lineStart, length: 0))
      lines.append(line)
      lineStart = NSMaxRange(line)
    }
    let last = lines.count - 1
    lines[last] = NSRange(location: lines[last].location, length: NSMaxRange(whole) - lines[last].location)
    // The line break that ends it, in its font, so the line's as tall as the others.
    storage.addAttribute(.font, value: self.codeFont, range: lines[last])
    for (index, line) in lines.enumerated() {
      let place: CodeLine = lines.count == 1 ? .only : index == 0 ? .first : index == last ? .last : .middle
      storage.addAttributes([.paragraphStyle: self.shownCodeParagraph(place, named: block.language != nil, layout: layout), self.codeLineKey: place.rawValue, self.blockKey: true], range: line)
    }
    if let language = block.language {
      storage.addAttribute(self.codeLanguageKey, value: language, range: lines[0])
    }
  }

  private enum Style {
    case bold, italic, boldItalic, underline, underlineItalic, strikethrough
  }

  /// Longer marks first, so ** isn't read as two *.
  private static let marks: [(mark: String, style: Style)] = [
    ("***", .boldItalic), ("___", .underlineItalic), ("**", .bold), ("__", .underline), ("~~", .strikethrough), ("*", .italic), ("_", .italic), ("~", .strikethrough),
  ]

  /// What a \ before it keeps from being a mark.
  private static let escapable = "*_~`[]\\#>+-!".utf16

  /// Styles the words in a range of whole lines, but for what's in the ranges it skips, which are
  /// code blocks and drawings, and gives back where `code` among them is. To show them, it keeps
  /// what it'd take out, or change: their marks, and where their links go.
  @discardableResult
  static func styleWords(in storage: NSMutableAttributedString, range: NSRange, skipping skipped: [NSRange], layout: Layout, shown: Shown? = nil) -> [NSRange] {
    let string = storage.string as NSString
    let start = range.location
    let end = NSMaxRange(range)
    guard range.length > 0 else {
      return []
    }

    let faint = layout.colors.tertiary
    let linkColor = self.linkColor
    var taken = [Bool](repeating: false, count: range.length)
    func isTaken(_ index: Int) -> Bool {
      index < start || index >= end || taken[index - start]
    }
    func take(_ taking: NSRange) {
      for index in max(taking.location, start)..<min(NSMaxRange(taking), end) {
        taken[index - start] = true
      }
    }
    func hide(_ hiding: NSRange) {
      shown?.hidden.insert(integersIn: hiding.location..<NSMaxRange(hiding))
    }
    for skip in skipped where NSIntersectionRange(skip, range).length > 0 {
      take(skip)
    }

    // Lines across, headings, quotes, their words fainter, along a bar, and lists, their items'
    // lines lined up after their marks.
    var lineStart = start
    while lineStart < end {
      let line = string.paragraphRange(for: NSRange(location: lineStart, length: 0))
      lineStart = NSMaxRange(line)
      guard !isTaken(line.location) else {
        continue
      }
      let content = NSRange(location: line.location, length: self.contentEnd(of: line, in: string) - line.location)
      if self.isRule(string, line: line) {
        // Shown as a line across, with its marks there to copy, but not to see.
        storage.addAttribute(.foregroundColor, value: shown == nil ? faint : NSColor.clear, range: content)
        if shown != nil {
          storage.addAttributes([self.ruleKey: true, self.blockKey: true], range: line)
        }
        take(content)
      }
      else if let heading = self.heading(in: string, line: line) {
        let mark = NSRange(location: line.location, length: heading.length)
        let paragraph = (layout.paragraph().mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = (layout.font.pointSize * 0.5).rounded()
        paragraph.paragraphSpacing = 2
        storage.addAttributes([.font: self.headingFont(level: heading.level, for: layout.font), .paragraphStyle: paragraph], range: line)
        storage.addAttribute(.foregroundColor, value: faint, range: mark)
        if shown != nil {
          storage.addAttribute(self.blockKey, value: true, range: line)
        }
        hide(mark)
        take(mark)
      }
      else if let mark = self.lineMark(in: string, line: line) {
        let markRange = NSRange(location: line.location, length: mark.length)
        // As it's written, its lines line up after its mark.
        let markWidth = shown == nil ? self.width(of: string.substring(with: markRange), in: layout.font) : 0
        switch mark.kind {
        case .quote:
          // Shown without its mark, its lines all start the same way in from the bar.
          storage.addAttributes([
            .paragraphStyle: layout.paragraph(firstLineHeadIndent: self.quoteIndent, headIndent: self.quoteIndent + markWidth),
            .foregroundColor: layout.colors.secondary,
            self.quoteLineKey: true,
          ], range: line)
          storage.addAttribute(.foregroundColor, value: faint, range: markRange)
          hide(markRange)
        case .bullet, .number:
          storage.addAttribute(.foregroundColor, value: layout.colors.secondary, range: markRange)
          if let shown {
            // From the start of the line, with a bullet for its - * or +, and the item's lines
            // lined up after it.
            let indent = mark.length - (mark.mark as NSString).length - 1
            shown.hidden.insert(integersIn: line.location..<line.location + indent)
            if mark.kind == .bullet {
              shown.bullets.append(line.location + indent)
            }
            let shownWidth = self.width(of: (mark.kind == .bullet ? "•" : mark.mark) + " ", in: layout.font)
            storage.addAttribute(.paragraphStyle, value: layout.paragraph(headIndent: shownWidth), range: line)
          }
          else {
            storage.addAttribute(.paragraphStyle, value: layout.paragraph(headIndent: markWidth), range: line)
          }
        }
        if shown != nil {
          storage.addAttribute(self.blockKey, value: true, range: line)
        }
        take(markRange)
      }
    }

    // `code`, between runs of as many backticks, on the same line, with a run of another length,
    // or one without its match, staying as it's typed, as Markdown has it. A ` after a \ isn't
    // one, outside code, and nothing's anything else inside it.
    var spans: [NSRange] = []
    func backticks(at index: Int) -> Int {
      var run = 0
      while index + run < end, string.character(at: index + run) == 0x60, !isTaken(index + run) {
        run += 1
      }
      return run
    }
    func isEscaped(_ index: Int) -> Bool {
      var backslashes = 0
      while index - backslashes - 1 >= start, string.character(at: index - backslashes - 1) == 0x5C, !isTaken(index - backslashes - 1) {
        backslashes += 1
      }
      return backslashes % 2 == 1
    }
    // Which of what could be marks there are, to skip looking for the rest.
    var present: (low: UInt64, high: UInt64) = (0, 0)
    for index in start..<end {
      let character = string.character(at: index)
      if character < 64 {
        present.low |= 1 << UInt64(character)
      }
      else if character < 128 {
        present.high |= 1 << UInt64(character - 64)
      }
    }
    func has(_ character: unichar) -> Bool {
      character < 64 ? present.low & (1 << UInt64(character)) != 0 : present.high & (1 << UInt64(character - 64)) != 0
    }
    var index = has(0x60) ? start : end
    while index < end {
      let run = backticks(at: index)
      guard run > 0, !isEscaped(index) else {
        index += max(run, 1)
        continue
      }
      var close = index + run
      var found: Int?
      while close < end, string.character(at: close) != 0x0A, string.character(at: close) != 0x0D {
        let closing = backticks(at: close)
        if closing == run {
          found = close
          break
        }
        close += max(closing, 1)
      }
      guard let close = found else {
        index += run
        continue
      }
      let span = NSRange(location: index, length: close + run - index)
      storage.addAttributes([.font: self.codeFont, .backgroundColor: layout.colors.codeSpan], range: span)
      storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: index, length: run))
      storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: close, length: run))
      take(span)
      spans.append(span)
      hide(NSRange(location: index, length: run))
      hide(NSRange(location: close, length: run))
      index = close + run
    }

    // A \ before a mark keeps it from being one.
    index = has(0x5C) ? start : end
    while index + 1 < end {
      if !isTaken(index), !isTaken(index + 1), string.character(at: index) == 0x5C, self.escapable.contains(string.character(at: index + 1)) {
        storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: index, length: 1))
        take(NSRange(location: index, length: 2))
        shown?.hidden.insert(index)
        index += 2
        continue
      }
      index += 1
    }

    // Links, the words in the link's color, and the rest faint, with where it goes not styled, and
    // images, which are shown as their previews.
    for match in has(0x5D) && has(0x28) ? self.linkPattern.matches(in: string as String, range: range) : [] {
      var whole = match.range
      var isImage = match.range(at: 1).length > 0
      // An image's ! kept from being one, by a \, and it's a link after it.
      if isImage, isTaken(whole.location) {
        isImage = false
        whole = NSRange(location: whole.location + 1, length: whole.length - 1)
      }
      guard !isTaken(whole.location) else {
        continue
      }
      let words = match.range(at: 2)
      let lineEnd = self.contentEnd(of: string.lineRange(for: NSRange(location: whole.location, length: 0)), in: string)
      storage.addAttribute(.foregroundColor, value: faint, range: whole)
      storage.addAttribute(.foregroundColor, value: linkColor, range: words)
      take(NSRange(location: NSMaxRange(words), length: NSMaxRange(whole) - NSMaxRange(words)))
      take(NSRange(location: whole.location, length: words.location - whole.location))
      guard let shown else {
        continue
      }
      let url = self.destination(string.substring(with: match.range(at: 3)))
      // Shown as its preview alone, where there are any, or else as its words, or where it is,
      // without any, as a link to it.
      if isImage, let url, layout.imagePreviews > 0, url.scheme?.lowercased() == "https" {
        shown.hidden.insert(integersIn: whole.location..<NSMaxRange(whole))
        take(words)
        shown.images.append((lineEnd, url, true))
        continue
      }
      // Its words, as a link to where it goes, without the rest, or as words, if it goes nowhere.
      shown.hidden.insert(integersIn: whole.location..<words.location)
      shown.hidden.insert(integersIn: NSMaxRange(words)..<NSMaxRange(whole))
      if let url {
        if words.length == 0 {
          // An image without words for it, as a link to where it is.
          shown.hidden.remove(integersIn: match.range(at: 3).location..<NSMaxRange(match.range(at: 3)))
          storage.addAttribute(.foregroundColor, value: linkColor, range: match.range(at: 3))
          shown.links.append((match.range(at: 3), url))
        }
        else {
          shown.links.append((words, url))
        }
        if ImagePreview.canPreview(url) || isImage {
          shown.images.append((lineEnd, url, false))
        }
      }
      else {
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: words)
      }
    }
    // Addresses, found a line at a time, as what's found across lines depends on more than the
    // line an address is in.
    lineStart = start
    while lineStart < end {
      let line = string.paragraphRange(for: NSRange(location: lineStart, length: 0))
      lineStart = NSMaxRange(line)
      let lineWords = string.substring(with: line)
      guard lineWords.contains(where: { $0 == "." || $0 == "@" || $0 == ":" }) else {
        continue
      }
      for link in lineWords.detectedLinks() {
        let found = NSRange(link.range, in: lineWords)
        let address = NSRange(location: line.location + found.location, length: found.length)
        guard !isTaken(address.location) else {
          continue
        }
        storage.addAttribute(.foregroundColor, value: linkColor, range: address)
        take(address)
        shown?.links.append((address, link.url))
        shown?.addresses.append(address)
        if ImagePreview.canPreview(link.url) {
          shown?.images.append((self.contentEnd(of: line, in: string), link.url, false))
        }
      }
    }

    func isSpace(_ index: Int) -> Bool {
      guard index >= start, index < end, let scalar = Unicode.Scalar(string.character(at: index)) else {
        return true
      }
      return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
    func isWordCharacter(_ index: Int) -> Bool {
      guard index >= start, index < end, let scalar = Unicode.Scalar(string.character(at: index)) else {
        return false
      }
      return CharacterSet.alphanumerics.contains(scalar)
    }
    func hasMark(_ mark: NSString, at index: Int) -> Bool {
      guard index >= start, index + mark.length <= end else {
        return false
      }
      for offset in 0..<mark.length where isTaken(index + offset) || string.character(at: index + offset) != mark.character(at: offset) {
        return false
      }
      return true
    }

    var traits = [NSFontDescriptor.SymbolicTraits](repeating: [], count: range.length)
    for (markString, style) in self.marks where has((markString as NSString).character(at: 0)) {
      let mark = markString as NSString
      let markLength = mark.length
      let markCharacter = mark.character(at: 0)
      var index = start
      while index < end {
        // Opens: at the start of a word, with something after it that isn't a space or more of it.
        guard hasMark(mark, at: index),
              index == start || string.character(at: index - 1) != markCharacter,
              !isWordCharacter(index - 1),
              !isSpace(index + markLength),
              string.character(at: index + markLength) != markCharacter else {
          index += 1
          continue
        }
        // Closes: on the same line, at the end of a word, with something before it that isn't a space.
        var close = index + markLength + 1
        var found: Int?
        while close + markLength <= end {
          let character = string.character(at: close)
          if character == 0x0A || character == 0x0D {
            break
          }
          if hasMark(mark, at: close), !isSpace(close - 1),
             close + markLength == end || string.character(at: close + markLength) != markCharacter,
             !isWordCharacter(close + markLength) {
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
        let opening = NSRange(location: index, length: markLength)
        let closing = NSRange(location: close, length: markLength)
        storage.addAttribute(.foregroundColor, value: faint, range: opening)
        storage.addAttribute(.foregroundColor, value: faint, range: closing)
        take(opening)
        take(closing)
        hide(opening)
        hide(closing)
        var added: NSFontDescriptor.SymbolicTraits = []
        switch style {
        case .strikethrough:
          storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
        case .underline, .underlineItalic:
          storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
          added = style == .underlineItalic ? .italic : []
        case .bold:
          added = .bold
        case .italic:
          added = .italic
        case .boldItalic:
          added = [.bold, .italic]
        }
        for offset in content.location..<NSMaxRange(content) where !added.isEmpty {
          traits[offset - start].formUnion(added)
        }
        index = close + markLength
      }
    }

    // Bold and italic can go together, so they're worked out a character at a time, and added to
    // the font each character already has, as a heading's, or code's.
    var run = 0
    while run < range.length {
      var next = run + 1
      while next < range.length && traits[next] == traits[run] {
        next += 1
      }
      if !traits[run].isEmpty {
        let added = traits[run]
        let runRange = NSRange(location: start + run, length: next - run)
        storage.enumerateAttribute(.font, in: runRange) { value, part, _ in
          storage.addAttribute(.font, value: self.font(value as? NSFont ?? layout.font, adding: added), range: part)
        }
      }
      run = next
    }
    return spans
  }

  // MARK: Quoting

  /// Some text quoted, as a reply quotes what it's replying to: who wrote it, and each of its lines
  /// after a >, with a line after it to write a reply on.
  static func quote(_ text: String, by author: String?) -> String {
    let lines = text.components(separatedBy: .newlines).map { $0.isEmpty ? ">" : "> \($0)" }
    return (author.map { "\($0) wrote:\n" } ?? "") + lines.joined(separator: "\n") + "\n\n"
  }

  // MARK: Rich Text

  /// Rich text, like what's copied from a web page, a note, or Xcode, as Markdown: what's bold,
  /// italic, underlined, struck through, or in a fixed-width font as code, with its marks, lines of
  /// code as a code block, and its links as links. Nil for text without any of that, which pastes
  /// as it is.
  static func markdown(from text: NSAttributedString) -> String? {
    struct Look: Equatable {
      var bold = false
      var italic = false
      var underline = false
      var code = false
      var strikethrough = false
      var link: URL?

      var isPlain: Bool {
        self == Look()
      }
    }
    typealias Run = (text: String, look: Look)

    // A line at a time, as marks don't go past the end of a line, with runs that look the same
    // together, as rich text often splits them for other reasons.
    var lines: [[Run]] = [[]]
    var styled = false
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
      let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
      var look = Look()
      look.code = traits.contains(.monoSpace)
      look.bold = traits.contains(.bold) && !look.code
      look.italic = traits.contains(.italic) && !look.code
      look.strikethrough = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
      look.link = attributes[.link] as? URL ?? (attributes[.link] as? String).flatMap { URL(string: $0) }
      // Not a link's, which is how links look.
      look.underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0 && look.link == nil && !look.code
      styled = styled || !look.isPlain
      let pieces = text.attributedSubstring(from: range).string
        .replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: CharacterSet(charactersIn: "\n\r\u{2028}\u{2029}"))
      for (index, piece) in pieces.enumerated() {
        if index > 0 {
          lines.append([])
        }
        if piece.isEmpty {
          continue
        }
        if let last = lines[lines.count - 1].last, last.look == look {
          lines[lines.count - 1][lines[lines.count - 1].count - 1].text += piece
        }
        else {
          lines[lines.count - 1].append((piece, look))
        }
      }
    }
    guard styled else {
      return nil
    }

    func isBlank(_ line: [Run]) -> Bool {
      line.allSatisfy { $0.text.allSatisfy(\.isWhitespace) }
    }
    func isCode(_ line: [Run]) -> Bool {
      !isBlank(line) && line.allSatisfy { $0.look.code || $0.text.allSatisfy(\.isWhitespace) }
    }
    /// The most backticks in a row in some code, for marks around it that it can't close early.
    func backticks(in code: String) -> Int {
      var most = 0
      var run = 0
      for character in code {
        run = character == "`" ? run + 1 : 0
        most = max(most, run)
      }
      return most
    }
    // With the spaces at either end outside its marks, where marks work.
    func marked(_ run: Run) -> String {
      let words = run.text.trimmingCharacters(in: .whitespaces)
      guard !words.isEmpty else {
        return run.text
      }
      let leading = run.text.prefix(while: \.isWhitespace)
      let trailing = run.text.reversed().prefix(while: \.isWhitespace)
      var marked = words
      if run.look.code {
        let ticks = String(repeating: "`", count: backticks(in: words) + 1)
        let space = words.hasPrefix("`") || words.hasSuffix("`") ? " " : ""
        marked = ticks + space + words + space + ticks
      }
      else {
        if run.look.strikethrough {
          marked = "~~\(marked)~~"
        }
        if run.look.underline {
          marked = "__\(marked)__"
        }
        if run.look.bold && run.look.italic {
          marked = "***\(marked)***"
        }
        else if run.look.bold {
          marked = "**\(marked)**"
        }
        else if run.look.italic {
          marked = "*\(marked)*"
        }
      }
      // An address that's its own words stays as it is, as it's made a link anyway.
      if let link = run.look.link, words != link.absoluteString, !link.absoluteString.hasSuffix("://" + words) {
        marked = "[\(marked)](\(link.absoluteString))"
      }
      return String(leading) + marked + String(trailing.reversed())
    }

    var markdown: [String] = []
    var index = 0
    while index < lines.count {
      // More than one line of code, with any blank lines between them, as a code block.
      var last = index
      var count = 0
      var next = index
      while next < lines.count, isCode(lines[next]) || (count > 0 && isBlank(lines[next])) {
        if isCode(lines[next]) {
          last = next
          count += 1
        }
        next += 1
      }
      if count > 1 {
        let code = lines[index...last].map { $0.map(\.text).joined() }
        let fence = String(repeating: "`", count: max(3, backticks(in: code.joined(separator: "\n")) + 1))
        markdown += [fence] + code + [fence]
        index = last + 1
        continue
      }
      markdown.append(lines[index].map(marked).joined())
      index += 1
    }
    return markdown.joined(separator: "\n")
  }
}
