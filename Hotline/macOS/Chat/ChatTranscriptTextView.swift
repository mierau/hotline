import AppKit

/// The chat transcript: an NSTextView on TextKit 2, which only lays out the messages on screen.
/// Opening a long chat, resizing its window, and trimming old messages cost about the same at any
/// length.
///
/// Don't use `layoutManager` here, even to read it. Asking for it switches the view to TextKit 1
/// for good. Use `textLayoutManager` and `textContentStorage` instead.
final class ChatTranscriptTextView: NSTextView, NSTextViewDelegate, NSViewToolTipOwner {
  /// The room either side of the chat.
  static let horizontalMargin: CGFloat = 24
  /// How far in the senders' icons are, which the input under the chat lines your icon up with: the
  /// margin, the padding text has inside its container, which here is the usual, and the icon's
  /// inset.
  static let iconColumnStart = horizontalMargin + NSTextContainer().lineFragmentPadding + ChatMessageRenderer.iconInset

  /// What to highlight in the chat.
  struct Highlights: Equatable {
    var query: String = ""
    var watchWords: [HighlightWord] = []

    var isEmpty: Bool { self.query.isEmpty && self.watchWords.isEmpty }
  }

  var openURLAction: ((URL) -> Void)?
  /// What clicking an image's preview does: open the image in a preview window.
  var openImageAction: ((URL) -> Void)?
  /// What clicking a hotline:// link does, in a few words, for its tooltip, since that depends on
  /// which server this is. Nil if it does nothing.
  var describeHotlineLink: ((URL) -> String?)?
  /// The menu for a link to a file, like the Files list's for the file.
  var fileLinkMenu: ((URL) -> NSMenu?)?
  /// The menu for whoever sent a message, from their name and the icon they had, like the user
  /// list's for them.
  var userMenu: ((_ name: String, _ iconID: UInt?) -> NSMenu?)?

  /// Search matches and watch words to highlight. Takes effect at `updateHighlights()`.
  var highlights = Highlights() {
    didSet {
      if self.highlights != oldValue {
        self.highlightsNeedReset = true
      }
    }
  }

  private let fragments = ChatLayoutFragmentProvider()

  /// The lines between days, and code blocks' languages, in place of the system's tertiary color, as
  /// a server's theme has it.
  var tertiaryColor: NSColor? {
    didSet {
      if self.tertiaryColor != oldValue {
        self.fragments.tertiaryColor = self.tertiaryColor ?? .tertiaryLabelColor
        self.redrawVisibleText()
      }
    }
  }
  private var hoveredLink: NSRange?
  /// The characters whose highlights are up to date.
  private var highlightedCharacters = IndexSet()
  private var highlightsNeedReset = false
  /// Whether what's on screen is being laid out, by NSTextView or here. A scroll then, as the chat
  /// keeps its place while the text grows, isn't the time to lay it out again.
  private var isLayingOutViewport = false
  /// Whether the text view is fitting itself to the text or the view, which can scroll it.
  fileprivate(set) var isFitting = false
  /// Where the chat was when a live resize started, kept for the whole resize, since working it out
  /// again at each step would let it creep.
  fileprivate var liveResizeAnchor: Anchor?
  /// Where the chat was when the width last changed, outside a live resize, kept until NSTextView
  /// has laid the text out at the new width, which moves it.
  fileprivate var widthChangeAnchor: Anchor?
  /// Whether any text is highlighted, so there's something to clear.
  private var hasHighlights = false
  /// Search matches: pale yellow with black text, and in dark mode a tint of yellow with light
  /// yellow text.
  private static let searchBackground = NSColor.highlightBackground(.systemYellow, light: NSColor.systemYellow.withAlphaComponent(0.5))
  private static let searchForeground = NSColor.highlightForeground(.systemYellow, light: .black)
  /// How far past the screen, in characters, text is highlighted ahead of scrolling to it.
  private static let highlightMargin = 2500
  /// What the timestamp tooltips cover, so they're only redone when that changes.
  private var toolTipsRange: NSTextRange?
  /// The tooltips added for the messages on screen, so only those are taken away again.
  private var toolTipTags: [NSView.ToolTipTag] = []
  /// The tooltips over links: each one's link, its text as it's shown, and where it is.
  private(set) var linkToolTips: [NSView.ToolTipTag: (url: URL, text: String, rect: NSRect)] = [:]

