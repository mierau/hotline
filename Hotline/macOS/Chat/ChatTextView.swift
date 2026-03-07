import SwiftUI
import AppKit

// MARK: - ChatTextView (NSViewRepresentable)

struct ChatTextView: NSViewRepresentable {
  let messages: [ChatMessage]
  var searchQuery: String = ""
  var watchWords: [HighlightWord] = []
  var isFiltered: Bool = false
  var cachedText: NSAttributedString?
  var cachedCount: Int = 0
  var onCacheUpdate: ((NSAttributedString, Int) -> Void)?
  var openURL: ((URL) -> Void)?
  
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }
  
  func makeNSView(context: Context) -> NSScrollView {
    let textView = BottomAnchoredTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.isRichText = true
    textView.usesFindBar = false
    textView.textContainerInset = NSSize(width: 24, height: 24)
    textView.isAutomaticLinkDetectionEnabled = false
    textView.font = .systemFont(ofSize: NSFont.systemFontSize)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    
    // Link attributes: asset catalog color + pointing hand cursor, no underline
    textView.linkTextAttributes = [
      .foregroundColor: NSColor(named: "Link Color") ?? .linkColor,
      .cursor: NSCursor.pointingHand,
    ]

    textView.delegate = textView
    textView.openURLAction = self.openURL

    let scrollView = BottomPinningScrollView()
    scrollView.contentView = BottomClipView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    
    context.coordinator.textView = textView
    context.coordinator.scrollView = scrollView
    
    return scrollView
  }
  
  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.onCacheUpdate = self.isFiltered ? nil : self.onCacheUpdate

    if let textView = coordinator.textView {
      textView.openURLAction = self.openURL
    }
    
    if coordinator.needsFullRebuild(for: self.messages) {
      coordinator.rebuildAll(messages: self.messages, cachedText: self.isFiltered ? nil : self.cachedText, cachedCount: self.isFiltered ? 0 : self.cachedCount)
    } else if self.messages.count > coordinator.renderedCount {
      coordinator.appendMessages(messages: self.messages)
    }
    
    if coordinator.currentWatchWords != self.watchWords {
      coordinator.applyWatchWordHighlights(words: self.watchWords)
    }

    if coordinator.currentSearchQuery != self.searchQuery {
      coordinator.applySearchHighlights(query: self.searchQuery)
    }
  }
  
  // MARK: - Coordinator
  
  class Coordinator {
    weak var textView: BottomAnchoredTextView?
    weak var scrollView: NSScrollView? {
      didSet { self.observeScroll() }
    }
    var onCacheUpdate: ((NSAttributedString, Int) -> Void)?
    var renderedCount = 0
    var currentSearchQuery = ""
    var currentWatchWords: [HighlightWord] = []
    private var lastMessageIDs: [UUID] = []
    private var scrollObserver: NSObjectProtocol?
    private var highlightedCharRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var lastHighlightedVisibleOriginY: CGFloat = -.greatestFiniteMagnitude
    
    private func observeScroll() {
      self.scrollObserver = nil
      guard let scrollView = self.scrollView else { return }
      scrollView.contentView.postsBoundsChangedNotifications = true
      self.scrollObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: scrollView.contentView,
        queue: .main
      ) { [weak self] _ in
        self?.scrollDidChange()
      }
    }
    
    private func scrollDidChange() {
      guard !self.currentSearchQuery.isEmpty || !self.currentWatchWords.isEmpty,
            let scrollView = self.scrollView else { return }
      let visibleY = scrollView.contentView.bounds.origin.y
      let viewportH = scrollView.contentView.bounds.height
      // Only re-highlight when scrolled beyond half the viewport from last highlight center
      if abs(visibleY - self.lastHighlightedVisibleOriginY) > viewportH * 0.5 {
        self.highlightVisibleRange()
      }
    }
    
    deinit {
      if let observer = self.scrollObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }
    
    func needsFullRebuild(for messages: [ChatMessage]) -> Bool {
      if messages.count < self.renderedCount { return true }
      if self.renderedCount == 0 && messages.isEmpty { return false }
      if self.renderedCount == 0 { return true }
      for i in 0..<min(self.renderedCount, messages.count, self.lastMessageIDs.count) {
        if messages[i].id != self.lastMessageIDs[i] { return true }
      }
      return false
    }
    
    func rebuildAll(messages: [ChatMessage], cachedText: NSAttributedString?, cachedCount: Int) {
      guard let textView = self.textView else { return }
      guard let storage = textView.textStorage else { return }
      
      // Try to restore from cache if it matches the current messages
      if let cached = cachedText,
         cachedCount == messages.count,
         cachedCount > 0 {
        storage.beginEditing()
        storage.setAttributedString(cached)
        storage.endEditing()
        
        self.renderedCount = cachedCount
        self.lastMessageIDs = messages.map(\.id)
        textView.needsDisplay = true
        self.scrollToBottom()
        return
      }
      
      storage.beginEditing()
      storage.setAttributedString(NSAttributedString())
      for (index, msg) in messages.enumerated() {
        if index > 0 {
          storage.append(NSAttributedString(string: "\n"))
        }
        storage.append(self.renderMessage(msg))
      }
      storage.endEditing()
      
      self.renderedCount = messages.count
      self.lastMessageIDs = messages.map(\.id)
      textView.needsDisplay = true
      
      // Save to cache
      self.onCacheUpdate?(NSAttributedString(attributedString: storage), self.renderedCount)

      if !self.currentSearchQuery.isEmpty || !self.currentWatchWords.isEmpty {
        self.highlightedCharRange = NSRange(location: NSNotFound, length: 0)
        self.lastHighlightedVisibleOriginY = -.greatestFiniteMagnitude
        self.highlightVisibleRange()
      }

      self.scrollToBottom()
    }
    
    func appendMessages(messages: [ChatMessage]) {
      guard let textView = self.textView else { return }
      guard let storage = textView.textStorage else { return }
      
      let wasAtBottom = self.isScrolledToBottom()
      let startIndex = self.renderedCount
      
      storage.beginEditing()
      for i in startIndex..<messages.count {
        if storage.length > 0 {
          storage.append(NSAttributedString(string: "\n"))
        }
        storage.append(self.renderMessage(messages[i]))
      }
      storage.endEditing()
      
      self.renderedCount = messages.count
      self.lastMessageIDs = messages.map(\.id)
      
      // Update cache
      self.onCacheUpdate?(NSAttributedString(attributedString: storage), self.renderedCount)

      if !self.currentSearchQuery.isEmpty || !self.currentWatchWords.isEmpty {
        self.highlightedCharRange = NSRange(location: NSNotFound, length: 0)
        self.lastHighlightedVisibleOriginY = -.greatestFiniteMagnitude
        self.highlightVisibleRange()
      }

      if wasAtBottom || startIndex == 0 {
        self.scrollToBottom()
      }
    }
    
    func scrollToBottom() {
      guard let textView = self.textView else { return }
      let suppress = !textView.hasRenderedOnce
      if suppress {
        textView.pendingScrollToBottom = true
      }
      DispatchQueue.main.async {
        textView.scrollToEndOfDocument(nil)
        if suppress {
          textView.pendingScrollToBottom = false
          textView.needsDisplay = true
        }
      }
    }
    
    func isScrolledToBottom() -> Bool {
      guard let scrollView = self.scrollView else { return true }
      let clipView = scrollView.contentView
      let docHeight = scrollView.documentView?.frame.height ?? 0
      let clipHeight = clipView.bounds.height
      if docHeight <= clipHeight { return true }
      let scrollY = clipView.bounds.origin.y
      return scrollY + clipHeight >= docHeight - 1
    }
    
    // MARK: - Search Highlighting
    
    func applySearchHighlights(query: String) {
      guard let layoutManager = self.textView?.layoutManager,
            let _ = self.textView?.textStorage else { return }

      // Clear all previous highlights when query changes
      if self.highlightedCharRange.location != NSNotFound {
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: self.highlightedCharRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: self.highlightedCharRange)
        self.highlightedCharRange = NSRange(location: NSNotFound, length: 0)
      }

      self.currentSearchQuery = query
      self.lastHighlightedVisibleOriginY = -.greatestFiniteMagnitude

      if !query.isEmpty || !self.currentWatchWords.isEmpty {
        self.highlightVisibleRange()
      }
    }

    func applyWatchWordHighlights(words: [HighlightWord]) {
      guard let layoutManager = self.textView?.layoutManager,
            let _ = self.textView?.textStorage else { return }

      // Clear all previous highlights when watch words change
      if self.highlightedCharRange.location != NSNotFound {
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: self.highlightedCharRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: self.highlightedCharRange)
        self.highlightedCharRange = NSRange(location: NSNotFound, length: 0)
      }

      self.currentWatchWords = words
      self.lastHighlightedVisibleOriginY = -.greatestFiniteMagnitude

      if !words.isEmpty || !self.currentSearchQuery.isEmpty {
        self.highlightVisibleRange()
      }
    }
    
    func highlightVisibleRange() {
      guard !self.currentSearchQuery.isEmpty || !self.currentWatchWords.isEmpty,
            let textView = self.textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            let storage = textView.textStorage,
            let scrollView = self.scrollView else { return }

      // Compute a buffer zone: 2x the viewport height centered on the visible area
      let clipBounds = scrollView.contentView.bounds
      let viewportH = clipBounds.height
      let bufferH = viewportH * 2
      let bufferMinY = max(0, clipBounds.origin.y - bufferH / 2)
      let bufferMaxY = clipBounds.origin.y + viewportH + bufferH / 2
      let bufferRect = NSRect(x: 0, y: bufferMinY, width: textView.bounds.width, height: bufferMaxY - bufferMinY)

      // Convert the buffer rect to a character range via the layout manager
      let glyphRange = layoutManager.glyphRange(forBoundingRect: bufferRect, in: textContainer)
      let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

      guard charRange.length > 0 else { return }

      // Clear previous highlights
      if self.highlightedCharRange.location != NSNotFound {
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: self.highlightedCharRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: self.highlightedCharRange)
      }

      let searchString = storage.string as NSString

      // Apply watch word highlights first — search highlights override on overlap
      if !self.currentWatchWords.isEmpty {
        for highlightWord in self.currentWatchWords {
          let watchBg = highlightWord.nsBackgroundColor
          let watchFg = highlightWord.nsForegroundColor
          var searchRange = charRange
          while searchRange.location < NSMaxRange(charRange) && searchRange.length > 0 {
            let foundRange = searchString.range(
              of: highlightWord.word,
              options: [.caseInsensitive, .literal],
              range: searchRange
            )
            guard foundRange.location != NSNotFound, foundRange.location < NSMaxRange(charRange) else { break }

            // Skip matches inside username prefixes
            let isInUsername = storage.attribute(BottomAnchoredTextView.skipHighlightKey, at: foundRange.location, effectiveRange: nil) != nil
            if !isInUsername {
              layoutManager.addTemporaryAttribute(.backgroundColor, value: watchBg, forCharacterRange: foundRange)
              layoutManager.addTemporaryAttribute(.foregroundColor, value: watchFg, forCharacterRange: foundRange)
            }

            searchRange.location = NSMaxRange(foundRange)
            searchRange.length = NSMaxRange(charRange) - searchRange.location
          }
        }
      }

      // Apply search highlights on top (yellow) — overrides watch words where they overlap
      if !self.currentSearchQuery.isEmpty {
        let highlightBg = NSColor.systemYellow.withAlphaComponent(0.5)
        let highlightFg = NSColor.black
        var searchRange = charRange

        while searchRange.location < NSMaxRange(charRange) && searchRange.length > 0 {
          let foundRange = searchString.range(
            of: self.currentSearchQuery,
            options: [.caseInsensitive, .literal],
            range: searchRange
          )
          guard foundRange.location != NSNotFound, foundRange.location < NSMaxRange(charRange) else { break }

          layoutManager.addTemporaryAttribute(.backgroundColor, value: highlightBg, forCharacterRange: foundRange)
          layoutManager.addTemporaryAttribute(.foregroundColor, value: highlightFg, forCharacterRange: foundRange)

          searchRange.location = NSMaxRange(foundRange)
          searchRange.length = NSMaxRange(charRange) - searchRange.location
        }
      }

      self.highlightedCharRange = charRange
      self.lastHighlightedVisibleOriginY = clipBounds.origin.y
    }
    
    // MARK: - Message Rendering
    
    func renderMessage(_ msg: ChatMessage) -> NSAttributedString {
      switch msg.type {
      case .message:
        return msg.isEmote ? self.renderEmoteMessage(msg) : self.renderChatMessage(msg)
      case .joined:
        return self.renderJoinedMessage(msg)
      case .left:
        return self.renderLeftMessage(msg)
      case .signOut:
        return self.renderSignOutMessage(msg)
      case .server:
        return self.renderServerMessage(msg)
      case .agreement:
        return NSAttributedString()
      }
    }
    
    private var baseFont: NSFont {
      .systemFont(ofSize: NSFont.systemFontSize)
    }
    
    private var semiboldFont: NSFont {
      .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }
    
    private var linkColor: NSColor {
      NSColor(named: "Link Color") ?? .linkColor
    }
    
    private func renderEmoteMessage(_ msg: ChatMessage) -> NSAttributedString {
      let paraStyle = NSMutableParagraphStyle()
      paraStyle.firstLineHeadIndent = 0
      paraStyle.headIndent = 12
      paraStyle.lineSpacing = 3
      paraStyle.paragraphSpacing = 8
      
      let italicDescriptor = self.baseFont.fontDescriptor.withSymbolicTraits(.italic)
      let italicFont = NSFont(descriptor: italicDescriptor, size: self.baseFont.pointSize) ?? self.baseFont
      
      // Strip "*** " prefix for display
      let displayText: String
      if let match = msg.text.firstMatch(of: ChatMessage.emoteParser) {
        displayText = String(match.1)
      } else {
        displayText = msg.text
      }
      
      return NSAttributedString(
        string: displayText,
        attributes: [
          .font: italicFont,
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: paraStyle,
        ]
      )
    }
    
    private func renderChatMessage(_ msg: ChatMessage) -> NSAttributedString {
      let result = NSMutableAttributedString()

      // Hanging indent: first line flush, wrapped lines indented
      let paraStyle = NSMutableParagraphStyle()
//      paraStyle.alignment = .justified
      paraStyle.firstLineHeadIndent = 0
      paraStyle.headIndent = 16
      paraStyle.lineSpacing = 3
      paraStyle.paragraphSpacing = 8

      let isOwnMessage = msg.username?.lowercased() == Prefs.shared.username.lowercased()

      // Replace newlines with line separators so the entire message stays
      // in one paragraph, keeping headIndent on all lines after the first.
      let bodyText = msg.text.replacingOccurrences(of: "\n", with: "\u{2028}")

      if let username = msg.username {
        let usernameColor: NSColor = msg.isAdmin
          ? (NSColor(named: "Hotline Red") ?? .systemRed)
          : .textColor
        let usernameAttr = NSAttributedString(
          string: "\(username): ",
          attributes: [
            .font: self.semiboldFont,
            .foregroundColor: usernameColor,
            .paragraphStyle: paraStyle,
            BottomAnchoredTextView.skipHighlightKey: true,
          ]
        )
        result.append(usernameAttr)

        let bodyAttr = bodyText.toNSAttributedStringWithMarkdownAndLinks(
          baseFont: self.baseFont,
          linkColor: self.linkColor,
          paragraphStyle: paraStyle
        )
        result.append(bodyAttr)
      } else {
        let bodyAttr = bodyText.toNSAttributedStringWithMarkdownAndLinks(
          baseFont: self.baseFont,
          linkColor: self.linkColor,
          paragraphStyle: paraStyle
        )
        result.append(bodyAttr)
      }

      // Skip watch word highlighting on the user's own messages entirely
      if isOwnMessage {
        result.addAttribute(BottomAnchoredTextView.skipHighlightKey, value: true, range: NSRange(location: 0, length: result.length))
      }

      return result
    }
    
    private func renderJoinedMessage(_ msg: ChatMessage) -> NSAttributedString {
      let paraStyle = NSMutableParagraphStyle()
      paraStyle.lineSpacing = 2
      paraStyle.paragraphSpacing = 8

      let color: NSColor = msg.isAdmin
        ? (NSColor(named: "Hotline Red") ?? .systemRed)
        : .secondaryLabelColor

      let arrow = "\u{2192} " // right arrow
      let text = arrow + msg.text
      return NSAttributedString(
        string: text,
        attributes: [
          .font: self.baseFont,
          .foregroundColor: color,
          .paragraphStyle: paraStyle,
          BottomAnchoredTextView.skipHighlightKey: true,
        ]
      )
    }

    private func renderLeftMessage(_ msg: ChatMessage) -> NSAttributedString {
      let paraStyle = NSMutableParagraphStyle()
      paraStyle.lineSpacing = 2
      paraStyle.paragraphSpacing = 8

      let color: NSColor = msg.isAdmin
        ? (NSColor(named: "Hotline Red") ?? .systemRed)
        : .secondaryLabelColor

      let arrow = "\u{2190} " // left arrow
      let text = arrow + msg.text
      return NSAttributedString(
        string: text,
        attributes: [
          .font: self.baseFont,
          .foregroundColor: color,
          .paragraphStyle: paraStyle,
          BottomAnchoredTextView.skipHighlightKey: true,
        ]
      )
    }
    
    private func renderSignOutMessage(_ msg: ChatMessage) -> NSAttributedString {
      let paraStyle = NSMutableParagraphStyle()
      paraStyle.paragraphSpacingBefore = 26 // + 8 from preceding message's paragraphSpacing = 34
      paraStyle.paragraphSpacing = 18
      paraStyle.alignment = .left

      let dateText = formatChatDividerDate(msg.date)
      let result = NSMutableAttributedString(
        string: dateText,
        attributes: [
          .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: paraStyle,
        ]
      )
      result.addAttribute(BottomAnchoredTextView.chatDividerKey, value: true, range: NSRange(location: 0, length: result.length))
      return result
    }
    
    private func renderServerMessage(_ msg: ChatMessage) -> NSAttributedString {
      let result = NSMutableAttributedString()
      
      let paraStyle = NSMutableParagraphStyle()
      paraStyle.paragraphSpacingBefore = 16 // + 8 from preceding message's paragraphSpacing = 24
      paraStyle.paragraphSpacing = 24
      paraStyle.alignment = .center
      paraStyle.lineSpacing = 3
      paraStyle.firstLineHeadIndent = 16
      paraStyle.headIndent = 28
      paraStyle.tailIndent = -16
      
      // Icon attachment
      if let image = NSImage(named: "Server Message") {
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { rect in
          image.draw(in: rect)
          return true
        }
        attachment.bounds = CGRect(x: 0, y: -4, width: 20, height: 20)
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: "  "))
      }
      
      // Text — use line separator (\u{2028}) instead of newlines to keep
      // everything in one paragraph so headIndent applies to all lines
      // and paragraph spacing doesn't repeat between lines.
      let displayText = msg.text.replacingOccurrences(of: "\\n\\s*", with: "\u{2028}", options: .regularExpression)
      let textAttr = NSAttributedString(
        string: displayText,
        attributes: [
          .font: self.semiboldFont,
          .foregroundColor: NSColor.textColor,
        ]
      )
      result.append(textAttr)
      
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttribute(.paragraphStyle, value: paraStyle, range: fullRange)
      result.addAttribute(BottomAnchoredTextView.serverMessageKey, value: true, range: fullRange)
      
      return result
    }
  }
}

