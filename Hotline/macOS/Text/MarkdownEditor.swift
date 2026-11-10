import SwiftUI
import LinkPresentation

/// What the Format menu, and a post's formatting buttons, work through: the text view you're
/// writing in, in chat, a private message, or a post, once there is one, and whether what's
/// selected is in code, where formatting doesn't show. The marks go in as typing would, so they
/// can be undone.
@MainActor @Observable
final class MarkdownEditor {
  @ObservationIgnored weak var textView: NSTextView? {
    didSet {
      (self.textView as? MarkdownEditingTextView)?.markdownEditor = self
    }
  }
  /// The kind of code what's selected is in, if it's in any.
  var codeContext: Markdown.CodeContext?
  /// Whether lines can be more than words where it's written, as its layout has it: lists, quotes,
  /// code blocks, and images, which show under their line. Not in a broadcast, which is centered.
  var allowsBlocks = true

  /// The key for a link, as Connect to Server has ⌘K.
  static let linkShortcut = KeyboardShortcut("k", modifiers: [.command, .shift])

  /// Whether a style can go on what's selected: none of them in code, where they don't show, but
  /// for taking code off `code`.
  func allows(_ style: MarkdownStyle) -> Bool {
    switch style {
    case .code:
      self.codeContext != .block && self.codeContext != .drawing
    default:
      self.codeContext == nil
    }
  }

  /// Whether what's selected can be made a link, which it can't in code.
  var allowsLink: Bool {
    self.codeContext == nil
  }

  /// Whether what's selected can be made an image, as a link can, where lines can be more than words.
  var allowsImage: Bool {
    self.allowsBlocks && self.allowsLink
  }

  /// Whether the lines selected can go in a list or a quote, where lines can be more than words, but
  /// not in a code block, or a drawing, where marks are what it's drawn with.
  var allowsLines: Bool {
    self.allowsBlocks && self.codeContext != .block && self.codeContext != .drawing
  }

  // MARK: Formatting

  /// What a page's title is, or nil if it doesn't come in time.
  @ObservationIgnored var pageTitle: (URL) async -> String? = { url in
    let provider = LPMetadataProvider()
    provider.timeout = 8
    return (try? await provider.startFetchingMetadata(for: url))?.title
  }

  /// Links waiting for their pages' titles, by where each one is, kept up with as the text around
  /// it changes, until something in it changes, which lets it go.
  @ObservationIgnored private var awaitingTitles: [UUID: NSRange] = [:]

  /// Keeps the links waiting for titles where they are as the text changes: one after a change
  /// moves with it, and one it's in, or across, is let go, as what's there now is what was written.
  func textChanged(in edited: NSRange, changeInLength delta: Int) {
    let replaced = NSRange(location: edited.location, length: max(0, edited.length - delta))
    for (id, link) in self.awaitingTitles {
      if NSMaxRange(replaced) <= link.location {
        self.awaitingTitles[id] = NSRange(location: link.location + delta, length: link.length)
      }
      else if replaced.location < NSMaxRange(link) {
        self.awaitingTitles[id] = nil
      }
    }
  }

  /// Puts the style's marks around what's selected, with nothing selected, either side of where
  /// you're typing, or takes them away from something that has them already.
  func toggle(_ style: MarkdownStyle) {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    let mark = style.mark
    let markLength = (mark as NSString).length
    // Lines of their own, for code, go in a code block, with where to name its language next, where
    // there can be one.
    if style == .code, self.allowsBlocks, text.substring(with: textView.selectedRange()).contains(where: \.isNewline) {
      let lines = text.lineRange(for: textView.selectedRange())
      var code = text.substring(with: lines)
      let ending = code.hasSuffix("\n") ? "\n" : ""
      code = String(code.dropLast(ending.count))
      self.replace(lines, with: "```\n\(code)\n```" + ending, selecting: NSRange(location: lines.location + 3, length: 0))
      return
    }
    // Not the spaces at either end of what's selected, which the marks would have to go inside of
    // to do anything.
    let range = Self.trimmingSpaces(textView.selectedRange(), in: text)

    // Marked just outside what's selected: the marks come off.
    if style.isMarked(around: range, in: text) {
      let marked = NSRange(location: range.location - markLength, length: range.length + 2 * markLength)
      self.replace(marked, with: text.substring(with: range), selecting: NSRange(location: marked.location, length: range.length))
      return
    }
    // Marked at its own ends, as when the marks were selected too.
    if range.length > 2 * markLength,
       text.substring(with: NSRange(location: range.location, length: markLength)) == mark,
       text.substring(with: NSRange(location: NSMaxRange(range) - markLength, length: markLength)) == mark {
      let inside = text.substring(with: NSRange(location: range.location + markLength, length: range.length - 2 * markLength))
      self.replace(range, with: inside, selecting: NSRange(location: range.location, length: (inside as NSString).length))
      return
    }
    self.replace(range, with: mark + text.substring(with: range) + mark, selecting: NSRange(location: range.location + markLength, length: range.length))
  }