  private static let toolTipDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
  }()

  /// Sets the view up for chat. Separate from init so `init(usingTextLayoutManager:)` can be used.
  func configure() {
    self.textLayoutManager?.delegate = self.fragments
    self.isEditable = false
    self.isSelectable = true
    self.isRichText = true
    self.drawsBackground = false
    self.usesFindBar = false
    self.isAutomaticLinkDetectionEnabled = false
    self.textContainerInset = NSSize(width: Self.horizontalMargin, height: 24)
    self.isVerticallyResizable = true
    self.isHorizontallyResizable = false
    self.minSize = .zero
    self.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    self.textContainer?.widthTracksTextView = true
    // Links keep the colors the renderer gave them. The pointer, the underline, and the tooltips
    // are handled here.
    self.linkTextAttributes = [:]
    self.displaysLinkToolTips = false
    self.delegate = self
    self.postsFrameChangedNotifications = true
    // NSTextView sizes the views it draws the text and selection in before laying out what's on
    // screen, which can make it taller, as estimated heights give way to real ones. They stay a
    // step behind until it next lays itself out, and they clip to their bounds, which would cut
    // off the newest messages until then. They never draw outside the text view anyway.
    for subview in self.subviews {
      subview.clipsToBounds = false
    }
  }

  // MARK: Ranges

  /// The TextKit 2 range for a range of characters.
  func textRange(for range: NSRange) -> NSTextRange? {
    guard let contentStorage = self.textContentStorage,
          let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
          let end = contentStorage.location(start, offsetBy: range.length) else {
      return nil
    }
    return NSTextRange(location: start, end: end)
  }

  /// The range of characters for a TextKit 2 range, if it's still in the text.
  func characterRange(for textRange: NSTextRange) -> NSRange? {
    guard let contentStorage = self.textContentStorage, let storage = self.textStorage else {
      return nil
    }
    let start = contentStorage.offset(from: contentStorage.documentRange.location, to: textRange.location)
    let length = contentStorage.offset(from: textRange.location, to: textRange.endLocation)
    guard start != NSNotFound, length != NSNotFound, start >= 0, length >= 0, length <= storage.length - start else {
      return nil
    }
    return NSRange(location: start, length: length)
  }

  /// The layout fragment under a point in the view, which is the message there.
  func layoutFragment(at point: NSPoint) -> NSTextLayoutFragment? {
    let origin = self.textContainerOrigin
    return self.textLayoutManager?.textLayoutFragment(for: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
  }

  // MARK: Highlights

  // Text is searched for highlights once it's on screen or nearly, and only once until the
  // highlights or the text change, so a long chat is as quick to search as a short one.
  //
  // Highlights are rendering attributes, which change how text draws without laying it out again.
  // Text that scrolls into view draws with them, but text already on screen doesn't draw again
  // by itself, so changing them redraws what's on screen.

  /// Applies `highlights` if they've changed, or the text was replaced.
  func updateHighlights() {
    guard self.highlightsNeedReset, let textLayoutManager = self.textLayoutManager else {
      return
    }
    self.highlightsNeedReset = false
    self.highlightedCharacters = IndexSet()
    guard self.hasHighlights || !self.highlights.isEmpty else {
      return
    }

    textLayoutManager.setRenderingAttributes([:], for: textLayoutManager.documentRange)
    self.hasHighlights = false

    // After the text changes, the viewport is out of date until it's laid out.
    self.layOutViewport()
    if !self.highlights.isEmpty, let visible = self.viewportCharacterRange() {
      self.highlight(self.paragraphs(around: visible, margin: Self.highlightMargin))
    }
    self.redrawVisibleText()
  }

  /// After the text is replaced, or changes anywhere but the end, which moves every message in it.
  /// Call `updateHighlights()` next.
  func textWasReplaced() {
    self.highlightsNeedReset = true
    self.liveResizeAnchor = nil
    self.widthChangeAnchor = nil
    self.hideCopyCodeButton()
  }

  /// After text is added to the end. New text draws for the first time with its highlights, so
  /// nothing needs drawing again.
  func textWasAppended(_ range: NSRange) {
    guard !self.highlightsNeedReset, !self.highlights.isEmpty else {
      return
    }
    self.highlight(range)
  }

  /// As the chat scrolls: highlights the text coming up, before it's on screen.
  private func highlightNearScreen() {
    guard !self.highlightsNeedReset, !self.highlights.isEmpty, let visible = self.viewportCharacterRange() else {
      return
    }
    let soon = self.paragraphs(around: visible, margin: Self.highlightMargin / 2)
    guard !self.highlightedCharacters.contains(integersIn: soon.location..<NSMaxRange(soon)) else {
      return
    }

    let wanted = self.paragraphs(around: visible, margin: Self.highlightMargin)
    var redraw = false
    for missing in IndexSet(integersIn: wanted.location..<NSMaxRange(wanted)).subtracting(self.highlightedCharacters).rangeView {
      let range = NSRange(missing)
      self.highlight(range)
      redraw = redraw || NSIntersectionRange(range, visible).length > 0
    }
    if redraw {
      self.redrawVisibleText()
    }
  }

  /// Highlights matches in whole messages in or around a range of characters.
  private func highlight(_ range: NSRange) {
    guard let textLayoutManager = self.textLayoutManager, let storage = self.textStorage else {
      return
    }
    let string = storage.string as NSString
    // Whole messages, so no match is cut in two.
    let range = string.paragraphRange(for: range)
    self.highlightedCharacters.insert(integersIn: range.location..<NSMaxRange(range))

    func mark(_ word: String, background: NSColor, foreground: NSColor, skippingNames: Bool) {
      guard !word.isEmpty else {
        return
      }
      let colors: [NSAttributedString.Key: Any] = [.backgroundColor: background, .foregroundColor: foreground]
      var location = range.location
      while location < NSMaxRange(range) {
        let found = string.range(of: word, options: [.caseInsensitive, .literal], range: NSRange(location: location, length: NSMaxRange(range) - location))
        guard found.location != NSNotFound else {
          break
        }
        // Search doesn't look at the dates on dividers, which show between results only to mark
        // where sessions start, so nothing in them is a match.
        let skipped = storage.attribute(ChatMessageRenderer.dividerKey, at: found.location, effectiveRange: nil) != nil
          || (skippingNames && storage.attribute(ChatMessageRenderer.skipHighlightKey, at: found.location, effectiveRange: nil) != nil)
        if !skipped, let textRange = self.textRange(for: found) {
          textLayoutManager.setRenderingAttributes(colors, for: textRange)
          self.hasHighlights = true
        }
        location = NSMaxRange(found)
      }
    }

    // Watch words first, so search matches win where they overlap.
    for watchWord in self.highlights.watchWords {
      mark(watchWord.word, background: watchWord.nsBackgroundColor, foreground: watchWord.nsForegroundColor, skippingNames: true)
    }
    mark(self.highlights.query, background: Self.searchBackground, foreground: Self.searchForeground, skippingNames: false)
  }

  /// The characters the viewport covers: what's on screen, and a little more that's ready to be.
  private func viewportCharacterRange() -> NSRange? {
    self.textLayoutManager?.textViewportLayoutController.viewportRange.flatMap { self.characterRange(for: $0) }
  }

  /// Whole messages in a range of characters and `margin` more on each side.
  private func paragraphs(around range: NSRange, margin: Int) -> NSRange {
    guard let storage = self.textStorage else {
      return range
    }
    let start = max(0, range.location - margin)
    let end = min(storage.length, NSMaxRange(range) + margin)
    return (storage.string as NSString).paragraphRange(for: NSRange(location: start, length: end - start))
  }

  /// Draws the text on screen again, or just what's in `rect`. Each message draws in a view of
  /// its own inside the text view, and those don't draw again when the text view does.
  private func redrawVisibleText(in rect: NSRect? = nil) {
    func redraw(_ view: NSView) {
      for subview in view.subviews where !(subview is ChatImagePreviewView) {
        if let rect, !subview.convert(subview.bounds, to: self).intersects(rect) {
          continue
        }
        subview.needsDisplay = true
        redraw(subview)
      }
    }
    redraw(self)
  }

  /// Where the message holding a range of characters is drawn.
  private func messageRect(for range: NSRange) -> NSRect? {
    guard let textRange = self.textRange(for: range),
          let fragment = self.textLayoutManager?.textLayoutFragment(for: textRange.location) else {
      return nil
    }
    let origin = self.textContainerOrigin
    return fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
  }

  // MARK: Laying out

  override func layout() {
    let wasLayingOut = self.isLayingOutViewport
    self.isLayingOutViewport = true
    super.layout()
    self.isLayingOutViewport = wasLayingOut
    // NSTextView sizes itself and moves what's on screen as it lays out at a new width, so while
    // the width is changing, put the chat back where the change found it.
    if let anchor = self.liveResizeAnchor ?? self.widthChangeAnchor {
      self.keep(anchor)
      if !self.inLiveResize {
        self.widthChangeAnchor = nil
      }
    }
    // Laying out what's on screen can make the text taller, as estimated heights give way to real
    // ones, and the chat scrolls to keep its place, past what was laid out.
    self.layOutViewportIfScrolledPast()
    // And move the copy button with the code block it's over.
    if self.copyCodeButton?.isShowing == true {
      self.updateCopyCodeButtonForPointer()
    }
  }

  /// Lays out what's on screen, again if that makes the text taller and the chat scrolls past it.
  private func layOutViewport() {
    guard !self.isLayingOutViewport, let controller = self.textLayoutManager?.textViewportLayoutController else {
      return
    }
    self.isLayingOutViewport = true
    defer { self.isLayingOutViewport = false }
    controller.layoutViewport()
    for _ in 0..<4 where !self.isViewportLaidOut() {
      controller.layoutViewport()
    }
  }

  /// The viewport is laid out on the next pass after scrolling, which is too late for a big jump,
  /// like to the top of the chat: what's there would draw before it's highlighted. And when the
  /// chat scrolls to keep its place as the text grows, which happens while it's being laid out,
  /// nothing lays it out again. So when the screen has moved past what's laid out, lay it out now.
  func layOutViewportIfScrolledPast() {
    if !self.isLayingOutViewport && !self.isViewportLaidOut() {
      self.layOutViewport()
    }
  }

  /// Whether what's laid out covers what's on screen.
  private func isViewportLaidOut() -> Bool {
    guard let textLayoutManager = self.textLayoutManager,
          let viewport = textLayoutManager.textViewportLayoutController.viewportRange,
          let first = textLayoutManager.textLayoutFragment(for: viewport.location),
          let lastLocation = textLayoutManager.location(viewport.endLocation, offsetBy: -1),
          let last = textLayoutManager.textLayoutFragment(for: lastLocation) else {
      return false
    }
    // At the start or end of the chat, what's laid out reaches the edge, past the inset.
    let laidOut = first.layoutFragmentFrame.union(last.layoutFragmentFrame).offsetBy(dx: 0, dy: self.textContainerOrigin.y)
    let document = textLayoutManager.documentRange
    let top = viewport.location.compare(document.location) == .orderedSame ? -CGFloat.greatestFiniteMagnitude : laidOut.minY
    let bottom = viewport.endLocation.compare(document.endLocation) == .orderedSame ? CGFloat.greatestFiniteMagnitude : laidOut.maxY
    let visible = self.visibleRect
    return top <= visible.minY && bottom >= visible.maxY
  }

  // MARK: Links

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
    guard let url else {
      return false
    }

    // Through SwiftUI's openURL, so hotline:// links stay in the app.
    if let openURL = self.openURLAction {
      openURL(url)
    }
    else {
      NSWorkspace.shared.open(url)
    }
    return true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in self.trackingAreas where area.owner === self && area.userInfo?["chatHover"] != nil {
      self.removeTrackingArea(area)
    }
    self.addTrackingArea(NSTrackingArea(
      rect: self.bounds,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: ["chatHover": true]
    ))
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    let point = self.convert(event.locationInWindow, from: nil)
    self.updateHoveredLink(at: point)
    self.updateCopyCodeButton(at: point)
    self.cursor(at: point)?.set()
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    self.clearHoveredLink()
    self.hideCopyCodeButton()
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let point = self.convert(event.locationInWindow, from: nil)
    if let sender = self.sender(at: point), let menu = self.userMenu?(sender.name, sender.iconID) {
      return menu
    }
    if let link = self.fileLink(at: point), let menu = self.fileLinkMenu?(link.url) {
      return menu
    }
    let menu = super.menu(for: event)
    // Over any other link, macOS's own menu has Open Link and Copy Link. For a link to an image,
    // Open Image comes first.
    if let menu, menu.items.contains(where: { $0.action == NSSelectorFromString("copyLink:") }),
       let url = self.link(near: point), ChatImagePreview.canPreview(url), let openImage = self.openImageAction {
      menu.insertItem(ChatMenuItem("Open Image", systemImage: "photo") {
        openImage(url)
      }, at: 0)
      menu.insertItem(.separator(), at: 1)
    }
    return menu
  }

  /// What can be done with a link to an image, for its preview's menu: open the image in a preview
  /// window, or the link the way a click on it does, or copy it, as macOS's menu for a link has.
  func linkMenuItems(for url: URL) -> [NSMenuItem] {
    var items: [NSMenuItem] = []
    if let openImage = self.openImageAction {
      items.append(ChatMenuItem("Open Image", systemImage: "photo") {
        openImage(url)
      })
    }
    let open = self.openURLAction
    items.append(ChatMenuItem("Open Link", systemImage: "arrow.up.forward.app") {
      if let open {
        open(url)
      }
      else {
        NSWorkspace.shared.open(url)
      }
    })
    items.append(ChatMenuItem("Copy Link", systemImage: "link") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
    })
    return items
  }

  /// The link at a point, found the way macOS's menu for a link finds it: from where an insertion
  /// point there would go, the character after it, or before it, at the end of a link.
  private func link(near point: NSPoint) -> URL? {
    guard let storage = self.textStorage else {
      return nil
    }
    let index = self.characterIndexForInsertion(at: point)
    for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
      let value = storage.attribute(.link, at: candidate, effectiveRange: nil)
      if let url = (value as? URL) ?? (value as? String).flatMap({ URL(string: $0) }) {
        return url
      }
    }
    return nil
  }

  /// A click on someone's name or icon, or on a link to a file, opens its menu under it, like a
  /// pull-down button.
  override func mouseDown(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    if !event.modifierFlags.contains(.control) {
      if let sender = self.sender(at: point), let menu = self.userMenu?(sender.name, sender.iconID) {
        self.popUp(menu, under: sender.frame)
        return
      }
      if let link = self.fileLink(at: point), let menu = self.fileLinkMenu?(link.url) {
        self.popUp(menu, under: link.frame)
        return
      }
    }
    super.mouseDown(with: event)
  }

  private func popUp(_ menu: NSMenu, under frame: NSRect) {
    menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.maxY + 2), in: self)
    // The pointer can be somewhere else by the time the menu closes.
    if let window = self.window {
      self.updateHoveredLink(at: self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
  }

  /// Who sent the message whose name or icon is under a point, the icon they had then, and where
  /// the name or icon is in the view.
  private func sender(at point: NSPoint) -> (name: String, iconID: UInt?, frame: NSRect)? {
    guard let storage = self.textStorage,
          let fragment = self.layoutFragment(at: point),
          let message = self.characterRange(for: fragment.rangeInElement) else {
      return nil
    }
    var nameRange = NSRange()
    if let index = self.character(at: point), NSLocationInRange(index, message),
       let name = storage.attribute(ChatMessageRenderer.userNameKey, at: index, longestEffectiveRange: &nameRange, in: message) as? String {
      let iconID = (storage.attribute(ChatMessageRenderer.iconIDKey, at: index, effectiveRange: nil) as? NSNumber)?.uintValue
      return (name, iconID, self.frame(of: nameRange, at: point))
    }
    // The icon isn't text, so it's found by where the message draws it.
    guard let fragment = fragment as? ChatLayoutFragment,
          let icon = fragment.iconFrame?.offsetBy(dx: fragment.layoutFragmentFrame.minX + self.textContainerOrigin.x, dy: fragment.layoutFragmentFrame.minY + self.textContainerOrigin.y),
          icon.contains(point),
          let text = (fragment.textElement as? NSTextParagraph)?.attributedString, text.length > 0,
          let name = text.attribute(ChatMessageRenderer.senderNameKey, at: 0, effectiveRange: nil) as? String else {
      return nil
    }
    return (name, (text.attribute(ChatMessageRenderer.iconIDKey, at: 0, effectiveRange: nil) as? NSNumber)?.uintValue, icon)
  }

  /// The link to a file under a point, and where it is in the view on the line under the point.
  private func fileLink(at point: NSPoint) -> (url: URL, frame: NSRect)? {
    guard let storage = self.textStorage,
          let fragment = self.layoutFragment(at: point),
          let message = self.characterRange(for: fragment.rangeInElement),
          let index = self.character(at: point), NSLocationInRange(index, message) else {
      return nil
    }
    var link = NSRange()
    guard let url = storage.attribute(ChatMessageRenderer.fileLinkKey, at: index, longestEffectiveRange: &link, in: message) as? URL else {
      return nil
    }
    return (url, self.frame(of: link, at: point))
  }

  /// Where some characters are in the view, on the line under a point, for those that wrap.
  private func frame(of range: NSRange, at point: NSPoint) -> NSRect {
    var frame = NSRect(origin: point, size: .zero)
    guard let textRange = self.textRange(for: range) else {
      return frame
    }
    self.textLayoutManager?.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, segment, _, _ in
      let rect = segment.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
      if point.y >= rect.minY, point.y <= rect.maxY {
        frame = rect
        return false
      }
      return true
    }
    return frame
  }

  override func cursorUpdate(with event: NSEvent) {
    if let cursor = self.cursor(at: self.convert(event.locationInWindow, from: nil)) {
      cursor.set()
    }
    else {
      super.cursorUpdate(with: event)
    }
  }

  /// The cursor over what isn't text, which NSTextView would show its text cursor over too: the
  /// arrow over the copy button, and the hand over what a click opens, a link, someone's name or
  /// icon, or an image preview.
  private func cursor(at point: NSPoint) -> NSCursor? {
    if let button = self.copyCodeButton, button.isShowing, button.frame.contains(point) {
      return .arrow
    }
    if self.hoveredLink != nil || (self.userMenu != nil && self.sender(at: point) != nil) {
      return .pointingHand
    }
    if let superview = self.superview, var view = self.hitTest(superview.convert(point, from: self)) {
      while view !== self {
        if view is ChatImagePreviewView {
          return .pointingHand
        }
        guard let parent = view.superview else {
          break
        }
        view = parent
      }
    }
    return nil
  }

  /// Underlines the link under the pointer, the way links on the web do, or someone's name, which
  /// a click opens a menu for.
  private func updateHoveredLink(at point: NSPoint) {
    guard let storage = self.textStorage,
          let fragment = self.layoutFragment(at: point),
          fragment.layoutFragmentFrame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y).contains(point) else {
      self.clearHoveredLink()
      return
    }

    // All of the link, even where its formatting changes partway.
    let message = self.characterRange(for: fragment.rangeInElement) ?? NSRange(location: 0, length: storage.length)
    let index = self.character(at: point) ?? NSNotFound
    var linkRange = NSRange()
    let link = NSLocationInRange(index, message)
      ? storage.attribute(.link, at: index, longestEffectiveRange: &linkRange, in: message)
        ?? (self.userMenu == nil ? nil : storage.attribute(ChatMessageRenderer.userNameKey, at: index, longestEffectiveRange: &linkRange, in: message))
      : nil
    guard link != nil else {
      self.clearHoveredLink()
      return
    }

    if self.hoveredLink != linkRange {
      self.clearHoveredLink()
      self.hoveredLink = linkRange
      self.fragments.hoveredLink = linkRange
      self.redrawVisibleText(in: self.messageRect(for: linkRange))
    }
    NSCursor.pointingHand.set()
  }

  /// The character under a point, if the point is over one. The nearest place between two
  /// characters, which is what `characterIndexForInsertion(at:)` gives, can be the next one.
  private func character(at point: NSPoint) -> Int? {
    guard let window = self.window, let storage = self.textStorage else {
      return nil
    }
    let screenPoint = window.convertPoint(toScreen: self.convert(point, to: nil))
    let index = self.characterIndex(for: screenPoint)
    guard index != NSNotFound, index < storage.length else {
      return nil
    }
    // Past the end of a line, the last character on it is still the nearest.
    let rect = self.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
    return rect.insetBy(dx: -1, dy: -1).contains(screenPoint) ? index : nil
  }

  func clearHoveredLink() {
    guard let range = self.hoveredLink else {
      return
    }
    self.hoveredLink = nil
    self.fragments.hoveredLink = nil
    if let storage = self.textStorage, NSMaxRange(range) <= storage.length {
      self.redrawVisibleText(in: self.messageRect(for: range))
    }
  }

  // MARK: Scrolling

  /// After the chat scrolls.
  func viewDidScroll() {
    // Scrolling to keep up with the text's height happens while it's being laid out, which would
    // be the wrong time to lay it out again. Fitting does that when it's done.
    if !self.isFitting {
      self.layOutViewportIfScrolledPast()
    }
    self.updateToolTips()
    self.highlightNearScreen()
    // What's under the pointer has moved.
    self.updateCopyCodeButtonForPointer()
  }

  // MARK: Copying Code

  /// The button over the code block under the pointer, which copies its code.
  private var copyCodeButton: ChatCopyCodeButton?
  /// The code block the copy button is over, in characters.
  private var copyCodeRange: NSRange?
  /// The code block last copied, which the button stays away from until the pointer leaves it.
  private var copiedCodeRange: NSRange?

  /// Shows the copy button in the top right corner of the code block under `point`, or as near it
  /// as can be seen, and hides it anywhere else. After a copy, it stays away from that block until
  /// the pointer has left it.
  private func updateCopyCodeButton(at point: NSPoint) {
    guard let fragment = self.layoutFragment(at: point) as? ChatLayoutFragment,
          let bounds = fragment.codeBlockBounds,
          let range = self.characterRange(for: fragment.rangeInElement) else {
      self.hideCopyCodeButton()
      return
    }
    let origin = self.textContainerOrigin
    let block = bounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + origin.x, dy: fragment.layoutFragmentFrame.minY + origin.y)
    guard block.contains(point) else {
      self.hideCopyCodeButton()
      return
    }
    guard range != self.copiedCodeRange else {
      return
    }
    self.copiedCodeRange = nil

    let button = self.copyCodeButton ?? {
      let button = ChatCopyCodeButton(target: self, action: #selector(self.copyCode(_:)))
      self.addSubview(button)
      self.copyCodeButton = button
      return button
    }()
    guard !button.isConfirming else {
      return
    }
    let size = ChatCopyCodeButton.size
    let inset: CGFloat = 5
    let top = min(max(block.minY, self.visibleTop) + inset, block.maxY - size - inset)
    button.place(at: NSPoint(x: block.maxX - inset, y: top))
    self.copyCodeRange = range
    button.show()
  }

  /// After the text under the pointer moves without the pointer moving.
  private func updateCopyCodeButtonForPointer() {
    guard let window = self.window, window.isKeyWindow else {
      return
    }
    let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    if self.visibleRect.contains(point) {
      self.updateCopyCodeButton(at: point)
    }
    else {
      self.hideCopyCodeButton()
    }
  }

  func hideCopyCodeButton() {
    self.copyCodeButton?.hide()
    self.copyCodeRange = nil
    self.copiedCodeRange = nil
  }

  /// The top of what can be seen of the text, below the toolbar.
  private var visibleTop: CGFloat {
    guard let window = self.window else {
      return self.visibleRect.minY
    }
    return max(self.visibleRect.minY, self.convert(NSPoint(x: 0, y: window.contentLayoutRect.maxY), from: nil).y)
  }

  /// Copies the code in the block under the pointer, with real line breaks.
  @objc private func copyCode(_ sender: Any?) {
    guard let range = self.copyCodeRange, let storage = self.textStorage, NSMaxRange(range) <= storage.length else {
      return
    }
    var code = (storage.string as NSString).substring(with: range)
    if code.hasSuffix("\n") {
      code.removeLast()
    }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(code.replacingOccurrences(of: "\u{2028}", with: "\n"), forType: .string)
    self.copiedCodeRange = range
    self.copyCodeButton?.confirmCopy()
  }

  // MARK: Tooltips

  /// Tooltips over the messages on screen: what a link does over a link, and when the message was
  /// sent everywhere else. They tile each message without overlapping, so moving from one to the
  /// next changes which shows.
  func updateToolTips() {
    guard let textLayoutManager = self.textLayoutManager,
          let viewport = textLayoutManager.textViewportLayoutController.viewportRange else {
      return
    }
    if let toolTipsRange = self.toolTipsRange, toolTipsRange.isEqual(to: viewport) {
      return
    }
    self.toolTipsRange = viewport

    for tag in self.toolTipTags {
      self.removeToolTip(tag)
    }
    self.toolTipTags = []
    self.linkToolTips = [:]
    textLayoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
      guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
        return false
      }
      self.addToolTips(for: fragment)
      return true
    }
  }

  private func addToolTips(for fragment: NSTextLayoutFragment) {
    let origin = self.textContainerOrigin
    let message = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
    let lines = fragment.textLineFragments
    guard let paragraph = fragment.textElement as? NSTextParagraph, !lines.isEmpty else {
      self.addToolTip(message, for: nil)
      return
    }

    let text = paragraph.attributedString
    var links: [(range: NSRange, url: URL)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      if let url = (value as? URL) ?? (value as? String).flatMap({ URL(string: $0) }) {
        links.append((range, url))
      }
    }
    guard !links.isEmpty else {
      self.addToolTip(message, for: nil)
      return
    }

    // Line by line, each from halfway to the line above to halfway to the one below, with the
    // links on it and the time in the gaps around them.
    for (index, line) in lines.enumerated() {
      let bounds = line.typographicBounds.offsetBy(dx: message.minX, dy: message.minY)
      let top = index == 0 ? message.minY : (lines[index - 1].typographicBounds.maxY + message.minY + bounds.minY) / 2
      let bottom = index == lines.count - 1 ? message.maxY : (bounds.maxY + lines[index + 1].typographicBounds.minY + message.minY) / 2
      var x = message.minX
      let onLine = links
        .map { (range: NSIntersectionRange($0.range, line.characterRange), whole: $0.range, url: $0.url) }
        .filter { $0.range.length > 0 }
        .sorted { $0.range.location < $1.range.location }
      for link in onLine {
        let left = bounds.minX + line.locationForCharacter(at: link.range.location).x
        let right = bounds.minX + line.locationForCharacter(at: NSMaxRange(link.range)).x
        let shown = (text.string as NSString).substring(with: link.whole)
        self.addToolTip(NSRect(x: x, y: top, width: left - x, height: bottom - top), for: nil)
        self.addToolTip(NSRect(x: left, y: top, width: right - left, height: bottom - top), for: (link.url, shown))
        x = right
      }
      self.addToolTip(NSRect(x: x, y: top, width: message.maxX - x, height: bottom - top), for: nil)
    }
  }

  /// A tooltip for a link, shown as `link.text`, or saying when the message under it was sent.
  private func addToolTip(_ rect: NSRect, for link: (url: URL, text: String)?) {
    guard rect.width > 0, rect.height > 0 else {
      return
    }
    let tag = self.addToolTip(rect, owner: self, userData: nil)
    self.toolTipTags.append(tag)
    if let link {
      self.linkToolTips[tag] = (link.url, link.text, rect)
    }
  }

  /// What clicking a link shown as `text` does, or nil if nothing.
  func toolTipText(for url: URL, shownAs text: String) -> String? {
    // A file shows only its name, so the whole link is what's worth knowing.
    if ChatMessageRenderer.fileName(ofHotlineLink: url) != nil {
      return url.absoluteString.removingPercentEncoding ?? url.absoluteString
    }
    if url.scheme?.lowercased() == "hotline" {
      return self.describeHotlineLink.map { $0(url) } ?? "Open in Hotline"
    }
    return Self.openLinkText(for: url, shownAs: text)
  }

  /// "Open in Safari", with the browser that opens it, and where it goes when the link's text
  /// doesn't show that: "Open example.com in Safari".
  static func openLinkText(for url: URL, shownAs text: String) -> String {
    let app = NSWorkspace.shared.urlForApplication(toOpen: url).map { appURL -> String in
      let name = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
      return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
    var host = url.host(percentEncoded: false)
    if let shown = host, text.localizedCaseInsensitiveContains(shown.hasPrefix("www.") ? String(shown.dropFirst(4)) : shown) {
      host = nil
    }
    switch (host, app) {
    case let (host?, app?): return "Open \(host) in \(app)"
    case let (nil, app?): return "Open in \(app)"
    case let (host?, nil): return "Open \(host)"
    case (nil, nil): return "Open Link"
    }
  }

  /// Forgets which messages have tooltips, after the text changes underneath them.
  func invalidateToolTips() {
    self.toolTipsRange = nil
  }

  func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
    if let link = self.linkToolTips[tag], let text = self.toolTipText(for: link.url, shownAs: link.text) {
      return text
    }
    guard let storage = self.textStorage,
          let contentStorage = self.textContentStorage,
          let fragment = self.layoutFragment(at: point) else {
      return ""
    }
    let index = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
    guard index < storage.length,
          let date = storage.attribute(ChatMessageRenderer.messageDateKey, at: index, effectiveRange: nil) as? Date else {
      return ""
    }
    return Self.toolTipDateFormatter.string(from: date)
  }

  // MARK: Copying

  // Plain text gets real line breaks, the links to files shown by their names and long links shown
  // shorter as they were written, and none of the stand-in characters for icons and previews.
  override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
    let wrote = super.writeSelection(to: pboard, types: types)
    if wrote, pboard.string(forType: .string) != nil, let storage = self.textStorage {
      let selected = self.selectedRanges
        .map(\.rangeValue)
        .filter { $0.length > 0 && NSMaxRange($0) <= storage.length }
        .map { Self.plainText(storage.attributedSubstring(from: $0)) }
      pboard.setString(selected.joined(separator: "\n"), forType: .string)
    }
    return wrote
  }

  private static func plainText(_ text: NSAttributedString) -> String {
    var plain = ""
    text.enumerateAttribute(ChatMessageRenderer.fileLinkKey, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      if let url = value as? URL {
        plain += url.absoluteString
        return
      }
      text.enumerateAttribute(ChatMessageRenderer.fullLinkKey, in: range) { written, part, _ in
        plain += (written as? String) ?? (text.string as NSString).substring(with: part)
      }
    }
    return plain
      .replacingOccurrences(of: "\u{FFFC}", with: "")
      .replacingOccurrences(of: "\u{2028}", with: "\n")
  }
}