// MARK: - BottomAnchoredTextView

/// NSTextView subclass that pushes content to the bottom when content is shorter than the view.
class BottomAnchoredTextView: NSTextView, NSTextViewDelegate {
  static let serverMessageKey = NSAttributedString.Key("serverMessageBackground")
  static let chatDividerKey = NSAttributedString.Key("chatDividerLine")
  static let skipHighlightKey = NSAttributedString.Key("skipHighlight")
  private var hoveredLinkRange: NSRange?

  var openURLAction: ((URL) -> Void)?

  private static let bubblePaddingV: CGFloat = 10
  private static let bubbleCornerRadius: CGFloat = 10

  /// The height of the toolbar/title bar overlapping this scroll view.
  var toolbarOverlap: CGFloat {
    guard let scrollView = self.enclosingScrollView,
          let window = scrollView.window else { return 0 }
    let scrollViewRect = scrollView.convert(scrollView.bounds, to: nil)
    return max(0, scrollViewRect.maxY - window.contentLayoutRect.maxY)
  }

  /// Top padding: at least the configured inset, but enough to clear the toolbar.
  var topPadding: CGFloat {
    max(self.textContainerInset.height, self.toolbarOverlap)
  }

  /// Whether the view has been laid out with a valid frame at least once.
  /// Suppresses drawing until the bottom offset can be correctly computed,
  /// preventing a flash where content appears at the top before jumping to the bottom.
  private var hasValidFrame = false