  /// Puts a mark typed over what's selected around it instead, as Markdown editors do: * or _ for
  /// italic, * again for bold, _ again for underline, ~ for strikethrough, and ` for code. What's
  /// selected stays selected, inside the marks, to type another around it.
  func wrap(_ range: NSRange, in typed: String) {
    guard let textView = self.textView else {
      return
    }
    let mark = typed == "~" ? "~~" : typed
    let selected = (textView.string as NSString).substring(with: range)
    self.replace(range, with: mark + selected + mark, selecting: NSRange(location: range.location + (mark as NSString).length, length: range.length))
  }

  /// A link's words, and where it goes, until they're written.
  static let linkWords = "link text"
  static let linkAddress = "https://example.com"

  /// Makes what's selected a link. Words become its words, with an address for now where it goes,
  /// selected to paste or write over. With nothing selected, it has words for now too, selected
  /// first, and Tab goes on to where it goes. An address becomes where it goes, with its page's
  /// title for its words, once that comes, and the site's name until then. In a link already, the
  /// link comes off, and its words stay.
  func link() {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    if let link = Markdown.link(around: selection, in: text) {
      let words = text.substring(with: link.words)
      self.replace(link.range, with: words, selecting: NSRange(location: link.range.location, length: (words as NSString).length))
      return
    }

    let range = Self.trimmingSpaces(selection, in: text)
    let selected = text.substring(with: range)
    if let url = Self.address(selected) {
      self.link(address: selected, url: url, replacing: range)
      return
    }
    // Written without its scheme, as the board would make a link of it, with it.
    if let url = Self.addressWithoutScheme(selected) {
      self.link(address: url.absoluteString, url: url, replacing: range)
      return
    }
    let words = selected.isEmpty ? Self.linkWords : selected
    let wordsRange = NSRange(location: range.location + 1, length: (words as NSString).length)
    let addressRange = NSRange(location: NSMaxRange(wordsRange) + 2, length: (Self.linkAddress as NSString).length)
    self.replace(range, with: "[\(words)](\(Self.linkAddress))", selecting: selected.isEmpty ? wordsRange : addressRange)
  }

  /// Words an address is pasted over become a link to it.
  func link(_ range: NSRange, to address: String) {
    guard let textView = self.textView else {
      return
    }
    let link = "[\((textView.string as NSString).substring(with: range))](\(address))"
    self.replace(range, with: link, selecting: NSRange(location: range.location + (link as NSString).length, length: 0))
  }

  /// What an image is, and where it is, until they're written.
  static let imageWords = "image"
  static let imageAddress = "https://example.com/image.png"