// MARK: - Copy Code Button

/// The round button over a code block that copies its code. It grows in when the pointer comes
/// over the block and shrinks away when it leaves, and after a copy it widens to say so, then goes
/// until the pointer comes back to the block. Glass where the system has it.
final class ChatCopyCodeButton: NSButton {
  static let size: CGFloat = 26

  private static let copyImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy Code")
  private static let copiedImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")

  /// Whether it's showing, or on its way to.
  private(set) var isShowing = false
  /// Whether it's saying the code was copied, which it finishes before going.
  private(set) var isConfirming = false
  /// Counts the animations started, so one that's been overtaken doesn't finish what it started.
  private var animationCount = 0
  /// Where its top right corner goes. It grows to the left from there.
  private var corner = NSPoint.zero

  init(target: AnyObject, action: Selector) {
    super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
    self.target = target
    self.action = action
    self.wantsLayer = true
    if #available(macOS 26.0, *) {
      self.isBordered = true
      self.bezelStyle = .glass
      self.borderShape = .circle
    }
    else {
      // A round tile of its own, so code running under it doesn't show through.
      self.isBordered = false
      self.layer?.cornerRadius = Self.size / 2
      self.layer?.borderWidth = 1
      self.updateTile()
    }
    self.imagePosition = .imageOnly
    self.imageScaling = .scaleNone
    self.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    self.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    self.toolTip = "Copy Code"
    self.setAccessibilityLabel("Copy Code")
    self.isHidden = true
    self.alphaValue = 0
    self.showCopy()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Puts its top right corner at `corner`, in its superview.
  func place(at corner: NSPoint) {
    self.corner = corner
    self.layOut(width: self.frame.width)
  }

