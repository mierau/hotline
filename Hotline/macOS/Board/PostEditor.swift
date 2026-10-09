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
  var codeContext: PostMarkdown.CodeContext?

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
  /// italic, and again for bold, ~ for strikethrough, and ` for code. What's selected stays
  /// selected, inside the marks, to type another around it.
  func wrap(_ range: NSRange, in typed: String) {
    guard let textView = self.textView else {
      return
    }
    let mark = typed == "~" ? "~~" : typed
    let selected = (textView.string as NSString).substring(with: range)
    self.replace(range, with: mark + selected + mark, selecting: NSRange(location: range.location + (mark as NSString).length, length: range.length))
  }

  /// Makes what's selected a link. Words become its words, with where it goes to write next. An
  /// address becomes where it goes, with its page's title for its words, once that comes, and the
  /// site's name until then. In a link already, the link comes off, and its words stay.
  func link() {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    if let link = PostMarkdown.link(around: selection, in: text) {
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
    let link = "[\(selected)]()"
    // The words first, if there aren't any, and then where it goes.
    let caret = selected.isEmpty ? range.location + 1 : range.location + (link as NSString).length - 1
    self.replace(range, with: link, selecting: NSRange(location: caret, length: 0))
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
  /// the page's title, if it comes before they're written over.
  private func link(address: String, url: URL, replacing range: NSRange) {
    let site = Self.escaped(url.host()?.replacing(/^www\./, with: "") ?? address)
    let link = "[\(site)](\(address))"
    self.replace(range, with: link, selecting: NSRange(location: range.location + 1, length: (site as NSString).length))

    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      return
    }
    Task { @MainActor [weak self] in
      let provider = LPMetadataProvider()
      provider.timeout = 8
      guard let fetched = (try? await provider.startFetchingMetadata(for: url))?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !fetched.isEmpty,
            let self, let textView = self.textView else {
        return
      }
      // Where it is now, if it's still as it was put in.
      let found = (textView.string as NSString).range(of: link)
      guard found.location != NSNotFound else {
        return
      }
      let words = NSRange(location: found.location + 1, length: (site as NSString).length)
      let title = Self.escaped(fetched)
      let change = (title as NSString).length - words.length
      // Still selected, it's the title that is now, and otherwise, what's selected stays put.
      var selection = textView.selectedRange()
      if selection == words {
        selection.length += change
      }
      else if selection.location >= NSMaxRange(words) {
        selection.location += change
      }
      self.replace(words, with: title, selecting: selection)
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
  case strikethrough
  case code

  var mark: String {
    switch self {
    case .bold: "**"
    case .italic: "*"
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
    case .bold, .strikethrough:
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
    textView.textLayoutManager?.delegate = context.coordinator
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
    textView.font = PostMarkdown.font
    textView.typingAttributes = PostMarkdown.attributes
    textView.string = self.text
    textView.applyServerTheme(self.theme)

    scrollView.drawsBackground = false
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: self.bottomInset, right: 0)

    self.controller.textView = textView
    // Ready to write in, once it's in the sheet.
    DispatchQueue.main.async {
      textView.window?.makeFirstResponder(textView)
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
    self.controller.textView = textView
  }

  final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSTextLayoutManagerDelegate {
    var text: Binding<String>
    let controller: PostEditorController

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
        if PostEditorController.address(words) == nil, !words.contains(where: \.isNewline), PostMarkdown.link(around: range, in: text) == nil {
          let address = string.trimmingCharacters(in: .whitespacesAndNewlines)
          DispatchQueue.main.async {
            self.controller.link(range, to: address)
          }
          return false
        }
      }
      return true
    }

    // A code block's lines, with its background behind them, and a quote's, with its bar.
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
      guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
      }
      let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
      if let line = (attributes[PostMarkdown.codeLineKey] as? Int).flatMap(PostMarkdown.CodeLine.init) {
        return PostCodeLineFragment(textElement: textElement, range: textElement.elementRange, line: line)
      }
      if attributes[PostMarkdown.quoteLineKey] != nil {
        return PostQuoteLineFragment(textElement: textElement, range: textElement.elementRange)
      }
      return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }

    // Styled again whenever the text changes: the lines the change is in, or all of it, when the
    // change moves where code blocks are.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
      guard editedMask.contains(.editedCharacters) else {
        return
      }
      self.code = PostMarkdown.restyle(textStorage, edited: editedRange, changeInLength: delta, after: self.code)
    }

    // MARK: Code

    /// Where the code is, as of the last time the text was styled.
    private var code = PostMarkdown.CodeRanges()
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
        return self.indent(in: textView, outward: false)
      case #selector(NSResponder.insertBacktab(_:)):
        return self.indent(in: textView, outward: true)
      default:
        return false
      }
    }

    private func insertNewline(in textView: NSTextView) -> Bool {
      let text = textView.string as NSString
      let selection = textView.selectedRange()
      guard selection.length == 0 else {
        return false
      }

      // After an opening ``` and its language, with no closing one, the closing one goes in too,
      // with where you're writing on the line between them, in the block.
      if let open = PostMarkdown.codeBlocks(in: text, includingUnclosed: true).last, !open.isClosed {
        let line = text.lineRange(for: NSRange(location: open.range.location, length: 0))
        let lineEnd = Self.contentEnd(of: line, in: text)
        if selection.location == lineEnd {
          let opening = text.substring(with: NSRange(location: line.location, length: lineEnd - line.location))
          let indent = opening.prefix(while: { $0 == " " })
          let fence = opening.dropFirst(indent.count).prefix(while: { $0 == "`" })
          textView.insertText("\n\n" + indent + fence, replacementRange: selection)
          textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
          return true
        }
      }

      let line = text.lineRange(for: selection)
      // A new line in a code block starts as far in as the one before it, as in a code editor.
      if self.code.context(of: selection) == .block {
        let indent = text.substring(with: line).prefix(while: { $0 == " " || $0 == "\t" })
        guard !indent.isEmpty else {
          return false
        }
        textView.insertText("\n" + indent, replacementRange: selection)
        return true
      }

      // In a list or a quote, a new line goes on with it, or from one with nothing in it, ends it.
      guard self.code.context(of: selection) == nil, let mark = PostMarkdown.lineMark(in: text, line: line), selection.location >= line.location + mark.length else {
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
/// Paste and Match Style.
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
          var markdown = PostMarkdown.markdown(from: pasted) else {
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

// MARK: - Fragments

/// A line of a code block, with its part of the block's background behind it, rounded at the top
/// of the block's first line and the bottom of its last, and square where its lines meet, so they
/// make one block, in the color chat's code blocks have.
final class PostCodeLineFragment: NSTextLayoutFragment {
  private let line: PostMarkdown.CodeLine

  /// How far past its first and last lines the block goes, for room above and below its code.
  private static let overhang: CGFloat = 5
  private static let cornerRadius: CGFloat = 6

  init(textElement: NSTextElement, range: NSTextRange?, line: PostMarkdown.CodeLine) {
    self.line = line
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var isTop: Bool {
    self.line == .first || self.line == .only
  }

  private var isBottom: Bool {
    self.line == .last || self.line == .only
  }

  /// Across the whole width of the text, from the top of the line to the top of the next, but for
  /// the block's first line, from the top of its text, as the room above the block isn't the
  /// block's, and for its last, to the bottom of its text, as the room below isn't either, and nor
  /// is a new line after it at the end of the post, which its fragment has too.
  private var backgroundBounds: CGRect {
    let width = self.textLayoutManager?.textContainer?.size.width ?? self.layoutFragmentFrame.width
    var top: CGFloat = 0
    var bottom = self.layoutFragmentFrame.height
    if self.isTop, let first = self.textLineFragments.first {
      top = first.typographicBounds.minY - Self.overhang
    }
    if self.isBottom, let last = self.textLineFragments.last(where: { $0.characterRange.length > 0 }) {
      bottom = last.typographicBounds.maxY + Self.overhang
    }
    return CGRect(x: -self.layoutFragmentFrame.minX, y: top, width: width, height: bottom - top)
  }

  override var renderingSurfaceBounds: CGRect {
    super.renderingSurfaceBounds.union(self.backgroundBounds)
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    let rect = self.backgroundBounds.offsetBy(dx: point.x, dy: point.y)
    let top = self.isTop ? Self.cornerRadius : 0
    let bottom = self.isBottom ? Self.cornerRadius : 0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + top, y: rect.minY), radius: top)
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top), radius: top)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
    path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
    path.closeSubpath()

    context.saveGState()
    context.addPath(path)
    context.setFillColor(ChatMessageRenderer.codeBlockBackground.cgColor)
    context.fillPath()
    context.restoreGState()
    super.draw(at: point, in: context)
  }
}

/// A line of a quote, with the bar along a quote's lines beside it, from the top of the line to the
/// top of the next, so a quote's lines make one bar, as the board shows them.
final class PostQuoteLineFragment: NSTextLayoutFragment {
  private static let barWidth: CGFloat = 3

  /// Not beside a new line after the quote at the end of the post, which the quote's last line's
  /// fragment has too, but which isn't the quote's.
  private var barBounds: CGRect {
    var height = self.layoutFragmentFrame.height
    if self.textLineFragments.count > 1, let last = self.textLineFragments.last, last.characterRange.length == 0 {
      height = last.typographicBounds.minY
    }
    return CGRect(x: -self.layoutFragmentFrame.minX + 1, y: 0, width: Self.barWidth, height: height)
  }

  override var renderingSurfaceBounds: CGRect {
    super.renderingSurfaceBounds.union(self.barBounds)
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    context.saveGState()
    context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
    context.fill(self.barBounds.offsetBy(dx: point.x, dy: point.y))
    context.restoreGState()
    super.draw(at: point, in: context)
  }
}