  /// Makes what's selected an image, ![what it is](where it is), which shows as the image itself,
  /// from an https address. An address becomes where it is, with its file's name for what it is,
  /// selected to write over. Words become what it is, and with nothing selected, it's an image for
  /// now, with an address for now, selected, to paste or write over, and Shift-Tab goes back to
  /// what it is. In an image already, it comes off, and its address stays, as a link to it, which
  /// shows a preview of it under its line.
  func image() {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    // An image is a link with a ! before it.
    if let image = Markdown.link(around: selection, in: text), text.character(at: image.range.location) == 0x21 {
      // Between the ]( after its words and the ) at its end.
      let address = text.substring(with: NSRange(location: NSMaxRange(image.words) + 2, length: NSMaxRange(image.range) - NSMaxRange(image.words) - 3))
      self.replace(image.range, with: address, selecting: NSRange(location: image.range.location, length: (address as NSString).length))
      return
    }

    let range = Self.trimmingSpaces(selection, in: text)
    let selected = text.substring(with: range)
    // Written without its scheme, as the board would make a link of it, with it.
    if let url = Self.address(selected) ?? Self.addressWithoutScheme(selected) {
      let address = Self.address(selected) != nil ? selected : url.absoluteString
      let name = url.deletingPathExtension().lastPathComponent
      let words = Self.escaped(name.isEmpty || name == "/" ? Self.imageWords : name)
      self.replace(range, with: "![\(words)](\(address))", selecting: NSRange(location: range.location + 2, length: (words as NSString).length))
      return
    }
    let words = selected.isEmpty ? Self.imageWords : selected
    let addressRange = NSRange(location: range.location + 2 + (words as NSString).length + 2, length: (Self.imageAddress as NSString).length)
    self.replace(range, with: "![\(words)](\(Self.imageAddress))", selecting: addressRange)
  }

  /// Puts the lines selected, or the line you're on, in a list, or a quote, or takes them out of
  /// it, when they're all in it already. A numbered list counts up from 1. Lines in the other
  /// list go in this one instead, and a quote keeps the lists in it, as it can hold them. Lines
  /// with nothing on them stay as they are, unless it's the only one, to start writing on.
  func toggle(_ style: MarkdownLineStyle) {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    // Not the line after a selection that ends with a line break, as lines clicked three times do.
    var lines = selection
    if lines.length > 0, text.character(at: NSMaxRange(lines) - 1) == 0x0A {
      lines.length -= 1
    }
    lines = text.lineRange(for: lines)
    let written = text.substring(with: lines)
    let ending = written.hasSuffix("\n") ? "\n" : ""
    var each = String(written.dropLast(ending.count)).components(separatedBy: "\n").map { $0 as NSString }

    // The quote mark a line starts with, and the list mark after it, if there are any.
    func marks(_ line: NSString) -> (quote: Int, list: Markdown.LineMark?) {
      let all = NSRange(location: 0, length: line.length)
      var quote = 0
      if let mark = Markdown.lineMark(in: line, line: all), mark.kind == .quote {
        quote = mark.length
      }
      let list = Markdown.lineMark(in: line, line: NSRange(location: quote, length: line.length - quote)).flatMap { $0.kind == .quote ? nil : $0 }
      return (quote, list)
    }
    func has(_ line: NSString) -> Bool {
      let marks = marks(line)
      switch style {
      case .quote:
        return marks.quote > 0
      case .bulletedList:
        return marks.list?.kind == .bullet
      case .numberedList:
        if case .number = marks.list?.kind {
          return true
        }
        return false
      }
    }
    let only = each.count == 1
    let changing = each.indices.filter { only || !(each[$0] as String).trimmingCharacters(in: .whitespaces).isEmpty }
    guard !changing.isEmpty else {
      return
    }
    let removing = changing.allSatisfy { has(each[$0]) }

    // How long the first line's marks were, and are, for where you're typing on it.
    var firstMarks = (before: 0, after: 0)
    var number = 1
    for index in changing {
      let line = each[index]
      let (quote, list) = marks(line)
      let changed: String
      let lineMarks: (before: Int, after: Int)
      switch style {
      case .quote:
        if removing {
          changed = line.substring(from: quote)
          lineMarks = (quote, 0)
        }
        else if quote > 0 {
          changed = line as String
          lineMarks = (quote, quote)
        }
        else {
          changed = "> " + (line as String)
          lineMarks = (0, 2)
        }
      case .bulletedList, .numberedList:
        let before = list.map { quote + $0.length } ?? quote
        let mark = removing ? "" : style == .bulletedList ? "- " : "\(number). "
        number += 1
        changed = line.substring(to: quote) + mark + line.substring(from: before)
        lineMarks = (before, quote + (mark as NSString).length)
      }
      if index == 0 {
        firstMarks = lineMarks
      }
      each[index] = changed as NSString
    }
    let replacement = each.map { $0 as String }.joined(separator: "\n") + ending

    if selection.length == 0 {
      // Where you were typing, among the words, or after the marks, if you were in them.
      let offset = selection.location - lines.location
      let moved = offset <= firstMarks.before ? firstMarks.after : offset - firstMarks.before + firstMarks.after
      self.replace(lines, with: replacement, selecting: NSRange(location: lines.location + moved, length: 0))
    }
    else {
      // The lines still selected, but not the line break after them.
      self.replace(lines, with: replacement, selecting: NSRange(location: lines.location, length: (replacement as NSString).length - (ending as NSString).length))
    }
  }