  /// Re-entrancy guard for `updateBottomOffset` ↔ `setFrameSize`.
  private var isUpdatingOffset = false

  /// Suppresses drawing during the initial deferred scroll-to-bottom so the user
  /// never sees a frame of un-scrolled content on first load. Only used once;
  /// after the first successful draw, subsequent rebuilds (search, reconnect)
  /// show content immediately without suppression.
  var pendingScrollToBottom = false

  /// Whether the view has completed at least one full draw cycle.
  private(set) var hasRenderedOnce = false

  /// Extra offset added to `textContainerOrigin.y` to push content to the bottom
  /// when the text view is taller than its natural content height.
  private var cachedBottomOffset: CGFloat = 0

  /// The minimum frame height needed: topPadding + usedRect + bottomPadding.
  /// Set by `updateBottomOffset` and enforced by `setFrameSize` so NSTextView's
  /// auto-sizing can't shrink the frame below what we need.
  private var minimumContentHeight: CGFloat = 0

  override var textContainerOrigin: NSPoint {
    return NSPoint(x: self.textContainerInset.width,
                   y: self.cachedBottomOffset + self.topPadding)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard self.hasValidFrame, !self.pendingScrollToBottom else { return }
    self.drawServerMessageBackgrounds(in: dirtyRect)
    self.drawChatDividerCapsules(in: dirtyRect)
    super.draw(dirtyRect)
    self.hasRenderedOnce = true
  }

