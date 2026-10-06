import SwiftUI
import AppKit

/// A chat input field that supports:
/// - **Enter**: Send message
/// - **Option+Enter**: Send as announcement
/// - **Shift+Enter**: Insert newline
/// - **Tab**: Complete the name being typed, then the next name that fits; **Shift+Tab** goes back
///
/// Auto-resizes vertically up to `maxLines` lines, then scrolls.
/// Fills its entire frame; text is inset internally so the scroll bar
/// sits at the right edge of the container.
struct ChatInputField: NSViewRepresentable {
  @Binding var text: String
  @Binding var height: CGFloat
  var maxLines: Int = 5
  /// Your icon, where the chat has the senders', or nil for none.
  var iconID: Int? = nil
  /// The names Tab completes, best first.
  var namesToComplete: () -> [String] = { [] }
  var onSubmit: (_ announce: Bool) -> Void

  /// Single-line height matching what `recalculateHeight` computes for an empty field.
  static let defaultHeight: CGFloat = {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let lm = NSLayoutManager()
    let lineHeight = ceil(lm.defaultLineHeight(for: font))
    return lineHeight + ChatInputTextView.verticalInset * 2
  }()

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    // Use the system factory method which creates a properly configured
    // NSScrollView + NSTextView pair that works across all macOS versions.
    let scrollView = NSTextView.scrollableTextView()
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.autohidesScrollers = true
    scrollView.verticalScrollElasticity = .none

    // Replace the system NSTextView with our subclass, reusing the
    // properly configured text container from the factory method.
    guard let systemTextView = scrollView.documentView as? NSTextView,
          let textContainer = systemTextView.textContainer else {
      return scrollView
    }
    let textView = ChatInputTextView(frame: systemTextView.frame, textContainer: textContainer)
    textView.autoresizingMask = systemTextView.autoresizingMask
    textView.isVerticallyResizable = systemTextView.isVerticallyResizable
    textView.isHorizontallyResizable = systemTextView.isHorizontallyResizable
    textView.maxSize = systemTextView.maxSize
    textView.minSize = systemTextView.minSize
    scrollView.documentView = textView

    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.allowsUndo = true
    textView.font = .systemFont(ofSize: NSFont.systemFontSize)
    textView.textColor = .textColor
    textView.drawsBackground = false
    textView.updateInsets()
    textView.textContainer?.lineFragmentPadding = 0

    textView.delegate = context.coordinator
    textView.submitHandler = { announce in
      context.coordinator.parent.onSubmit(announce)
    }
    textView.namesToComplete = { [weak coordinator = context.coordinator] in
      coordinator?.parent.namesToComplete() ?? []
    }
    let coordinator = context.coordinator
    textView.frameResizeHandler = { [weak coordinator] in
      coordinator?.recalculateHeight()
    }

    context.coordinator.textView = textView
    context.coordinator.scrollView = scrollView

    DispatchQueue.main.async {
      context.coordinator.recalculateHeight()
    }

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else { return }
    textView.applyServerTheme(context.environment.serverTheme)
    // A generic one for an icon this copy of Hotline doesn't have.
    textView.icon = self.iconID.flatMap { HotlineState.getClassicIcon($0) ?? NSImage(named: "User") }
    // Never overwrite the text view's string while the IME is composing
    // (has marked text). Doing so clears the uncommitted composition,
    // causing input to vanish — especially when text wraps to a new line.
    if textView.hasMarkedText() {
      return
    }
    if textView.string != self.text {
      textView.string = self.text
      // Defer recalculation so the @Binding height update is not dropped
      // by SwiftUI (setting state during an update pass can be silently ignored).
      DispatchQueue.main.async {
        context.coordinator.recalculateHeight()
      }
    }
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ChatInputField
    weak var textView: ChatInputTextView?
    weak var scrollView: NSScrollView?