  private func layOut(width: CGFloat) {
    let frame = NSRect(x: self.corner.x - width, y: self.corner.y, width: width, height: Self.size)
    self.frame = self.superview?.backingAlignedRect(frame, options: .alignAllEdgesNearest) ?? frame
  }

  private func showCopy() {
    self.title = ""
    self.image = Self.copyImage
    self.imagePosition = .imageOnly
    self.contentTintColor = .secondaryLabelColor
    if #available(macOS 26.0, *) {
      self.borderShape = .circle
    }
    self.layOut(width: Self.size)
  }

  /// Grows in, unless it's already there.
  func show() {
    guard !self.isShowing else {
      return
    }
    self.isShowing = true
    self.animationCount += 1
    self.isHidden = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      self.animator().alphaValue = 1
    }
    self.animateScale(from: 0.6, to: 1, duration: 0.22, timing: CAMediaTimingFunction(controlPoints: 0.2, 1.4, 0.4, 1))
  }

  /// Shrinks away, unless it's saying the code was copied, which goes by itself.
  func hide() {
    guard self.isShowing, !self.isConfirming else {
      return
    }
    self.dismiss()
  }

  private func dismiss() {
    self.isShowing = false
    self.animationCount += 1
    let animation = self.animationCount
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      self.animator().alphaValue = 0
    } completionHandler: {
      guard self.animationCount == animation else {
        return
      }
      self.isHidden = true
      self.isConfirming = false
      self.showCopy()
    }
    self.animateScale(from: 1, to: 0.6, duration: 0.14, timing: CAMediaTimingFunction(name: .easeIn))
  }

  /// Widens to say the code was copied, then goes after a moment.
  func confirmCopy() {
    self.isConfirming = true
    self.animationCount += 1
    let animation = self.animationCount
    self.title = "Copied"
    self.image = Self.copiedImage
    self.imagePosition = .imageLeading
    self.contentTintColor = .systemGreen
    if #available(macOS 26.0, *) {
      self.borderShape = .capsule
    }
    let width = max(Self.size, ceil(self.fittingSize.width) + 6)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      context.allowsImplicitAnimation = true
      self.animator().frame = NSRect(x: self.corner.x - width, y: self.corner.y, width: width, height: Self.size)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      if let self, self.animationCount == animation {
        self.dismiss()
      }
    }
  }

  /// Scales the button about its middle, from one size to another, ending at its own.
  private func animateScale(from: CGFloat, to: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
    guard let layer = self.layer else {
      return
    }
    func scaled(_ scale: CGFloat) -> CATransform3D {
      let middle = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
      return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-middle.x, -middle.y, 0), CATransform3DMakeScale(scale, scale, 1)), CATransform3DMakeTranslation(middle.x, middle.y, 0))
    }
    let animation = CABasicAnimation(keyPath: "transform")
    animation.fromValue = scaled(from)
    animation.toValue = scaled(to)
    animation.duration = duration
    animation.timingFunction = timing
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = to != 1
    layer.add(animation, forKey: "scale")
  }

  /// Without glass, the tile's colors, for light or dark.
  private func updateTile() {
    guard #unavailable(macOS 26.0) else {
      return
    }
    self.effectiveAppearance.performAsCurrentDrawingAppearance {
      self.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
      self.layer?.borderColor = NSColor.separatorColor.cgColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    self.updateTile()
  }
}