  override func viewWillDraw() {
    super.viewWillDraw()
    guard !self.pendingScrollToBottom else { return }
    self.updateBottomOffset()
    self.hasValidFrame = true
  }

  override func setFrameSize(_ newSize: NSSize) {
    var size = newSize
    // Enforce cached minimum height so NSTextView's auto-sizing can't shrink
    // the frame below what we need (topPadding + content + bottomPadding).
    // We intentionally do NOT query the layout manager here — doing so during
    // live resize interferes with the layout/resize cycle and blocks text reflow.
    size.height = max(size.height, self.minimumContentHeight)
    // Ensure the text view always fills the clip view so there's no gap below content.
    // When content is short, cachedBottomOffset pushes text to the bottom.
    if let clipHeight = self.enclosingScrollView?.contentView.bounds.height {
      size.height = max(size.height, clipHeight)
    }
    // Avoid no-op calls that could loop with auto-sizing.
    guard abs(size.width - self.frame.width) > 0.5
       || abs(size.height - self.frame.height) > 0.5 else { return }
    super.setFrameSize(size)
    // Do NOT call updateBottomOffset() here — forcing layout (ensureLayout)
    // during the resize/tile chain prevents text from reflowing during live
    // window resize. viewWillDraw calls updateBottomOffset on each draw frame.
  }