  /// An address as a link, with the site's name for its words, selected to write over, and then
  /// the page's title, when it comes, if nothing in the link has changed by then, wherever it's
  /// moved to, and you're not in its words, about to write there.
  private func link(address: String, url: URL, replacing range: NSRange) {
    let site = Self.escaped(url.host()?.replacing(/^www\./, with: "") ?? address)
    let link = "[\(site)](\(address))"
    let siteLength = (site as NSString).length
    self.replace(range, with: link, selecting: NSRange(location: range.location + 1, length: siteLength))

    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      return
    }
    let id = UUID()
    self.awaitingTitles[id] = NSRange(location: range.location, length: (link as NSString).length)
    let pageTitle = self.pageTitle
    Task { @MainActor [weak self] in
      let fetched = await pageTitle(url)
      guard let self, let link = self.awaitingTitles.removeValue(forKey: id),
            let title = fetched?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
            let textView = self.textView else {
        return
      }
      let words = NSRange(location: link.location + 1, length: siteLength)
      // Still selected as it was put in, it's the title that's selected now, but anywhere else in
      // its words, or at either end of them, you're about to write there, and they stay.
      var selection = textView.selectedRange()
      if selection != words, NSMaxRange(selection) >= words.location, selection.location <= NSMaxRange(words) {
        return
      }
      let escaped = Self.escaped(title)
      let change = (escaped as NSString).length - words.length
      if selection == words {
        selection.length += change
      }
      else if selection.location >= NSMaxRange(words) {
        selection.location += change
      }
      self.replace(words, with: escaped, selecting: selection)
    }
  }

  /// A web or Hotline address, as it's selected or pasted, or nil if it's something else.
  static func address(_ text: String) -> URL? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !text.contains(where: \.isWhitespace),
          let url = URL(string: text), ["http", "https", "hotline"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil else {
      return nil
    }
    return url
  }

  /// An address without its scheme, as it's selected, like apple.com, or a server's, with its port,
  /// all of what's selected, with the scheme the board gives it as it makes a link of it. Not for
  /// what's pasted, where words with a dot, like a file's name, can look like one.
  private static func addressWithoutScheme(_ text: String) -> URL? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !text.contains(where: \.isWhitespace),
          let link = text.detectedLinks().first, link.range == text.startIndex..<text.endIndex,
          ["http", "https", "hotline"].contains(link.url.scheme?.lowercased() ?? "") else {
      return nil
    }
    return link.url
  }

  /// Words for a link, with brackets that would end its words early kept as brackets.
  private static func escaped(_ words: String) -> String {
    words.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
  }

  private func replace(_ range: NSRange, with string: String, selecting selection: NSRange) {
    guard let textView = self.textView, textView.shouldChangeText(in: range, replacementString: string) else {
      return
    }
    textView.textStorage?.replaceCharacters(in: range, with: string)
    textView.didChangeText()
    textView.setSelectedRange(selection)
    textView.window?.makeFirstResponder(textView)
  }

  private static func trimmingSpaces(_ range: NSRange, in text: NSString) -> NSRange {
    var start = range.location, end = NSMaxRange(range)
    while start < end, text.character(at: start) == 0x20 || text.character(at: start) == 0x09 {
      start += 1
    }
    while end > start, text.character(at: end - 1) == 0x20 || text.character(at: end - 1) == 0x09 {
      end -= 1
    }
    return NSRange(location: start, length: end - start)
  }
}

// MARK: - Styled Text