// MARK: - Scroll View

/// The chat's scroll view, with the text view its document. Its top inset leaves room for the
/// toolbar over the top of the chat, and, while the chat is shorter than the view, for all the
/// space above it, so it sits at the bottom, the way a chat should look. The bottom inset SwiftUI
/// gives it keeps the chat above the input bar.
final class ChatTranscriptScrollView: NSScrollView {
  /// The top inset, which the text view works out, in place of the one SwiftUI gives it.
  var topInset: CGFloat = 0 {
    didSet {
      if abs(self.topInset - oldValue) > 0.25 {
        self.tile()
      }
    }
  }

  override func tile() {
    let textView = self.documentView as? ChatTranscriptTextView
    let wasAtBottom = textView?.isAtBottom ?? false
    var insets = self.contentInsets
    if insets.top != self.topInset {
      insets.top = self.topInset
      self.contentInsets = insets
    }
    super.tile()
    // At the bottom, the newest message stays there as the view or its insets change.
    if wasAtBottom, let textView, !textView.isFitting {
      textView.scrollToBottom()
    }
  }
}

// MARK: - Fitting and Scrolling

// The text view is the scroll view's document, so that NSTextView keeps what's on screen still as
// messages coming on screen get their real heights in place of TextKit 2's estimates. Inside
// another view, it doesn't, and the chat jumps as it scrolls back.

extension ChatTranscriptTextView {
  /// Where the chat is scrolled to, by its messages, since their positions change when the text is
  /// laid out again at another width, or when old messages are removed from the top.
  enum Anchor {
    /// At the newest message, which is also where a chat too short to scroll stays.
    case bottom
    /// At the oldest message.
    case top
    /// A message's top, `distance` below the top of what can be seen of the chat, below the
    /// toolbar, `offset` characters into the text.
    case message(offset: Int, distance: CGFloat)
  }