    init(_ parent: ChatInputField) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = self.textView else { return }
      self.parent.text = textView.string
      self.recalculateHeight()
    }

    func recalculateHeight() {
      guard let textView = self.textView else { return }

      let font = textView.font ?? .systemFont(ofSize: NSFont.systemFontSize)
      let tempLM = NSLayoutManager()
      let lineHeight = ceil(tempLM.defaultLineHeight(for: font))
      let maxContentHeight = ceil(lineHeight * CGFloat(self.parent.maxLines))

      let contentHeight: CGFloat
      if let layoutManager = textView.layoutManager,
         let textContainer = textView.textContainer {
        // TextKit 1
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        contentHeight = max(ceil(usedRect.height), lineHeight)
      } else if let textLayoutManager = textView.textLayoutManager {
        // TextKit 2
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let usageBounds = textLayoutManager.usageBoundsForTextContainer
        contentHeight = max(ceil(usageBounds.height), lineHeight)
      } else {
        contentHeight = lineHeight
      }

      let needsScroller = contentHeight > maxContentHeight
      let clampedContent = needsScroller ? maxContentHeight : contentHeight
      let newHeight = clampedContent + ChatInputTextView.verticalInset * 2

      self.scrollView?.hasVerticalScroller = needsScroller
      self.scrollView?.verticalScrollElasticity = needsScroller ? .allowed : .none

      if abs(newHeight - self.parent.height) > 0.5 {
        self.parent.height = newHeight
      }

      if needsScroller {
        textView.scrollRangeToVisible(textView.selectedRange())
      }
    }
  }
}

/// NSTextView subclass that intercepts Enter key variants and provides
/// asymmetric internal padding so the text area is inset from the edges.
/// Laid out like the messages above: your icon where they have their senders', and the text where
/// theirs starts.
class ChatInputTextView: NSTextView {
  var submitHandler: ((_ announce: Bool) -> Void)?
  var frameResizeHandler: (() -> Void)?
  /// The names Tab completes, best first.
  var namesToComplete: (() -> [String])?
  /// The name Tab last put in, and the others that fit what was typed, so another Tab can swap it
  /// for the next one.
  private var completion: (names: [String], index: Int, range: NSRange, inserted: String)?

  static let verticalInset: CGFloat = 24

  /// Your icon, where the messages above have their senders'. Nil for none, as when the chat
  /// doesn't show icons.
  var icon: NSImage? {
    didSet {
      guard self.icon !== oldValue else {
        return
      }
      self.iconView.image = self.icon
      self.iconView.isHidden = self.icon == nil
      self.updateInsets()
      // Another icon can be another width.
      self.updateIconPosition()
    }
  }

  /// Where the text starts, where the messages above have theirs: after the icons, when there's
  /// yours, or without, at the start of the line.
  var leftInset: CGFloat {
    ChatTranscriptTextView.lineStart + (self.icon == nil ? 0 : ChatMessageRenderer.textIndent)
  }
  /// Where the text ends, where the chat's lines do.
  let rightInset = ChatTranscriptTextView.lineStart

  /// Insets the text from the left past your icon, and from the right by `rightInset`. The text
  /// view's own inset is the same on both sides, so it's what they come to together, and
  /// `textContainerOrigin` moves the text over.
  func updateInsets() {
    let inset = NSSize(width: (self.leftInset + self.rightInset) / 2, height: Self.verticalInset)
    guard self.textContainerInset != inset else {
      return
    }
    self.textContainerInset = inset
    self.frameResizeHandler?()
  }

  override var textContainerOrigin: NSPoint {
    NSPoint(x: self.leftInset, y: super.textContainerOrigin.y)
  }