/// What styles Markdown as it's written, in the post's editor and the chat's input: the marks
/// faint, and what they mark as it'll be shown, with code that's words to no one, a mark typed over
/// words going around them, an address pasted over words making them a link, and lists, quotes
/// and code blocks going on from one line to the next. Each place keeps what's written its own
/// way, by overriding `textDidChange(_:)`.
class MarkdownTextCoordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
  let editor: MarkdownEditor
  /// How what's written is laid out, as the board's posts are, or chat's messages, but for its
  /// colors.
  let layout: Markdown.Layout
  /// For code blocks' backgrounds and quotes' bars.
  let fragments = MarkdownFragments.editor()
  /// What's written is styled in, a server's theme's colors, or the system's.
  private var colors = Markdown.Colors()

  init(editor: MarkdownEditor, layout: Markdown.Layout = .board) {
    self.editor = editor
    self.layout = layout
  }

  /// Has a text view's text styled, and its edits handled, here, and the editor work through it.
  @MainActor
  func attach(_ textView: NSTextView) {
    textView.delegate = self
    textView.textStorage?.delegate = self
    // For code blocks' backgrounds and quotes' bars, which the text can't draw on its own.
    textView.textLayoutManager?.delegate = self.fragments
    textView.typingAttributes = self.layout.attributes
    self.editor.textView = textView
    self.editor.allowsBlocks = self.layout.blocks
  }

  /// For what's written to go where it's kept.
  func textDidChange(_ notification: Notification) {
  }

  /// For what's written to go where it's kept once you're done with it, where it isn't kept until
  /// then.
  func textDidEndEditing(_ notification: Notification) {
  }

  func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString string: String?) -> Bool {
    guard let string, range.length > 0 else {
      return true
    }
    let text = textView.string as NSString
    let selection = textView.selectedRange()

    // A word just written in code isn't capitalized for you, should corrections, which are off
    // in code, still get there.
    if self.code.intersects(range), selection.length == 0, NSMaxRange(range) <= selection.location {
      let word = text.substring(with: range)
      if word != string, word.lowercased() == string.lowercased(), word.dropFirst() == string.dropFirst() {
        return false
      }
    }

    // A mark typed over words goes around them, once the typing's done with.
    if range == selection, ["*", "_", "~", "`"].contains(string), self.code.context(of: range) == nil,
       !text.substring(with: range).contains(where: \.isNewline) {
      DispatchQueue.main.async {
        self.editor.wrap(range, in: string)
      }
      return false
    }

    // An address pasted over words, all on one line and not an address or a link themselves,
    // makes them a link to it, as in Slack, once the paste is done with.
    if MarkdownEditor.address(string) != nil {
      let words = text.substring(with: range)
      if MarkdownEditor.address(words) == nil, !words.contains(where: \.isNewline), Markdown.link(around: range, in: text) == nil {
        let address = string.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
          self.editor.link(range, to: address)
        }
        return false
      }
    }
    return true
  }

  // Styled again whenever the text changes: the lines the change is in, or all of it, when the
  // change moves where code blocks are.
  func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
    guard editedMask.contains(.editedCharacters) else {
      return
    }
    self.code = Markdown.restyle(textStorage, edited: editedRange, changeInLength: delta, after: self.code, layout: self.layout, colors: self.colors)
    // The editor's text only changes on the main thread.
    MainActor.assumeIsolated {
      self.editor.textChanged(in: editedRange, changeInLength: delta)
    }
  }

  /// Styles what's written in a server's theme's colors, or the system's, again, when they change.
  func use(_ colors: Markdown.Colors, in textView: NSTextView) {
    guard colors != self.colors else {
      return
    }
    self.colors = colors
    self.fragments.apply(colors)
    if let storage = textView.textStorage {
      self.code = Markdown.style(storage, layout: self.layout, colors: colors)
    }
  }

  // MARK: Code

  /// Where the code is, as of the last time the text was styled.
  private var code = Markdown.CodeRanges()
  /// Whether you're writing in code, and what was on for words before you were.
  private var inCode = false
  private var spellingCorrection = false
  private var textReplacement = false

  func textViewDidChangeSelection(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else {
      return
    }
    let context = self.code.context(of: textView.selectedRange())
    if self.editor.codeContext != context {
      self.editor.codeContext = context
    }

    // In code, what's for words is off: corrections, which capitalize too, replacements, and
    // predictions, and back on, as it was, out of it.
    let inCode = context != nil
    guard inCode != self.inCode else {
      return
    }
    self.inCode = inCode
    if inCode {
      self.spellingCorrection = textView.isAutomaticSpellingCorrectionEnabled
      self.textReplacement = textView.isAutomaticTextReplacementEnabled
      textView.isAutomaticSpellingCorrectionEnabled = false
      textView.isAutomaticTextReplacementEnabled = false
      textView.inlinePredictionType = .no
    }
    else {
      textView.isAutomaticSpellingCorrectionEnabled = self.spellingCorrection
      textView.isAutomaticTextReplacementEnabled = self.textReplacement
      textView.inlinePredictionType = .default
    }
  }

  // Nothing marked misspelled in code, which isn't words.
  func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
    self.code.intersects(affectedCharRange) ? 0 : value
  }

  func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      return self.insertNewline(in: textView)
    case #selector(NSResponder.insertTab(_:)):
      return self.moveInLink(textView, back: false) || self.indent(in: textView, outward: false)
    case #selector(NSResponder.insertBacktab(_:)):
      return self.moveInLink(textView, back: true) || self.indent(in: textView, outward: true)
    default:
      return false
    }
  }

  /// In a link, Tab goes on from its words to where it goes, selected, to paste or write over,
  /// and from there, on past the link, as a form's fields do. Shift-Tab goes back to its words.
  private func moveInLink(_ textView: NSTextView, back: Bool) -> Bool {
    let selection = textView.selectedRange()
    guard self.code.context(of: selection) == nil, let link = Markdown.link(around: selection, in: textView.string as NSString) else {
      return false
    }
    // Between the ]( after its words and the ) at its end.
    let address = NSRange(location: NSMaxRange(link.words) + 2, length: NSMaxRange(link.range) - NSMaxRange(link.words) - 3)
    let inWords = selection.location >= link.words.location && NSMaxRange(selection) <= NSMaxRange(link.words)
    if back {
      guard !inWords else {
        return false
      }
      textView.setSelectedRange(link.words)
    }
    else {
      textView.setSelectedRange(inWords ? address : NSRange(location: NSMaxRange(link.range), length: 0))
    }
    return true
  }

  /// A new line goes on with the list, quote or code block it's in, where lines can be more than
  /// words.
  private func insertNewline(in textView: NSTextView) -> Bool {
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    guard selection.length == 0, self.layout.blocks else {
      return false
    }

    // After an opening ``` and its language, with no closing one, the closing one goes in too,
    // with where you're writing on the line between them, in the block, as far in as the opening
    // one, on a line of its own.
    if let open = Markdown.codeBlocks(in: text, includingUnclosed: true).last, !open.isClosed {
      let line = text.lineRange(for: NSRange(location: open.range.location, length: 0))
      let lineEnd = Self.contentEnd(of: line, in: text)
      if selection.location == lineEnd, open.code.location >= lineEnd {
        let indent = open.opensOwnLine ? text.substring(with: line).prefix(while: { $0 == " " }) : ""
        let fence = String(repeating: "`", count: open.ticks)
        textView.insertText("\n\n" + indent + fence, replacementRange: selection)
        textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        return true
      }
    }

    let line = text.lineRange(for: selection)
    // A new line in a code block starts as far in as the one before it, as in a code editor, and
    // in a drawing, as far in as what's drawn on the one before.
    if self.code.context(of: selection) == .block || self.code.context(of: selection) == .drawing {
      let indent = text.substring(with: line).prefix(while: { $0 == " " || $0 == "\t" })
      guard !indent.isEmpty else {
        return false
      }
      textView.insertText("\n" + indent, replacementRange: selection)
      return true
    }

    // In a list or a quote, a new line goes on with it, or from one with nothing in it, ends it.
    guard self.code.context(of: selection) == nil, let mark = Markdown.lineMark(in: text, line: line), selection.location >= line.location + mark.length else {
      return false
    }
    let lineEnd = Self.contentEnd(of: line, in: text)
    let words = text.substring(with: NSRange(location: line.location + mark.length, length: lineEnd - line.location - mark.length))
    if words.trimmingCharacters(in: .whitespaces).isEmpty {
      textView.insertText("", replacementRange: NSRange(location: line.location, length: lineEnd - line.location))
      return true
    }
    let indent = text.substring(with: line).prefix(while: { $0 == " " })
    textView.insertText("\n" + indent + mark.next + " ", replacementRange: selection)
    return true
  }

  /// In a code block, Tab puts the lines selected, or where you're typing, in by two spaces, and
  /// Shift-Tab takes them out by as much, or a tab.
  private func indent(in textView: NSTextView, outward: Bool) -> Bool {
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    // In a block's code, selected up to the line break after its last line, too, as when its
    // lines are clicked three times.
    guard let block = self.code.blocks.first(where: { selection.location >= $0.code.location && NSMaxRange(selection) <= NSMaxRange($0.code) + (selection.length > 0 ? 1 : 0) }) else {
      return false
    }
    if !outward && selection.length == 0 {
      textView.insertText("  ", replacementRange: selection)
      return true
    }
    let lines = NSIntersectionRange(text.lineRange(for: selection), NSRange(location: block.code.location, length: block.code.length + 1))
    var removed = 0
    let changed = text.substring(with: lines).components(separatedBy: "\n").enumerated().map { index, line -> String in
      // Not empty lines, or the nothing after the last line break.
      guard !(line.isEmpty && index > 0) else {
        return line
      }
      if !outward {
        return "  " + line
      }
      let out = line.hasPrefix("\t") ? 1 : min(2, line.prefix(while: { $0 == " " }).count)
      if index == 0 {
        removed = out
      }
      return String(line.dropFirst(out))
    }.joined(separator: "\n")
    textView.insertText(changed, replacementRange: lines)
    if selection.length == 0 {
      // Where you're typing, with its line.
      textView.setSelectedRange(NSRange(location: max(lines.location, selection.location - removed), length: 0))
    }
    else {
      // The lines still selected, to go in or out again, but not the line break after them.
      let length = (changed as NSString).length - (changed.hasSuffix("\n") ? 1 : 0)
      textView.setSelectedRange(NSRange(location: lines.location, length: length))
    }
    return true
  }

  private static func contentEnd(of line: NSRange, in text: NSString) -> Int {
    var end = NSMaxRange(line)
    while end > line.location, text.character(at: end - 1) == 0x0A || text.character(at: end - 1) == 0x0D {
      end -= 1
    }
    return end
  }
}