  fileprivate var clipView: NSClipView? {
    self.superview as? NSClipView
  }

  /// How much of the top of the chat the toolbar covers.
  fileprivate var toolbarHeight: CGFloat {
    guard let scrollView = self.enclosingScrollView, let window = scrollView.window else {
      return 0
    }
    let scrollViewRect = scrollView.convert(scrollView.bounds, to: nil)
    return max(0, scrollViewRect.maxY - window.contentLayoutRect.maxY)
  }

  /// The top of what can be seen of the chat, below the toolbar, in the text container's
  /// coordinates.
  fileprivate func visibleTopOfText(in clipView: NSClipView) -> CGFloat {
    clipView.bounds.minY + self.toolbarHeight - self.textContainerOrigin.y
  }

  /// How far the chat scrolls, from showing its top to showing its bottom, insets included.
  fileprivate func scrollRange(in clipView: NSClipView) -> ClosedRange<CGFloat> {
    let insets = self.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
    let top = -insets.top
    return top...max(top, self.frame.height + insets.bottom - clipView.bounds.height)
  }

  var isAtBottom: Bool {
    guard let clipView = self.clipView else {
      return true
    }
    return clipView.bounds.minY >= self.scrollRange(in: clipView).upperBound - 1
  }

  // MARK: Fitting

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if let clipView = self.clipView {
      clipView.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(self, selector: #selector(self.clipViewResized), name: NSView.frameDidChangeNotification, object: clipView)
    }
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if let clipView = self.clipView {
      NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: clipView)
    }
    super.viewWillMove(toSuperview: newSuperview)
  }

  /// Right away, rather than in the next layout pass: in SwiftUI, the window can show the view at
  /// its new size before then, with the text still laid out for the old one.
  @objc fileprivate func clipViewResized() {
    guard let clipView = self.clipView else {
      return
    }
    if abs(self.frame.width - clipView.bounds.width) > 0.5 {
      self.setFrameSize(NSSize(width: clipView.bounds.width, height: self.frame.height))
    }
    else {
      // The scroll view keeps the chat at the bottom, if it was, as its size changes.
      self.fit(keepingBottom: false)
    }
  }

  override func setFrameSize(_ newSize: NSSize) {
    guard !self.isFitting, self.clipView != nil else {
      super.setFrameSize(newSize)
      return
    }
    if abs(newSize.width - self.frame.width) > 0.5 {
      // From before, while it's laid out at the old width.
      let anchor = self.liveResizeAnchor ?? self.anchor()
      if !self.inLiveResize {
        self.widthChangeAnchor = anchor
      }
      self.isFitting = true
      super.setFrameSize(newSize)
      self.resizeText(keeping: anchor)
      self.isFitting = false
      self.layOutViewportIfScrolledPast()
    }
    else if let anchor = self.liveResizeAnchor ?? self.widthChangeAnchor {
      super.setFrameSize(newSize)
      self.keep(anchor)
    }
    else {
      // TextKit 2 corrects its estimate of the text's height as it lays more of it out, which it
      // does right after the text changes and as the chat scrolls. Fit to it straight away, before
      // anything draws, so the chat stays put at the bottom instead of jumping for a frame or two.
      let wasAtBottom = self.isAtBottom
      super.setFrameSize(newSize)
      self.fit(keepingBottom: wasAtBottom)
    }
  }

  /// Leaves room at the top for the toolbar, or, while the chat is shorter than the view, for all
  /// the space above it, and keeps the chat at the bottom if it was there.
  func fit(keepingBottom: Bool) {
    guard !self.isFitting, self.clipView != nil else {
      return
    }
    self.isFitting = true
    defer {
      self.isFitting = false
      // Keeping up with the text can scroll the chat past what's laid out.
      self.layOutViewportIfScrolledPast()
    }
    self.fitInsets()
    if keepingBottom {
      self.scrollToBottom()
    }
  }

  /// Puts the chat back where an anchor says, with room above it.
  private func keep(_ anchor: Anchor) {
    guard !self.isFitting else {
      return
    }
    self.isFitting = true
    self.fitInsets()
    self.scroll(to: anchor)
    self.isFitting = false
  }

  // MARK: Resizing

  override func viewWillStartLiveResize() {
    super.viewWillStartLiveResize()
    self.liveResizeAnchor = self.anchor()
    // The scroller shows TextKit 2's estimate of how tall the chat is, since only what's on screen
    // is laid out. Each step of a resize estimates it again, at the new width, so the scroller
    // would change size and jump around while the chat stays put.
    self.enclosingScrollView?.verticalScroller?.alphaValue = 0
  }

  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()
    // NSTextView finishes the resize in its next layout pass, which keeps the chat in place too.
    self.widthChangeAnchor = self.liveResizeAnchor
    self.liveResizeAnchor = nil
    self.enclosingScrollView?.verticalScroller?.alphaValue = 1
  }

  /// Lays the text out at a new width without the chat moving: at the bottom, the newest message
  /// stays at the bottom, at the top, the oldest stays at the top, and in between, the message at
  /// the top of the view stays where it is.
  private func resizeText(keeping anchor: Anchor) {
    // During a live resize, NSTextView keeps its text container at the width the resize started
    // at, so the text wouldn't rewrap until it was over, and then all at once. Keep it in step.
    if let container = self.textContainer {
      let containerWidth = max(0, self.frame.width - 2 * self.textContainerInset.width)
      if abs(container.size.width - containerWidth) > 0.5 {
        container.size = NSSize(width: containerWidth, height: container.size.height)
      }
    }

    // The text's height is only known as it's laid out, and laying out what comes on screen makes
    // the estimate for the rest better, so this settles over a pass or two, all before it draws.
    guard let textLayoutManager = self.textLayoutManager else {
      return
    }
    self.layOut(around: anchor)
    // And the last message, without which the text's height after a new width is only what's laid
    // out, as if the rest weren't there.
    textLayoutManager.ensureLayout(for: NSTextRange(location: textLayoutManager.documentRange.endLocation))
    for _ in 0..<8 {
      // Over a whole pass, since scrolling into place can make NSTextView lay out more of the
      // text, and resize, before the viewport is laid out here.
      let height = self.frame.height
      self.matchTextHeight()
      self.fitInsets()
      self.scroll(to: anchor)
      textLayoutManager.textViewportLayoutController.layoutViewport()
      self.matchTextHeight()
      if abs(self.frame.height - height) < 0.5 {
        break
      }
    }
    self.fitInsets()
    self.scroll(to: anchor)
  }

  /// Leaves room at the top for the toolbar, or for all the space above a chat shorter than the
  /// view.
  private func fitInsets() {
    guard let clipView = self.clipView, let scrollView = self.enclosingScrollView as? ChatTranscriptScrollView else {
      return
    }
    // NSTextView makes itself at least as tall as the view when the text changes, so a chat
    // shorter than that, like a search that finds only a few messages, would sit at the top. It
    // gets the text's own height instead, with the room above it inset.
    if let height = self.textHeight, height < clipView.bounds.height, self.frame.height > height + 0.5 {
      super.setFrameSize(NSSize(width: self.frame.width, height: height))
    }
    let toolbarRoom = max(0, self.toolbarHeight - self.textContainerInset.height)
    scrollView.topInset = max(toolbarRoom, clipView.bounds.height - scrollView.contentInsets.bottom - self.frame.height)
  }

  /// Sets the text view's height to the text's, which NSTextView doesn't do during a live resize.
  private func matchTextHeight() {
    guard let height = self.textHeight else {
      return
    }
    if abs(self.frame.height - height) > 0.1 {
      super.setFrameSize(NSSize(width: self.frame.width, height: height))
    }
  }

  /// How tall the text is, insets and all. On whole pixels, as NSTextView sizes it, or the bottom
  /// of the chat would move by part of one as the two take turns.
  private var textHeight: CGFloat? {
    guard let textLayoutManager = self.textLayoutManager else {
      return nil
    }
    let scale = self.window?.backingScaleFactor ?? 2
    return ((textLayoutManager.usageBoundsForTextContainer.height + 2 * self.textContainerInset.height) * scale).rounded(.up) / scale
  }

  // MARK: Anchoring

  /// Where the chat is scrolled to now.
  func anchor() -> Anchor {
    guard let clipView = self.clipView, !self.isAtBottom,
          let textLayoutManager = self.textLayoutManager,
          let contentStorage = self.textContentStorage else {
      return .bottom
    }
    if clipView.bounds.minY <= self.scrollRange(in: clipView).lowerBound + 1 {
      return .top
    }
    let visibleTop = self.visibleTopOfText(in: clipView)
    guard var fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visibleTop))) else {
      return .bottom
    }
    // The first message that starts in view, rather than one mostly scrolled past, whose rewrapping
    // would move everything below it.
    if fragment.layoutFragmentFrame.minY < visibleTop - 0.5,
       let next = textLayoutManager.textLayoutFragment(for: fragment.rangeInElement.endLocation),
       next !== fragment,
       next.layoutFragmentFrame.minY < visibleTop + clipView.bounds.height - self.toolbarHeight {
      fragment = next
    }
    let offset = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
    return .message(offset: offset, distance: fragment.layoutFragmentFrame.minY - visibleTop)
  }

  /// Scrolls back to where an anchor says. If its message is gone, the oldest message left goes at
  /// the top.
  func scroll(to anchor: Anchor) {
    let offset: Int
    let distance: CGFloat
    switch anchor {
    case .bottom:
      self.scrollToBottom()
      return
    case .top:
      self.scrollToTop()
      return
    case .message(let messageOffset, let messageDistance):
      offset = messageOffset
      distance = messageDistance
    }
    guard let clipView = self.clipView,
          let textLayoutManager = self.textLayoutManager,
          let contentStorage = self.textContentStorage else {
      return
    }
    var top = self.scrollRange(in: clipView).lowerBound
    if offset >= 0, let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: offset) {
      textLayoutManager.ensureLayout(for: NSTextRange(location: location))
      if let fragment = textLayoutManager.textLayoutFragment(for: location) {
        top = fragment.layoutFragmentFrame.minY - distance + self.textContainerOrigin.y - self.toolbarHeight
      }
    }
    let range = self.scrollRange(in: clipView)
    self.scrollClip(to: min(max(top, range.lowerBound), range.upperBound))
  }

  /// Lays out the text where an anchor is, a few screens of it, so that what's about to be on
  /// screen, and around it, has its real height rather than TextKit 2's estimate. The estimate
  /// can be well off, as for date dividers, whose spacing it leaves out, and pinning to it means
  /// moving again once the real heights come in.
  private func layOut(around anchor: Anchor) {
    guard let textLayoutManager = self.textLayoutManager,
          let contentStorage = self.textContentStorage,
          let clipView = self.clipView else {
      return
    }
    let screen = clipView.bounds.height
    switch anchor {
    case .bottom:
      self.layOut(textLayoutManager, from: textLayoutManager.documentRange.endLocation, backward: true, height: screen * 2.5)
    case .top:
      self.layOut(textLayoutManager, from: textLayoutManager.documentRange.location, backward: false, height: screen * 2.5)
    case .message(let offset, _):
      if let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: max(0, offset)) {
        self.layOut(textLayoutManager, from: location, backward: true, height: screen)
        self.layOut(textLayoutManager, from: location, backward: false, height: screen * 2)
      }
    }
  }

  /// Lays out messages from a place in the text, forward or back, until they're `height` tall.
  private func layOut(_ textLayoutManager: NSTextLayoutManager, from location: any NSTextLocation, backward: Bool, height: CGFloat) {
    var laidOut: CGFloat = 0
    textLayoutManager.enumerateTextLayoutFragments(from: location, options: backward ? [.reverse, .ensuresLayout] : [.ensuresLayout]) { fragment in
      laidOut += fragment.layoutFragmentFrame.height
      return laidOut < height
    }
  }

  /// Shows the start of the chat.
  func scrollToTop() {
    if let clipView = self.clipView {
      self.scrollClip(to: self.scrollRange(in: clipView).lowerBound)
    }
  }

  /// Shows the end of the chat.
  func scrollToBottom() {
    if let clipView = self.clipView {
      self.scrollClip(to: self.scrollRange(in: clipView).upperBound)
    }
  }

  private func scrollClip(to y: CGFloat) {
    guard let clipView = self.clipView, abs(clipView.bounds.minY - y) > 0.25 else {
      return
    }
    clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
    self.enclosingScrollView?.reflectScrolledClipView(clipView)
  }
}

