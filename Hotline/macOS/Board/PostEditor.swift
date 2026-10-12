import SwiftUI
import LinkPresentation

// MARK: - Controller

/// What the formatting buttons work through: the post's text view, once there is one, and whether
/// what's selected is in code, where formatting doesn't show. The marks go in as typing would, so
/// they can be undone.
@MainActor @Observable
final class PostEditorController {
  @ObservationIgnored weak var textView: NSTextView?
  /// The kind of code what's selected is in, if it's in any.
  var codeContext: Markdown.CodeContext?

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
  func toggle(_ style: PostStyle) {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    let mark = style.mark
    let markLength = (mark as NSString).length
    // Lines of their own, for code, go in a code block, with where to name its language next.
    if style == .code, text.substring(with: textView.selectedRange()).contains(where: \.isNewline) {
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

/// A style the board shows, and the Markdown marks for it.
enum PostStyle {
  case bold
  case italic
  case underline
  case strikethrough
  case code

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

// MARK: - Editor

/// The post's text, styled as the board will show it as it's written.
struct PostEditor: NSViewRepresentable {
  /// Where the text starts in the card, which the card's top and its placeholder line up with.
  static let inset = NSSize(width: 16, height: 14)

  @Environment(\.serverTheme) private var theme

  @Binding var text: String
  let controller: PostEditorController
  /// Room past the last line, to scroll it up past what's over the bottom of the editor.
  var bottomInset: CGFloat = 0
  /// Whether you start writing here, once it's shown, or somewhere else, as in a title.
  var startsHere = true

  func makeCoordinator() -> Coordinator {
    Coordinator(text: self.$text, controller: self.controller)
  }

  func makeNSView(context: Context) -> NSScrollView {
    // The system's, for its scroll view and text container, with a text view of our own in it, for
    // what it pastes.
    let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
    let factory = scrollView.documentView as! NSTextView
    let textView = PostTextView(frame: factory.frame, textContainer: factory.textContainer)
    textView.autoresizingMask = factory.autoresizingMask
    textView.isVerticallyResizable = factory.isVerticallyResizable
    textView.isHorizontallyResizable = factory.isHorizontallyResizable
    textView.minSize = factory.minSize
    textView.maxSize = factory.maxSize
    scrollView.documentView = textView

    textView.delegate = context.coordinator
    textView.textStorage?.delegate = context.coordinator
    // For code blocks' backgrounds and quotes' bars, which the text can't draw on its own.
    textView.textLayoutManager?.delegate = context.coordinator.fragments
    textView.isInCode = { [weak coordinator = context.coordinator] in
      coordinator?.controller.codeContext != nil
    }
    textView.isRichText = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.usesFindBar = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    // Spelling corrected or not as the system's set to, but not in code.
    textView.isContinuousSpellCheckingEnabled = true
    textView.textContainerInset = Self.inset
    // From the inset, as the card's top and the placeholder are.
    textView.textContainer?.lineFragmentPadding = 0
    // For pictures dropped on it, as well as text.
    textView.updateDragTypeRegistration()
    textView.font = Markdown.font
    textView.typingAttributes = Markdown.attributes
    textView.string = self.text
    textView.applyServerTheme(self.theme)

    scrollView.drawsBackground = false
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: self.bottomInset, right: 0)

    self.controller.textView = textView
    // Ready to write in, once it's in the sheet, at the end of what's written.
    let startsHere = self.startsHere
    DispatchQueue.main.async {
      if startsHere {
        textView.window?.makeFirstResponder(textView)
      }
      textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let textView = scrollView.documentView as! NSTextView
    context.coordinator.text = self.$text
    if textView.string != self.text {
      textView.string = self.text
    }
    textView.applyServerTheme(self.theme)
    context.coordinator.use(Markdown.Colors(theme: self.theme), in: textView)
    self.controller.textView = textView
  }

  final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    var text: Binding<String>
    let controller: PostEditorController
    /// For code blocks' backgrounds and quotes' bars.
    let fragments = MarkdownFragments.editor()
    /// What's written is styled in, a server's theme's colors, or the system's.
    private var colors = Markdown.Colors()

    init(text: Binding<String>, controller: PostEditorController) {
      self.text = text
      self.controller = controller
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else {
        return
      }
      self.text.wrappedValue = textView.string
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
          self.controller.wrap(range, in: string)
        }
        return false
      }

      // An address pasted over words, all on one line and not an address or a link themselves,
      // makes them a link to it, as in Slack, once the paste is done with.
      if PostEditorController.address(string) != nil {
        let words = text.substring(with: range)
        if PostEditorController.address(words) == nil, !words.contains(where: \.isNewline), Markdown.link(around: range, in: text) == nil {
          let address = string.trimmingCharacters(in: .whitespacesAndNewlines)
          DispatchQueue.main.async {
            self.controller.link(range, to: address)
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
      self.code = Markdown.restyle(textStorage, edited: editedRange, changeInLength: delta, after: self.code, colors: self.colors)
      // The editor's text only changes on the main thread.
      MainActor.assumeIsolated {
        self.controller.textChanged(in: editedRange, changeInLength: delta)
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
        self.code = Markdown.style(storage, colors: colors)
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
      if self.controller.codeContext != context {
        self.controller.codeContext = context
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

    private func insertNewline(in textView: NSTextView) -> Bool {
      let text = textView.string as NSString
      let selection = textView.selectedRange()
      guard selection.length == 0 else {
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
}

/// The post's text view, which pastes rich text, like what's copied from a web page or a note, as
/// Markdown, so what was bold or a link still is, but as it is in code, and as plain text with
/// Paste and Match Style. A picture dropped or pasted in goes in as a drawing of it.
final class PostTextView: NSTextView {
  /// Whether where you're writing is in code.
  var isInCode: () -> Bool = { false }

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
    guard rich, !self.isInCode(),
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

  // MARK: Pictures

  /// Picture files, and pictures, as well as text.
  private static let pictureTypes: [NSPasteboard.PasteboardType] = [.fileURL, .tiff, .png]

  override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
    let types = super.readablePasteboardTypes
    return types + Self.pictureTypes.filter { !types.contains($0) }
  }

  override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
    let types = super.acceptableDragTypes
    return types + Self.pictureTypes.filter { !types.contains($0) }
  }

  override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
    PostPicture.hasPicture(dragInfo.draggingPasteboard) ? .copy : super.dragOperation(for: dragInfo, type: type)
  }

  // Where it's dropped, or what's selected, as for a paste.
  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
    guard PostPicture.hasPicture(pboard) else {
      return super.readSelection(from: pboard, type: type)
    }
    guard let picture = PostPicture.picture(on: pboard) else {
      return false
    }
    self.insertDrawing(of: picture)
    return true
  }

  /// A picture's drawing, for the background it's written on, on lines of its own, as a drawing
  /// has to be, with a line break before it, and after it, where it would share a line with words.
  /// It's selected after, to take out again with Delete, as well as Undo.
  private func insertDrawing(of picture: CGImage) {
    let drawing = PostPicture.drawing(of: picture, onDark: self.effectiveAppearance.isDark)
    guard !drawing.isEmpty else {
      return
    }
    let text = self.string as NSString
    let range = self.selectedRange()
    func isLineBreak(_ index: Int) -> Bool {
      text.character(at: index) == 0x0A || text.character(at: index) == 0x0D
    }
    let before = range.location > 0 && !isLineBreak(range.location - 1) ? "\n" : ""
    let after = NSMaxRange(range) < text.length && !isLineBreak(NSMaxRange(range)) ? "\n" : ""
    self.insertText(before + drawing + after, replacementRange: range)
    self.setSelectedRange(NSRange(location: range.location + (before as NSString).length, length: (drawing as NSString).length))
  }
}

// MARK: - Sheet

/// How big the post is shown, kept where keeping it doesn't draw it again as it's resized, and how
/// much more than it was asked to be, as SwiftUI shows a sheet, so it's asked for as big as it's to
/// be next time, and doesn't grow each time.
final class ShownSize {
  var size: CGSize = .zero
  var extra: CGSize?
}

/// Lets the sheet it's in be resized, which a sheet isn't on its own, no smaller than the post needs
/// room for, and keeps how big it's made, for the next time it opens.
struct ResizableSheet: NSViewRepresentable {
  let smallest: CGSize
  /// How big it was asked to be, as it opened.
  let opening: CGSize
  let shown: ShownSize
  /// Keeps how big it's been made.
  let keep: (CGSize) -> Void

  func makeNSView(context: Context) -> SheetView {
    SheetView(smallest: self.smallest, opening: self.opening, shown: self.shown, keep: self.keep)
  }

  func updateNSView(_ view: SheetView, context: Context) {
  }

  final class SheetView: NSView {
    private let smallest: CGSize
    private let opening: CGSize
    private let shown: ShownSize
    private let keep: (CGSize) -> Void
    private var watching: [NSObjectProtocol] = []

    init(smallest: CGSize, opening: CGSize, shown: ShownSize, keep: @escaping (CGSize) -> Void) {
      self.smallest = smallest
      self.opening = opening
      self.shown = shown
      self.keep = keep
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      self.watching.forEach(NotificationCenter.default.removeObserver)
      self.watching = []
      guard let window = self.window else {
        return
      }
      window.styleMask.insert(.resizable)
      let shown = self.shown, smallest = self.smallest, opening = self.opening, keep = self.keep
      // As small as the post, and what's around it, as SwiftUI doesn't keep a sheet's smallest size
      // until it's being resized.
      self.watching.append(NotificationCenter.default.addObserver(forName: NSWindow.willStartLiveResizeNotification, object: window, queue: .main) { [weak window] _ in
        MainActor.assumeIsolated {
          guard let window, let content = window.contentView?.frame.size, shown.size != .zero else {
            return
          }
          window.contentMinSize = CGSize(width: smallest.width + content.width - shown.size.width, height: smallest.height + content.height - shown.size.height)
          // Still as big as it opened, the first time.
          if shown.extra == nil {
            shown.extra = CGSize(width: shown.size.width - opening.width, height: shown.size.height - opening.height)
          }
        }
      })
      self.watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
          if shown.size != .zero {
            let extra = shown.extra ?? .zero
            keep(CGSize(width: shown.size.width - extra.width, height: shown.size.height - extra.height))
          }
        }
      })
    }
  }
}

// MARK: - Formatting

/// The formatting posts can have, a click or a key away, in glass over the bottom of the post.
struct PostFormattingBar: View {
  /// How tall it is: its buttons, and the glass around them.
  static let height: CGFloat = PostFormatButton.height + 2 * Self.padding
  private static let padding: CGFloat = 3

  let editor: PostEditorController

  var body: some View {
    // None of it shows in code, so it's off there, but for taking code off `code`.
    let code = self.editor.codeContext
    HStack(spacing: 0) {
      PostFormatButton("Bold", systemImage: "bold", key: "b") {
        self.editor.toggle(.bold)
      }
      .disabled(code != nil)
      PostFormatButton("Italic", systemImage: "italic", key: "i") {
        self.editor.toggle(.italic)
      }
      .disabled(code != nil)
      PostFormatButton("Underline", systemImage: "underline", key: "u") {
        self.editor.toggle(.underline)
      }
      .disabled(code != nil)
      PostFormatButton("Strikethrough", systemImage: "strikethrough", key: "x", modifiers: [.command, .shift]) {
        self.editor.toggle(.strikethrough)
      }
      .disabled(code != nil)
      PostFormatButton("Code", systemImage: "chevron.left.forwardslash.chevron.right", key: "e") {
        self.editor.toggle(.code)
      }
      .disabled(code == .block || code == .drawing)
      PostFormatButton("Link", systemImage: "link", key: "k") {
        self.editor.link()
      }
      .disabled(code != nil)
    }
    .padding(Self.padding)
    .modifier(PostFormattingBackground())
  }
}

/// Glass, from macOS 26, or before it, a fill.
private struct PostFormattingBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.glassEffect(.regular, in: .capsule)
    }
    else {
      content.background(.fill.quaternary, in: .capsule)
    }
  }
}

/// A formatting button: its symbol, a light fill behind it while the pointer's over it, and its
/// name and key as its help.
struct PostFormatButton: View {
  static let height: CGFloat = 26

  let title: String
  let systemImage: String
  let key: KeyEquivalent
  let modifiers: EventModifiers
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var hovered: Bool = false

  init(_ title: String, systemImage: String, key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.key = key
    self.modifiers = modifiers
    self.action = action
  }

  var body: some View {
    Button(action: self.action) {
      Image(systemName: self.systemImage)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 32, height: Self.height)
        // In the text's color, as any button that's on, and faint when it's off.
        .foregroundStyle(self.isEnabled ? .primary : .tertiary)
        .background(.fill.tertiary.opacity(self.hovered && self.isEnabled ? 1 : 0), in: .capsule)
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .keyboardShortcut(self.key, modifiers: self.modifiers)
    .help("\(self.title) (\(self.shortcut))")
    .accessibilityLabel(self.title)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        self.hovered = hovering
      }
    }
  }

  /// The key, as menus show it.
  private var shortcut: String {
    (self.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + String(self.key.character).uppercased()
  }
}