// MARK: - Focus

/// The editor for the text view with the keys, in the window with them, which the Format menu
/// works through, or nil, while they're anywhere else. Kept by the text views themselves, as they
/// take the keys and give them up, and the windows, as they do, since SwiftUI doesn't know a text
/// view of its own has them, until it's clicked, and a focused value in a sheet doesn't reach the
/// menu.
@MainActor @Observable
final class MarkdownEditorFocus {
  static let shared = MarkdownEditorFocus()

  private(set) var editor: MarkdownEditor?
  @ObservationIgnored private var observers: [NSObjectProtocol] = []

  private init() {
    self.observers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
        MainActor.assumeIsolated {
          MarkdownEditorFocus.shared.changed()
        }
      }
    }
  }

  /// Looks again, once the keys have gone where they're going, as a text view hears it's giving
  /// them up before the window says who has them now, and a window before another has them.
  func changed() {
    DispatchQueue.main.async {
      let editor = (NSApp.keyWindow?.firstResponder as? MarkdownEditingTextView)?.markdownEditor
      if self.editor !== editor {
        self.editor = editor
      }
    }
  }
}

/// A text view Markdown's written in: the Format menu works through it, while it has the keys, with
/// its editor, which tells the menu as it takes them and gives them up, and rich text pasted in,
/// like what's copied from a web page or a note, goes in as Markdown, so what was bold or a link
/// still is, but as it is in code, and as plain text with Paste and Match Style.
class MarkdownEditingTextView: NSTextView {
  weak var markdownEditor: MarkdownEditor? {
    didSet {
      MarkdownEditorFocus.shared.changed()
    }
  }