  private lazy var iconView: NSImageView = {
    let view = NSImageView()
    view.imageScaling = .scaleNone
    view.isHidden = true
    view.setAccessibilityElement(false)
    return view
  }()

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if self.window != nil {
      DispatchQueue.main.async { [weak self] in
        self?.window?.makeFirstResponder(self)
      }
    }
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if self.iconView.superview == nil, let clipView = self.superview {
      clipView.addSubview(self.iconView)
      self.updateIconPosition()
    }
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    self.updateIconPosition()
    self.frameResizeHandler?()
  }

  override func resetCursorRects() {
    self.addCursorRect(self.bounds, cursor: .iBeam)
  }

  override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    self.updateIconPosition()
  }

  override func didChangeText() {
    super.didChangeText()
    self.updateIconPosition()
  }

  // MARK: Completing Names

  override func insertTab(_ sender: Any?) {
    if !self.completeName(forward: true) {
      super.insertTab(sender)
    }
  }

  override func insertBacktab(_ sender: Any?) {
    if !self.completeName(forward: false) {
      super.insertBacktab(sender)
    }
  }

  /// Completes the name being typed before the insertion point, or right after a completion, puts
  /// in the next name that fits instead. Returns whether Tab was for a name, which it isn't with
  /// nothing typed before it.
  private func completeName(forward: Bool) -> Bool {
    let selection = self.selectedRange()
    guard !self.hasMarkedText(), selection.length == 0, let names = self.namesToComplete?(), !names.isEmpty else {
      return false
    }
    let text = self.string as NSString

    if let completion = self.completion, NSMaxRange(completion.range) == selection.location, NSMaxRange(completion.range) <= text.length,
       text.substring(with: completion.range) == completion.inserted {
      let count = completion.names.count
      let index = (completion.index + (forward ? 1 : count - 1)) % count
      self.insert(completion.names, at: index, replacing: completion.range)
      return true
    }

    // What's typed: the most of the line before the insertion point, from the start of a word,
    // that a name starts with, for names with spaces in them.
    let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
    guard selection.location > line.location, let typedBefore = Unicode.Scalar(text.character(at: selection.location - 1)),
          !CharacterSet.whitespacesAndNewlines.contains(typedBefore) else {
      return false
    }
    var start = line.location
    while start < selection.location {
      let typed = text.substring(with: NSRange(location: start, length: selection.location - start))
      let fits = names.filter { $0.range(of: typed, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil }
      if !fits.isEmpty {
        self.insert(fits, at: 0, replacing: NSRange(location: start, length: selection.location - start))
        return true
      }
      let space = text.rangeOfCharacter(from: .whitespaces, options: [], range: NSRange(location: start, length: selection.location - start))
      guard space.location != NSNotFound else {
        break
      }
      start = NSMaxRange(space)
    }
    NSSound.beep()
    return true
  }

  /// Puts a name in place of what was typed: at the start of a line followed by a colon, the way
  /// someone's spoken to, and elsewhere by a space.
  private func insert(_ names: [String], at index: Int, replacing range: NSRange) {
    let text = self.string as NSString
    let startsLine = range.location == 0 || [0x0A, 0x0D, 0x2028].contains(text.character(at: range.location - 1))
    let inserted = names[index] + (startsLine ? ": " : " ")
    self.insertText(inserted, replacementRange: range)
    self.completion = (names, index, NSRange(location: range.location, length: (inserted as NSString).length), inserted)
  }

  /// Puts your icon by the first line, as the chat has a message's sender: centered in the icon
  /// column, which a wide one spills out of, and on the line.
  func updateIconPosition() {
    guard let size = self.icon?.size else {
      return
    }
    let font = self.font ?? .systemFont(ofSize: NSFont.systemFontSize)

    // The first line, or with no text, where it would be.
    var lineRect = NSRect(x: 0, y: 0, width: 0, height: ceil(font.ascender + abs(font.descender) + font.leading))
    if let layoutManager = self.layoutManager {
      // TextKit 1 path
      if layoutManager.numberOfGlyphs > 0 {
        lineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
      } else {
        lineRect.size.height = layoutManager.defaultLineHeight(for: font)
      }
    } else if let textLayoutManager = self.textLayoutManager,
              let fragment = textLayoutManager.textLayoutFragment(for: textLayoutManager.documentRange.location),
              let line = fragment.textLineFragments.first {
      // TextKit 2 path
      lineRect = line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)
    }

    let midX = ChatTranscriptTextView.lineStart + ChatMessageRenderer.iconInset + ChatMessageRenderer.iconColumnWidth / 2
    let midY = self.textContainerInset.height + lineRect.midY
    // On whole points, as pixel art blurs between them.
    self.iconView.frame = NSRect(x: (midX - size.width / 2).rounded(), y: (midY - size.height / 2).rounded(), width: size.width, height: size.height)
  }

  override func keyDown(with event: NSEvent) {
    let isReturn = event.keyCode == 36 // Return key
    let isShift = event.modifierFlags.contains(.shift)
    let isOption = event.modifierFlags.contains(.option)

    // Let the IME handle Enter when text is being composed (e.g. Japanese IME).
    if self.hasMarkedText() {
      super.keyDown(with: event)
      return
    }

    if isReturn && isShift {
      // Shift+Enter: insert newline
      self.insertNewline(nil)
      return
    }

    if isReturn && isOption {
      // Option+Enter: send as announcement
      self.submitHandler?(true)
      return
    }

    if isReturn && !isShift && !isOption {
      // Enter: send normally
      self.submitHandler?(false)
      return
    }

    super.keyDown(with: event)
  }
}
