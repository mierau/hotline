import AppKit

/// The Markdown the board shows, and posts are written in, styled as the board shows it, with its
/// marks kept, faint: bold, italic and both, with * or _, strikethrough, `code`, code blocks between
/// ``` on lines of their own, colored as chat colors them when they name a language, links, and
/// addresses, which the board makes links, quotes, and lists. A mark opens with something other than
/// a space after it and closes with something other than one before it, and _ only at the start
/// and end of words, as Markdown has it, so snake_case_names stay as they are. Nothing's styled
/// inside code, or where a link goes.
enum PostMarkdown {
  /// The most a post can be, as a field holds no more.
  static let maximumLength = HotlineTransactionField.maximumDataSize

  /// As the board's posts are.
  static var font: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }

  static var attributes: [NSAttributedString.Key: Any] {
    [.font: self.font, .foregroundColor: NSColor.textColor, .paragraphStyle: self.paragraph()]
  }

  private static func paragraph(firstLineHeadIndent: CGFloat = 0, headIndent: CGFloat = 0) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    paragraph.firstLineHeadIndent = firstLineHeadIndent
    paragraph.headIndent = headIndent
    return paragraph
  }

  private static var codeFont: NSFont {
    .monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
  }

  // MARK: Code

  /// Where a line of a code block is in it, for the fragment that draws its part of the block's
  /// background: rounded at the block's top and bottom, and square where its lines meet.
  static let codeLineKey = NSAttributedString.Key("postCodeLine")

  enum CodeLine: Int {
    case first, middle, last, only
  }

  /// How far in from a code block's background its code is.
  static let codePadding: CGFloat = 10

  /// The room between a code block and what's above and below it.
  static let codeBlockSpacing: CGFloat = 12

  /// The kind of code something's in: a code block, or `code` among the words.
  enum CodeContext {
    case block
    case span
  }

  /// A code block in a post. Ranges count UTF-16 code units, as NSString does.
  struct CodeBlock: Equatable {
    /// All of it, from the start of its opening ``` to the end of its closing one.
    var range: NSRange
    /// Its code, the lines between its ```, if there are any.
    var code: NSRange
    /// The language named after the opening ```, like lua in ```lua.
    var language: String?
    /// Whether it has its closing ```, which only one asked for still open doesn't.
    var isClosed: Bool
  }

  /// Where the code is: code blocks, and `code`, with its marks.
  struct CodeRanges {
    var blocks: [CodeBlock] = []
    var spans: [NSRange] = []

    /// The code a selection is in, or for where you're typing, inside, past the opening mark and
    /// not yet past the closing one.
    func context(of selection: NSRange) -> CodeContext? {
      func holds(_ range: NSRange) -> Bool {
        selection.length > 0 ? NSIntersectionRange(range, selection).length > 0 : selection.location > range.location && selection.location < NSMaxRange(range)
      }
      if self.blocks.contains(where: { holds($0.range) }) {
        return .block
      }
      return self.spans.contains(where: holds) ? .span : nil
    }

    /// The code block a selection's in, if it's in one.
    func block(holding selection: NSRange) -> CodeBlock? {
      self.blocks.first { selection.location > $0.range.location && NSMaxRange(selection) < NSMaxRange($0.range) }
    }

    func intersects(_ range: NSRange) -> Bool {
      (self.blocks.map(\.range) + self.spans).contains { NSIntersectionRange($0, range).length > 0 || (range.length == 0 && NSLocationInRange(range.location, $0)) }
    }
  }

  /// A line of a code block, in from its background's edges, and for its first and last lines,
  /// with room to what's above and below the block.
  private static func codeParagraph(_ place: CodeLine) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = self.codePadding
    paragraph.headIndent = self.codePadding
    paragraph.tailIndent = -self.codePadding
    paragraph.lineSpacing = 3
    paragraph.paragraphSpacingBefore = place == .first || place == .only ? self.codeBlockSpacing : 0
    paragraph.paragraphSpacing = place == .last || place == .only ? self.codeBlockSpacing : 0
    // Tabs four spaces wide, as most code is written.
    paragraph.tabStops = []
    paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: self.codeFont]).width
    return paragraph
  }

  /// The code blocks in a post: from a line that starts with ``` and the language it's in, to a
  /// line of just ```, with nothing, or any lines, between them. A ``` without a closing one stays
  /// as it's typed, as in chat, rather than making the rest of the post code, as Markdown would,
  /// and the editor puts in the closing one as the opening one's written. Asked to, it gives back
  /// one still open, at the end, as the editor needs, to do that.
  static func codeBlocks(in text: NSString, includingUnclosed: Bool = false) -> [CodeBlock] {
    var blocks: [CodeBlock] = []
    var open: (start: Int, code: Int, fence: Int, language: String?)?
    var lineStart = 0
    while lineStart < text.length {
      let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
      let end = self.contentEnd(of: line, in: text)
      // Only lines with a ` in them can open or close one.
      if text.range(of: "`", options: .literal, range: NSRange(location: line.location, length: end - line.location)).location != NSNotFound {
        let content = text.substring(with: NSRange(location: line.location, length: end - line.location))
        let indent = content.prefix(while: { $0 == " " }).count
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        let ticks = trimmed.prefix(while: { $0 == "`" }).count
        if let fence = open {
          // Closes with a line of just ```, or more.
          if ticks >= fence.fence, ticks == trimmed.count {
            // Not the line break before the closing ```.
            var codeEnd = line.location
            if codeEnd > fence.code, text.character(at: codeEnd - 1) == 0x0A {
              codeEnd -= 1
            }
            if codeEnd > fence.code, text.character(at: codeEnd - 1) == 0x0D {
              codeEnd -= 1
            }
            blocks.append(CodeBlock(range: NSRange(location: fence.start, length: end - fence.start), code: NSRange(location: fence.code, length: max(0, codeEnd - fence.code)), language: fence.language, isClosed: true))
            open = nil
          }
        }
        // Opens with ``` at the start of a line, then a language, if any, with no ` in it.
        else if ticks >= 3, indent <= 3, !trimmed.dropFirst(ticks).contains("`") {
          let language = trimmed.dropFirst(ticks).split(separator: " ").first.map(String.init)
          open = (line.location, NSMaxRange(line), ticks, language)
        }
      }
      lineStart = NSMaxRange(line)
    }
    if let fence = open, includingUnclosed {
      let code = min(fence.code, text.length)
      blocks.append(CodeBlock(range: NSRange(location: fence.start, length: text.length - fence.start), code: NSRange(location: code, length: text.length - code), language: fence.language, isClosed: false))
    }
    return blocks
  }

  /// Where a line's words end, before its line break.
  private static func contentEnd(of line: NSRange, in text: NSString) -> Int {
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
  static let quoteLineKey = NSAttributedString.Key("postQuoteLine")

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

  /// The quote or list mark a line starts with, after up to three spaces, as Markdown has them: >,
  /// or -, * or + with a space after it, or a number and . or ) with a space after it.
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
    if character == 0x3E {
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

  // MARK: Links

  private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]\n]*)\]\(([^)\s]*)\)"#)
  private static let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

  /// The link a range is in, all of it, and its words.
  static func link(around range: NSRange, in text: NSString) -> (range: NSRange, words: NSRange)? {
    let line = text.lineRange(for: NSRange(location: range.location, length: 0))
    for match in self.linkPattern.matches(in: text as String, range: line)
    where range.length > 0
      ? range.location >= match.range.location && NSMaxRange(range) <= NSMaxRange(match.range)
      : range.location > match.range.location && range.location < NSMaxRange(match.range) {
      return (match.range, match.range(at: 1))
    }
    return nil
  }

  // MARK: Styling

  /// Styles all of the text, and gives back where the code in it is.
  @discardableResult
  static func style(_ storage: NSTextStorage) -> CodeRanges {
    let string = storage.string as NSString
    let all = NSRange(location: 0, length: string.length)
    // Attributes only, as it's done while the text storage is still taking an edit.
    storage.setAttributes(self.attributes, range: all)
    var code = CodeRanges(blocks: self.codeBlocks(in: string))
    for block in code.blocks {
      self.styleBlock(block, in: storage)
    }
    code.spans = self.styleWords(in: storage, range: all, skipping: code.blocks.map(\.range))
    return code
  }

  /// Styles again what an edit changed: the lines it's in, and any code block among them, when
  /// where the code blocks are hasn't changed, and otherwise, all of it. Typing in a long post only
  /// styles the line it's on.
  static func restyle(_ storage: NSTextStorage, edited: NSRange, changeInLength delta: Int, after previous: CodeRanges) -> CodeRanges {
    let string = storage.string as NSString
    let blocks = self.codeBlocks(in: string)
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
      return CodeBlock(range: range, code: code, language: block.language, isClosed: block.isClosed)
    }
    guard unmoved == blocks.map({ Optional($0) }) else {
      return self.style(storage)
    }

    // The lines the edit's in, the one it ends in too, as when it breaks one in two, and all of any
    // code block among them.
    var region = NSUnionRange(string.paragraphRange(for: edited), string.paragraphRange(for: NSRange(location: NSMaxRange(edited), length: 0)))
    for block in blocks where NSIntersectionRange(string.paragraphRange(for: block.range), region).length > 0 {
      region = NSUnionRange(region, string.paragraphRange(for: block.range))
    }
    storage.setAttributes(self.attributes, range: region)
    for block in blocks where NSIntersectionRange(block.range, region).length > 0 {
      self.styleBlock(block, in: storage)
    }
    let spans = previous.spans.compactMap(moved).filter { NSIntersectionRange($0, region).length == 0 }
      + self.styleWords(in: storage, range: region, skipping: blocks.map(\.range))
    return CodeRanges(blocks: blocks, spans: spans.sorted { $0.location < $1.location })
  }

  /// A code block: its code in the code font, colored when it names a language, its ``` and
  /// language faint, and each of its lines with its place in the block, for the background behind it.
  private static func styleBlock(_ block: CodeBlock, in storage: NSTextStorage) {
    let string = storage.string as NSString
    let faint = NSColor.tertiaryLabelColor
    storage.addAttribute(.font, value: self.codeFont, range: block.range)
    storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: block.range.location, length: block.code.location - block.range.location))
    storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: NSMaxRange(block.code), length: NSMaxRange(block.range) - NSMaxRange(block.code)))
    if block.code.length > 0, let language = block.language.flatMap({ ChatCodeHighlighter.language(named: $0) }) {
      ChatCodeHighlighter.highlight(storage, in: block.code, as: language)
    }
    let paragraphs = string.paragraphRange(for: block.range)
    var lines: [NSRange] = []
    var start = paragraphs.location
    while start < NSMaxRange(paragraphs) {
      let line = string.paragraphRange(for: NSRange(location: start, length: 0))
      lines.append(line)
      start = NSMaxRange(line)
    }
    for (index, line) in lines.enumerated() {
      let place: CodeLine = lines.count == 1 ? .only : index == 0 ? .first : index == lines.count - 1 ? .last : .middle
      storage.addAttributes([.paragraphStyle: self.codeParagraph(place), self.codeLineKey: place.rawValue], range: line)
    }
  }

  private enum Style {
    case bold, italic, boldItalic, strikethrough
  }

  /// Longer marks first, so ** isn't read as two *.
  private static let marks: [(mark: String, style: Style)] = [
    ("***", .boldItalic), ("___", .boldItalic), ("**", .bold), ("__", .bold), ("~~", .strikethrough), ("*", .italic), ("_", .italic),
  ]

  /// Styles the words in a range of whole lines, but for what's in the ranges it skips, which are
  /// code blocks, and gives back where `code` among them is.
  private static func styleWords(in storage: NSTextStorage, range: NSRange, skipping skipped: [NSRange]) -> [NSRange] {
    let string = storage.string as NSString
    let start = range.location
    let end = NSMaxRange(range)
    guard range.length > 0 else {
      return []
    }

    let faint = NSColor.tertiaryLabelColor
    let linkColor = NSColor(named: "Link Color") ?? .linkColor
    var taken = [Bool](repeating: false, count: range.length)
    func isTaken(_ index: Int) -> Bool {
      index < start || index >= end || taken[index - start]
    }
    func take(_ taking: NSRange) {
      for index in max(taking.location, start)..<min(NSMaxRange(taking), end) {
        taken[index - start] = true
      }
    }
    for skip in skipped where NSIntersectionRange(skip, range).length > 0 {
      take(skip)
    }

    // Quotes, their words fainter, along a bar, and lists, their items' lines lined up after their
    // marks.
    var lineStart = start
    while lineStart < end {
      let line = string.paragraphRange(for: NSRange(location: lineStart, length: 0))
      if !isTaken(lineStart), let mark = self.lineMark(in: string, line: line) {
        let markRange = NSRange(location: line.location, length: mark.length)
        let markWidth = string.substring(with: markRange).size(withAttributes: [.font: self.font]).width
        switch mark.kind {
        case .quote:
          storage.addAttributes([
            .paragraphStyle: self.paragraph(firstLineHeadIndent: self.quoteIndent, headIndent: self.quoteIndent + markWidth),
            .foregroundColor: NSColor.secondaryLabelColor,
            self.quoteLineKey: true,
          ], range: line)
          storage.addAttribute(.foregroundColor, value: faint, range: markRange)
        case .bullet, .number:
          storage.addAttribute(.paragraphStyle, value: self.paragraph(headIndent: markWidth), range: line)
          storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markRange)
        }
        take(markRange)
      }
      lineStart = NSMaxRange(line)
    }

    // Links, the words in the link's color, and the rest faint, with where it goes not styled.
    for match in self.linkPattern.matches(in: string as String, range: range) where !isTaken(match.range.location) {
      let words = match.range(at: 1)
      storage.addAttribute(.foregroundColor, value: faint, range: match.range)
      storage.addAttribute(.foregroundColor, value: linkColor, range: words)
      take(NSRange(location: NSMaxRange(words), length: NSMaxRange(match.range) - NSMaxRange(words)))
      take(NSRange(location: match.range.location, length: 1))
    }
    // Addresses, as the board makes them links, a line at a time, as what's found across lines
    // depends on more than the line an address is in.
    lineStart = start
    while lineStart < end {
      let line = string.paragraphRange(for: NSRange(location: lineStart, length: 0))
      for match in self.addresses?.matches(in: string as String, range: line) ?? [] where !isTaken(match.range.location) {
        storage.addAttribute(.foregroundColor, value: linkColor, range: match.range)
        take(match.range)
      }
      lineStart = NSMaxRange(line)
    }
    // A \ before a mark keeps it from being one.
    var index = start
    while index + 1 < end {
      if !isTaken(index), string.character(at: index) == 0x5C, "*_~`[]\\".utf16.contains(string.character(at: index + 1)) {
        storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: index, length: 1))
        take(NSRange(location: index, length: 2))
        index += 2
        continue
      }
      index += 1
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

    // `code`, between runs of as many backticks, on the same line, with a run of another length,
    // or one without its match, staying as it's typed, as Markdown has it.
    var spans: [NSRange] = []
    func backticks(at index: Int) -> Int {
      var run = 0
      while index + run < end, string.character(at: index + run) == 0x60, !isTaken(index + run) {
        run += 1
      }
      return run
    }
    index = start
    while index < end {
      let run = backticks(at: index)
      guard run > 0 else {
        index += 1
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
      storage.addAttributes([.font: self.codeFont, .backgroundColor: NSColor.quaternarySystemFill], range: span)
      storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: index, length: run))
      storage.addAttribute(.foregroundColor, value: faint, range: NSRange(location: close, length: run))
      take(span)
      spans.append(span)
      index = close + run
    }

    var traits = [NSFontDescriptor.SymbolicTraits](repeating: [], count: range.length)
    for (markString, style) in self.marks {
      let mark = markString as NSString
      let markLength = mark.length
      let markCharacter = mark.character(at: 0)
      let wordsOnly = markCharacter == 0x5F
      var index = start
      while index < end {
        // Opens: with something after it that isn't a space or more of it.
        guard hasMark(mark, at: index),
              index == start || string.character(at: index - 1) != markCharacter,
              !wordsOnly || !isWordCharacter(index - 1),
              !isSpace(index + markLength),
              string.character(at: index + markLength) != markCharacter else {
          index += 1
          continue
        }
        // Closes: on the same line, with something before it that isn't a space.
        var close = index + markLength + 1
        var found: Int?
        while close + markLength <= end {
          let character = string.character(at: close)
          if character == 0x0A || character == 0x0D {
            break
          }
          if hasMark(mark, at: close), !isSpace(close - 1),
             close + markLength == end || string.character(at: close + markLength) != markCharacter,
             !wordsOnly || !isWordCharacter(close + markLength) {
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
        switch style {
        case .strikethrough:
          storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
        case .bold, .italic, .boldItalic:
          let added: NSFontDescriptor.SymbolicTraits = style == .bold ? .bold : style == .italic ? .italic : [.bold, .italic]
          for offset in content.location..<NSMaxRange(content) {
            traits[offset - start].formUnion(added)
          }
        }
        index = close + markLength
      }
    }

    // Bold and italic can go together, so they're worked out a character at a time.
    var run = 0
    while run < range.length {
      var next = run + 1
      while next < range.length && traits[next] == traits[run] {
        next += 1
      }
      if !traits[run].isEmpty {
        let font = NSFont(descriptor: self.font.fontDescriptor.withSymbolicTraits(traits[run]), size: self.font.pointSize) ?? self.font
        storage.addAttribute(.font, value: font, range: NSRange(location: start + run, length: next - run))
      }
      run = next
    }
    return spans
  }

  // MARK: Rich Text

  /// Rich text, like what's copied from a web page, a note, or Xcode, as Markdown: what's bold,
  /// italic, struck through, or in a fixed-width font as code, with its marks, lines of code as a
  /// code block, and its links as links. Nil for text without any of that, which pastes as it is.
  static func markdown(from text: NSAttributedString) -> String? {
    struct Look: Equatable {
      var bold = false
      var italic = false
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
      // An address that's its own words stays as it is, as the board makes it a link anyway.
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

extension MessageBoardPost {
  /// Whether it has code blocks, which it shows as code, even with the look of a drawing.
  var hasCodeBlocks: Bool {
    self.body.contains("```") && !PostMarkdown.codeBlocks(in: self.body as NSString).isEmpty
  }
}