  override func becomeFirstResponder() -> Bool {
    defer { MarkdownEditorFocus.shared.changed() }
    return super.becomeFirstResponder()
  }

  override func resignFirstResponder() -> Bool {
    defer { MarkdownEditorFocus.shared.changed() }
    return super.resignFirstResponder()
  }

  // Taken out of its window, as chat is for the files, which doesn't say it's given up the keys.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    MarkdownEditorFocus.shared.changed()
  }

  // MARK: Pasting

  override func paste(_ sender: Any?) {
    if !self.pasteMarkdown(from: .general) {
      super.paste(sender)
    }
  }

  /// Pastes rich text from a pasteboard as Markdown, unless it's going in code, with a code block
  /// it starts or ends with on lines of its own, as code blocks have to be. False for anything
  /// else, to paste as it is.
  func pasteMarkdown(from pasteboard: NSPasteboard) -> Bool {
    let rich = pasteboard.types?.contains(where: { [.rtf, .rtfd, .html].contains($0) }) ?? false
    guard rich, self.markdownEditor?.codeContext == nil,
          let pasted = pasteboard.readObjects(forClasses: [NSAttributedString.self])?.first as? NSAttributedString,
          var markdown = Markdown.markdown(from: pasted) else {
      return false
    }
    let text = self.string as NSString
    let range = self.selectedRange()
    func isLineBreak(_ index: Int) -> Bool {
      text.character(at: index) == 0x0A || text.character(at: index) == 0x0D
    }
    if markdown.hasPrefix("```"), range.location > 0, !isLineBreak(range.location - 1) {
      markdown = "\n" + markdown
    }
    if markdown.hasSuffix("```"), NSMaxRange(range) < text.length, !isLineBreak(NSMaxRange(range)) {
      markdown += "\n"
    }
    self.insertText(markdown, replacementRange: range)
    return true
  }
}