// MARK: - Layout Fragments

/// Hands out layout fragments that draw what the text alone can't.
final class ChatLayoutFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
  /// The link or name under the pointer, in characters, which the fragment holding it underlines.
  var hoveredLink: NSRange?
  /// The color of the lines between days, and code blocks' languages.
  var tertiaryColor: NSColor = .tertiaryLabelColor

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
    guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
      return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }

    let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
    let decoration: ChatLayoutFragment.Decoration
    if attributes[ChatMessageRenderer.codeBlockKey] != nil {
      decoration = .codeBlock
    }
    else if attributes[ChatMessageRenderer.serverMessageKey] != nil {
      decoration = .serverMessage
    }
    else if attributes[ChatMessageRenderer.dividerKey] != nil {
      decoration = .divider
    }
    else if attributes[ChatMessageRenderer.senderNameKey] != nil {
      decoration = .icon(ChatLayoutFragment.icon(savedIconID: (attributes[ChatMessageRenderer.iconIDKey] as? NSNumber)?.uintValue))
    }
    else {
      decoration = .none
    }
    let fragment = ChatLayoutFragment(textElement: textElement, range: textElement.elementRange, decoration: decoration)
    fragment.provider = self
    return fragment
  }
}

/// A message's layout fragment, with what it draws behind its text: the sender's icon before
/// their name (wide icons run under the name, as in the user list), the rounded background of a
/// server message or a code block, or the line through a date divider. It also underlines a link
/// under the pointer.
final class ChatLayoutFragment: NSTextLayoutFragment {
  enum Decoration {
    case none
    case icon(NSImage?)
    case serverMessage
    case divider
    case codeBlock
  }

  let decoration: Decoration
  weak var provider: ChatLayoutFragmentProvider?

  private static let iconHeight: CGFloat = 16
  /// Room for the widest icons.
  private static let widestIcon: CGFloat = 48

  /// The icon the sender had when the message came in, or the generic one when that wasn't saved
  /// or isn't one we have, as in the user list. Names aren't accounts, so someone online now with
  /// the same name could be someone else, and their icon isn't used.
  static func icon(savedIconID: UInt?) -> NSImage? {
    savedIconID.flatMap { NSImage(named: "Classic/\($0)") } ?? NSImage(named: "User")
  }