  /// Recomputes `cachedBottomOffset` based on the current layout.
  /// When the text view frame is taller than the natural content height
  /// (because of the clip-height clamp), this pushes the text container
  /// down so content appears at the bottom.
  func updateBottomOffset() {
    guard !self.isUpdatingOffset else { return }
    self.isUpdatingOffset = true
    defer { self.isUpdatingOffset = false }

    guard let lm = self.layoutManager, let tc = self.textContainer else { return }
    lm.ensureLayout(for: tc)

    let usedHeight = lm.usedRect(for: tc).height
    let topPad = self.topPadding
    let bottomPad = self.textContainerInset.height
    let naturalHeight = topPad + usedHeight + bottomPad

    // Cache so setFrameSize can enforce without querying the layout manager.
    self.minimumContentHeight = naturalHeight

    let clipHeight = self.enclosingScrollView?.contentView.bounds.height ?? self.bounds.height
    let desiredHeight = max(naturalHeight, clipHeight)

    let newOffset = (desiredHeight > naturalHeight) ? (desiredHeight - naturalHeight) : 0
    let offsetChanged = abs(self.cachedBottomOffset - newOffset) > 0.5
    let heightChanged = abs(self.frame.height - desiredHeight) > 0.5

    self.cachedBottomOffset = newOffset

    if heightChanged {
      self.setFrameSize(NSSize(width: self.frame.width, height: desiredHeight))
    }
    if offsetChanged || heightChanged {
      self.needsDisplay = true
    }
  }