/// A list, or a quote, which Markdown marks whole lines for, and how the Format menu shows it.
enum MarkdownLineStyle: CaseIterable {
  case bulletedList
  case numberedList
  case quote

  var title: String {
    switch self {
    case .bulletedList: "Bulleted List"
    case .numberedList: "Numbered List"
    case .quote: "Quote"
    }
  }

  var systemImage: String {
    switch self {
    case .bulletedList: "list.bullet"
    case .numberedList: "list.number"
    case .quote: "text.quote"
    }
  }

  /// As Slack and Google Docs have them.
  var shortcut: KeyboardShortcut {
    switch self {
    case .bulletedList: KeyboardShortcut("8", modifiers: [.command, .shift])
    case .numberedList: KeyboardShortcut("7", modifiers: [.command, .shift])
    case .quote: KeyboardShortcut("9", modifiers: [.command, .shift])
    }
  }
}

/// A style Markdown shows, the marks for it, and how the Format menu, and a post's formatting
/// buttons, show it.
enum MarkdownStyle: CaseIterable {
  case bold
  case italic
  case underline
  case strikethrough
  case code

  var title: String {
    switch self {
    case .bold: "Bold"
    case .italic: "Italic"
    case .underline: "Underline"
    case .strikethrough: "Strikethrough"
    case .code: "Code"
    }
  }

  var systemImage: String {
    switch self {
    case .bold: "bold"
    case .italic: "italic"
    case .underline: "underline"
    case .strikethrough: "strikethrough"
    case .code: "chevron.left.forwardslash.chevron.right"
    }
  }

  var shortcut: KeyboardShortcut {
    switch self {
    case .bold: KeyboardShortcut("b")
    case .italic: KeyboardShortcut("i")
    case .underline: KeyboardShortcut("u")
    case .strikethrough: KeyboardShortcut("x", modifiers: [.command, .shift])
    case .code: KeyboardShortcut("e")
    }
  }

  var mark: String {
    switch self {
    case .bold: "**"
    case .italic: "*"
    case .underline: "__"
    case .strikethrough: "~~"
    case .code: "`"
    }
  }

  /// Whether the marks are right outside a range: as many of the mark's character as the style
  /// takes on both sides, so an italic's * isn't one of a bold's **, unless it's both, as ***.
  func isMarked(around range: NSRange, in text: NSString) -> Bool {
    let character = (self.mark as NSString).character(at: 0)
    func run(from index: Int, step: Int) -> Int {
      var count = 0
      var index = index
      while index >= 0, index < text.length, text.character(at: index) == character {
        count += 1
        index += step
      }
      return count
    }
    let before = run(from: range.location - 1, step: -1)
    let after = run(from: NSMaxRange(range), step: 1)
    switch self {
    case .italic:
      return (before == 1 || before == 3) && (after == 1 || after == 3)
    case .bold, .underline, .strikethrough:
      return before >= 2 && after >= 2
    case .code:
      return before >= 1 && after >= 1
    }
  }
}