  init(textElement: NSTextElement, range: NSTextRange?, decoration: Decoration) {
    self.decoration = decoration
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// How far in from the container's edges text starts.
  private var lineFragmentPadding: CGFloat {
    self.textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
  }

  /// The text's lines, in the fragment's coordinates.
  private var textBounds: CGRect {
    self.textLineFragments.reduce(CGRect.null) { $0.union($1.typographicBounds) }
  }

  /// The middle of the icon's frame, which starts where text starts, past the container's padding.
  private var iconMidX: CGFloat {
    self.lineFragmentPadding + ChatMessageRenderer.iconInset + ChatMessageRenderer.iconColumnWidth / 2 - self.layoutFragmentFrame.minX
  }

  /// The icon's middle line, centered on the message's first line.
  private var iconMidY: CGFloat {
    self.textLineFragments.first.map { $0.typographicBounds.midY } ?? Self.iconHeight / 2
  }

  /// Where the sender's icon is, in the fragment's coordinates: centered in its frame, 16 pt tall,
  /// as wide as its shape.
  var iconFrame: CGRect? {
    guard case .icon(let image) = self.decoration, let icon = image else {
      return nil
    }
    let height = Self.iconHeight
    let width = icon.size.height > 0 ? (icon.size.width / icon.size.height * height).rounded() : height
    return CGRect(x: self.iconMidX - width / 2, y: self.iconMidY - height / 2, width: width, height: height)
  }

  /// The language a code block names, which shows above its code.
  private lazy var codeLanguage: String? = {
    guard case .codeBlock = self.decoration, let text = (self.textElement as? NSTextParagraph)?.attributedString, text.length > 0 else {
      return nil
    }
    return text.attribute(ChatMessageRenderer.codeLanguageKey, at: 0, effectiveRange: nil) as? String
  }()

  private static var codeLanguageFont: NSFont {
    .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
  }

  /// Where the decoration draws, in the fragment's coordinates. For icons, room for any icon.
  private var decorationBounds: CGRect {
    switch self.decoration {
    case .none:
      return .null

    case .icon:
      return CGRect(x: self.iconMidX - Self.widestIcon / 2, y: self.iconMidY - Self.iconHeight / 2, width: Self.widestIcon, height: Self.iconHeight)

    case .serverMessage:
      let text = self.textBounds
      let width = self.textLayoutManager?.textContainer?.size.width ?? self.layoutFragmentFrame.width
      return CGRect(x: -self.layoutFragmentFrame.minX, y: text.minY - 10, width: width, height: text.height + 20)

    case .divider:
      // A line through the middle of the date, from where text starts across to the same margin on
      // the right, which leaves room around the date as it's drawn.
      let line = self.textLineFragments.first?.typographicBounds ?? self.textBounds
      let width = self.textLayoutManager?.textContainer?.size.width ?? self.layoutFragmentFrame.width
      let left = self.lineFragmentPadding - self.layoutFragmentFrame.minX
      let right = width - self.lineFragmentPadding - self.layoutFragmentFrame.minX
      return CGRect(x: left, y: line.midY, width: right - left, height: 1)

    case .codeBlock:
      // Around the code, from where a message's wrapped lines start across to the right margin,
      // and the language it names above it.
      let text = self.textBounds
      let width = self.textLayoutManager?.textContainer?.size.width ?? self.layoutFragmentFrame.width
      let left = self.lineFragmentPadding + self.codeBlockIndent - self.layoutFragmentFrame.minX
      let right = width - self.lineFragmentPadding - self.layoutFragmentFrame.minX
      let padding = ChatMessageRenderer.codeBlockPadding.height
      let top = text.minY - padding - (self.codeLanguage == nil ? 0 : ChatMessageRenderer.codeLanguageHeight)
      return CGRect(x: left, y: top, width: right - left, height: text.maxY + padding - top)
    }
  }

  override var renderingSurfaceBounds: CGRect {
    super.renderingSurfaceBounds.union(self.decorationBounds)
  }

  /// The room a divider's line leaves either side of the date.
  private static let dividerGap: CGFloat = 8

  /// Where a divider's date starts and ends across, in the fragment's coordinates.
  private var dividerDate: ClosedRange<CGFloat>? {
    guard let line = self.textLineFragments.first else {
      return nil
    }
    let string = line.attributedString.string as NSString
    let start = line.characterRange.location
    var end = NSMaxRange(line.characterRange)
    // Not the line break after it.
    while end > start, CharacterSet.newlines.contains(UnicodeScalar(string.character(at: end - 1)) ?? " ") {
      end -= 1
    }
    let origin = line.typographicBounds.minX
    return (origin + line.locationForCharacter(at: start).x)...(origin + line.locationForCharacter(at: end).x)
  }

  /// Where a code block's background starts: where its lines do, less its padding.
  private lazy var codeBlockIndent: CGFloat = {
    let padding = ChatMessageRenderer.codeBlockPadding.width
    guard let text = (self.textElement as? NSTextParagraph)?.attributedString, text.length > 0,
          let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
      return ChatMessageRenderer.textIndent + ChatMessageRenderer.hangingIndent
    }
    return style.headIndent - padding
  }()

  /// Where a code block's background is, in the fragment's coordinates, if this is one.
  var codeBlockBounds: CGRect? {
    guard case .codeBlock = self.decoration else {
      return nil
    }
    return self.decorationBounds
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    switch self.decoration {
    case .none:
      break

    case .icon(let icon):
      if let icon, var rect = self.iconFrame?.offsetBy(dx: point.x, dy: point.y) {
        // Messages can sit part of a pixel off, and the icons are pixel art, which blurs when it's
        // drawn off the pixel grid. Text drops the part of a pixel, so the icon does the same, to
        // stay put beside the name wherever the message is.
        let pixel = abs(context.convertToUserSpace(CGSize(width: 1, height: 1)).height)
        rect.origin.x = (rect.minX / pixel).rounded(.down) * pixel
        rect.origin.y = (rect.minY / pixel).rounded(.down) * pixel
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
      }

    case .serverMessage:
      let rect = self.decorationBounds.offsetBy(dx: point.x, dy: point.y)
      context.saveGState()
      context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
      context.setFillColor(NSColor.textColor.withAlphaComponent(0.06).cgColor)
      context.fillPath()
      context.restoreGState()

    case .divider:
      // One pixel tall, whatever the screen's scale, and darker than a separator, to stand out from
      // the messages. It stops short of the date and goes on after it.
      let rect = self.decorationBounds.offsetBy(dx: point.x, dy: point.y)
      let pixel = abs(context.convertToUserSpace(CGSize(width: 1, height: 1)).height)
      let y = (rect.minY / pixel).rounded(.down) * pixel
      var segments = [rect.minX...rect.maxX]
      if let date = self.dividerDate {
        let before = rect.minX...max(rect.minX, date.lowerBound + point.x - Self.dividerGap)
        let after = min(rect.maxX, date.upperBound + point.x + Self.dividerGap)...rect.maxX
        segments = [before, after]
      }
      context.saveGState()
      context.setFillColor((self.provider?.tertiaryColor ?? .tertiaryLabelColor).cgColor)
      // A stub too short to read as a line isn't drawn.
      for segment in segments where segment.upperBound - segment.lowerBound >= 4 {
        context.fill(CGRect(x: segment.lowerBound, y: y, width: segment.upperBound - segment.lowerBound, height: pixel))
      }
      context.restoreGState()

    case .codeBlock:
      let rect = self.decorationBounds.offsetBy(dx: point.x, dy: point.y)
      context.saveGState()
      context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
      context.setFillColor(ChatMessageRenderer.codeBlockBackground.cgColor)
      context.fillPath()
      context.restoreGState()
      if let language = self.codeLanguage {
        // Small and faint, in line with the code.
        let label = NSAttributedString(string: language, attributes: [
          .font: Self.codeLanguageFont,
          .foregroundColor: self.provider?.tertiaryColor ?? .tertiaryLabelColor,
        ])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(x: rect.minX + ChatMessageRenderer.codeBlockPadding.width, y: rect.minY + ChatMessageRenderer.codeBlockPadding.height - 1))
        NSGraphicsContext.restoreGraphicsState()
      }
    }

    super.draw(at: point, in: context)
    self.drawHoveredLink(at: point, in: context)
  }

  /// Underlines the link or name under the pointer, if it's in this message. TextKit 2 doesn't draw
  /// underlines added as rendering attributes, only colors, so the fragment draws its own.
  private func drawHoveredLink(at point: CGPoint, in context: CGContext) {
    guard let link = self.provider?.hoveredLink,
          let contentManager = self.textLayoutManager?.textContentManager,
          let paragraph = self.textElement as? NSTextParagraph else {
      return
    }
    // The link's characters, counted from the start of this message.
    let start = contentManager.offset(from: contentManager.documentRange.location, to: self.rangeInElement.location)
    let local = NSIntersectionRange(NSRange(location: link.location - start, length: link.length), NSRange(location: 0, length: paragraph.attributedString.length))
    guard local.length > 0 else {
      return
    }

    let pixel = abs(context.convertToUserSpace(CGSize(width: 1, height: 1)).height)
    context.saveGState()
    for line in self.textLineFragments {
      var range = NSIntersectionRange(line.characterRange, local)
      // Not under a file's icon.
      if range.length > 1, (line.attributedString.string as NSString).character(at: range.location) == 0xFFFC {
        range = NSRange(location: range.location + 1, length: range.length - 1)
      }
      guard range.length > 0 else {
        continue
      }
      let attributes = line.attributedString.attributes(at: range.location, effectiveRange: nil)
      let font = attributes[.font] as? NSFont ?? ChatMessageRenderer.baseFont
      let color = attributes[.foregroundColor] as? NSColor ?? .textColor
      let left = line.locationForCharacter(at: range.location).x
      let right = line.locationForCharacter(at: NSMaxRange(range)).x
      // Below the baseline by the font's underline position, on whole pixels so it's crisp, with
      // the part of a pixel dropped the way the text drops it.
      let baseline = point.y + line.typographicBounds.minY + line.glyphOrigin.y
      let y = ((baseline - font.underlinePosition) / pixel).rounded(.down) * pixel
      let thickness = max(pixel, (font.underlineThickness / pixel).rounded() * pixel)
      context.setFillColor(color.cgColor)
      context.fill(CGRect(x: point.x + line.typographicBounds.minX + left, y: y, width: right - left, height: thickness))
    }
    context.restoreGState()
  }
}