  override func viewDidEndLiveResize() {
    // Workaround: NSTextView internally calls _adjustedCenteredScrollRectToVisible:forceCenter:
    // during viewDidEndLiveResize, which computes an incorrect visible rect when
    // textContainerInset is non-zero, causing a jarring scroll jump. Temporarily clearing
    // the inset prevents this.
    let savedInset = self.textContainerInset
    self.textContainerInset = .zero
    super.viewDidEndLiveResize()
    self.textContainerInset = savedInset
  }

  /// Draws rounded-rect backgrounds behind server messages, before the text is drawn.
  /// Done here rather than in NSLayoutManager.drawBackground so the bubble padding
  /// is not clipped to the line fragment rects.
  private func drawServerMessageBackgrounds(in dirtyRect: NSRect) {
    guard let storage = self.textStorage,
          let layoutManager = self.layoutManager,
          let container = self.textContainer else { return }

    let origin = self.textContainerOrigin
    let fullRange = NSRange(location: 0, length: storage.length)

    storage.enumerateAttribute(Self.serverMessageKey, in: fullRange, options: []) { value, range, _ in
      guard value != nil else { return }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

      let bgRect = NSRect(
        x: origin.x,
        y: boundingRect.minY - Self.bubblePaddingV + origin.y,
        width: container.size.width,
        height: boundingRect.height + Self.bubblePaddingV * 2
      )

      guard bgRect.intersects(dirtyRect) else { return }

      NSColor.textColor.withAlphaComponent(0.06).setFill()
      NSBezierPath(roundedRect: bgRect, xRadius: Self.bubbleCornerRadius, yRadius: Self.bubbleCornerRadius).fill()
    }
  }

