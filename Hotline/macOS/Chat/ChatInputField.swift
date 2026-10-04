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
    textView.textContainerInset = NSSize(width: textView.leftInset, height: ChatInputTextView.verticalInset)
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
/// Shows a chevron indicator next to the line containing the insertion point.
class ChatInputTextView: NSTextView {
  var submitHandler: ((_ announce: Bool) -> Void)?
  var frameResizeHandler: (() -> Void)?
  /// The names Tab completes, best first.
  var namesToComplete: (() -> [String])?
  /// The name Tab last put in, and the others that fit what was typed, so another Tab can swap it
  /// for the next one.
  private var completion: (names: [String], index: Int, range: NSRange, inserted: String)?

  static let verticalInset: CGFloat = 24

  let leftInset: CGFloat = 30
  let rightInset: CGFloat = 12

  private lazy var chevronView: NSImageView = {
    let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .semibold)
    let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    let iv = NSImageView()
    iv.image = image
    iv.contentTintColor = .tertiaryLabelColor
    iv.imageScaling = .scaleNone
    iv.setContentHuggingPriority(.required, for: .horizontal)
    iv.setContentHuggingPriority(.required, for: .vertical)
    iv.frame.size = image?.size ?? NSSize(width: 10, height: 12)
    return iv
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
    if self.chevronView.superview == nil, let clipView = self.superview {
      clipView.addSubview(self.chevronView)
      self.updateChevronPosition()
    }
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    self.updateChevronPosition()
    self.frameResizeHandler?()
  }

  override func resetCursorRects() {
    self.addCursorRect(self.bounds, cursor: .iBeam)
  }

  override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    self.updateChevronPosition()
  }

  override func didChangeText() {
    super.didChangeText()
    self.updateChevronPosition()
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

  func updateChevronPosition() {
    let font = self.font ?? .systemFont(ofSize: NSFont.systemFontSize)
    let length = self.textStorage?.length ?? 0

    let lineRect: NSRect

    if let layoutManager = self.layoutManager {
      // TextKit 1 path
      if length == 0 {
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        lineRect = NSRect(x: 0, y: 0, width: 0, height: lineHeight)
      } else {
        let insertionIndex = self.selectedRange().location
        let extraRect = layoutManager.extraLineFragmentRect
        if insertionIndex >= length && extraRect.height > 0 {
          lineRect = extraRect
        } else {
          let charIndex = min(insertionIndex, length - 1)
          let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
          lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }
      }
    } else if let textLayoutManager = self.textLayoutManager {
      // TextKit 2 path
      let defaultLineHeight = ceil(font.ascender + abs(font.descender) + font.leading)

      if length == 0 {
        lineRect = NSRect(x: 0, y: 0, width: 0, height: defaultLineHeight)
      } else {
        let insertionIndex = self.selectedRange().location
        let docRange = textLayoutManager.documentRange

        let location: NSTextLocation
        if insertionIndex >= length {
          location = docRange.endLocation
        } else {
          location = textLayoutManager.location(docRange.location, offsetBy: insertionIndex) ?? docRange.location
        }

        if let fragment = textLayoutManager.textLayoutFragment(for: location) {
          lineRect = fragment.layoutFragmentFrame
        } else {
          // Fallback: find the last layout fragment
          var lastRect = NSRect(x: 0, y: 0, width: 0, height: defaultLineHeight)
          textLayoutManager.enumerateTextLayoutFragments(
            from: docRange.endLocation,
            options: [.reverse, .ensuresLayout]
          ) { fragment in
            lastRect = fragment.layoutFragmentFrame
            return false
          }
          lineRect = lastRect
        }
      }
    } else {
      return
    }

    let chevronSize = self.chevronView.frame.size
    let x = (self.leftInset - chevronSize.width - 4)
    let y = self.textContainerInset.height + lineRect.origin.y + (lineRect.height - chevronSize.height) / 2.0
    self.chevronView.frame.origin = NSPoint(x: x, y: y)
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