  /// Draws backgrounds behind date divider text — flat left edge, rounded right edge.
  private func drawChatDividerCapsules(in dirtyRect: NSRect) {
    guard let storage = self.textStorage,
          let layoutManager = self.layoutManager,
          let container = self.textContainer else { return }

    let origin = self.textContainerOrigin
    let fullRange = NSRange(location: 0, length: storage.length)
    let paddingH: CGFloat = 10
    let paddingV: CGFloat = 3

    storage.enumerateAttribute(Self.chatDividerKey, in: fullRange, options: []) { value, range, _ in
      guard value != nil else { return }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      let textRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

      let rightX = textRect.maxX + origin.x + paddingH
      let y = textRect.minY + origin.y - paddingV
      let h = textRect.height + paddingV * 2
      let r = h / 2

      let shapeRect = NSRect(x: 0, y: y, width: rightX + r, height: h)
      guard shapeRect.intersects(dirtyRect) else { return }

      // Flat left edge, capsule-rounded right edge
      let path = NSBezierPath()
      path.move(to: NSPoint(x: 0, y: y + h))              // bottom-left
      path.line(to: NSPoint(x: 0, y: y))                   // top-left
      path.line(to: NSPoint(x: rightX, y: y))              // top-right before arc
      path.appendArc(
        withCenter: NSPoint(x: rightX, y: y + r),
        radius: r,
        startAngle: -90,
        endAngle: 90,
        clockwise: false
      )
      path.line(to: NSPoint(x: 0, y: y + h))              // back to bottom-left
      path.close()

      NSColor.tertiarySystemFill.setFill()
      path.fill()
    }
  }
  
  // MARK: - NSTextViewDelegate

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    let url: URL?
    if let linkURL = link as? URL {
      url = linkURL
    } else if let linkString = link as? String {
      url = URL(string: linkString)
    } else {
      url = nil
    }

    guard let url = url else { return false }

    // Route through SwiftUI's openURL so hotline:// links fire
    // the app's onOpenURL handlers without leaving the process.
    // Falls back to NSWorkspace for non-hotline links or if
    // the SwiftUI action isn't available.
    if let openURL = self.openURLAction {
      openURL(url)
    } else {
      NSWorkspace.shared.open(url)
    }
    return true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in self.trackingAreas where area.owner === self {
      self.removeTrackingArea(area)
    }
    let area = NSTrackingArea(
      rect: self.bounds,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    self.addTrackingArea(area)
  }
  
  override func mouseMoved(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    let charIndex = self.characterIndexForInsertion(at: point)
    
    guard let storage = self.textStorage, charIndex < storage.length else {
      self.clearHoveredLink()
      super.mouseMoved(with: event)
      return
    }
    
    var linkRange = NSRange()
    let linkValue = storage.attribute(.link, at: charIndex, effectiveRange: &linkRange)
    
    if linkValue != nil {
      if self.hoveredLinkRange != linkRange {
        self.clearHoveredLink()
        self.layoutManager?.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: linkRange)
        self.hoveredLinkRange = linkRange
      }
    } else {
      self.clearHoveredLink()
    }
    
    super.mouseMoved(with: event)
  }
  
  override func mouseExited(with event: NSEvent) {
    self.clearHoveredLink()
    super.mouseExited(with: event)
  }
  
  private func clearHoveredLink() {
    if let range = self.hoveredLinkRange {
      self.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
      self.hoveredLinkRange = nil
    }
  }
  
}

// MARK: - BottomClipView

/// NSClipView subclass that prevents scrolling past the document bottom
/// when content fits entirely in the viewport.
class BottomClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var constrained = super.constrainBoundsRect(proposedBounds)
    let docHeight = self.documentView?.frame.height ?? 0
    let clipHeight = self.bounds.height
    // When content fits entirely, pin the origin to zero in both directions.
    // Without this, mouse wheel scrolling can push the content up or down
    // within the viewport even though there's nothing to scroll to.
    // Trackpad rubber-banding is handled by super and snaps back on its own.
    if docHeight <= clipHeight {
      constrained.origin.y = 0
    }
    return constrained
  }
}

// MARK: - BottomPinningScrollView

/// NSScrollView subclass that preserves pin-to-bottom across resize
/// and zeros SwiftUI-injected content insets.
class BottomPinningScrollView: NSScrollView {
  fileprivate var shouldPinToBottom = true
  fileprivate var isAdjusting = false

  private func isAtBottom() -> Bool {
    let clipHeight = self.contentView.bounds.height
    guard clipHeight > 0 else { return self.shouldPinToBottom }
    let docHeight = self.documentView?.frame.height ?? 0
    if docHeight <= clipHeight { return true }
    let scrollY = self.contentView.bounds.origin.y
    return scrollY + clipHeight >= docHeight - 1
  }

  override func setFrameSize(_ newSize: NSSize) {
    self.shouldPinToBottom = self.isAtBottom()
    self.isAdjusting = true
    super.setFrameSize(newSize)
    self.isAdjusting = false
  }

  override func tile() {
    // Zero out the TOP content inset only. SwiftUI's .ignoresSafeArea injects
    // a top inset for the toolbar that we don't want — we handle that gap via
    // topPadding on the text view instead. The BOTTOM inset comes from
    // SwiftUI's .safeAreaInset(edge: .bottom) for the chat input bar and must
    // be preserved so the clip view height correctly reflects the visible area.
    let insets = self.contentInsets
    if insets.top != 0 {
      self.contentInsets = NSEdgeInsets(top: 0, left: insets.left, bottom: insets.bottom, right: insets.right)
    }

    super.tile()

    let docHeight = self.documentView?.frame.height ?? 0
    let clipHeight = self.contentView.bounds.height

    if docHeight <= clipHeight {
      // Content fits entirely — ensure the clip view origin is at zero.
      // constrainBoundsRect on BottomClipView prevents scroll gestures from
      // moving it, but reset it here too in case layout changed it.
      if self.contentView.bounds.origin.y != 0 {
        self.isAdjusting = true
        self.contentView.setBoundsOrigin(.zero)
        self.isAdjusting = false
      }
    } else if self.shouldPinToBottom {
      self.isAdjusting = true
      self.contentView.setBoundsOrigin(NSPoint(x: 0, y: docHeight - clipHeight))
      self.isAdjusting = false
    }
  }

  override func viewDidEndLiveResize() {
    let wasAtBottom = self.shouldPinToBottom
    super.viewDidEndLiveResize()
    // After live resize, deferred layout may change document height.
    // reflectScrolledClipView can set shouldPinToBottom = false during
    // the relayout because the scroll position hasn't caught up yet.
    // Restore it so the next tile() re-pins correctly.
    if wasAtBottom {
      self.shouldPinToBottom = true
    }
  }

  override func reflectScrolledClipView(_ cView: NSClipView) {
    super.reflectScrolledClipView(cView)
    if !self.isAdjusting {
      self.shouldPinToBottom = self.isAtBottom()
    }
  }
}

// MARK: - Chat Divider Date Formatting

private func formatChatDividerDate(_ date: Date) -> String {
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
  let f = DateFormatter()
  f.dateFormat = isCurrentYear
  ? "MMMM d'\(suffix)' \u{2022} h:mm a"
  : "MMMM d'\(suffix)', yyyy \u{2022} h:mm a"
  return f.string(from: date)
}

// MARK: - Preview

#Preview {
  ChatTextView(messages: [
    ChatMessage(text: "admin: Hello everyone! Check out https://example.com", type: .message, date: Date()),
    ChatMessage(text: "guest joined the chat", type: .joined, date: Date()),
    ChatMessage(text: "user: **bold** and *italic* text", type: .message, date: Date()),
    ChatMessage(text: "*** admin waves hello", type: .message, date: Date()),
    ChatMessage(text: "", type: .signOut, date: Date()),
    ChatMessage(text: "Welcome to the server!", type: .server, date: Date()),
    ChatMessage(text: "admin: Back online!", type: .message, date: Date()),
  ])
  .frame(width: 500, height: 400)
}
