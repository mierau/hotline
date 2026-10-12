import SwiftUI

/// Markdown, shown as it's written, to read, select and copy, but not to change: a post on the
/// board, a news article, a private message, or what's new in an update. Styled as Markdown's shown
/// everywhere, on TextKit 2, as the board's editor has it. It's selectable all at once, from one end
/// to the other, but not on into the next, and links go where they go, as they do in chat: a link
/// to a file opens a menu for the file, and an image's preview opens the image.
struct MarkdownText: NSViewRepresentable {
  let text: String
  var layout: Markdown.Layout = .board
  /// How far in from its edges its words are.
  var inset: NSSize = .zero
  /// What its menu has first, before what's for words, like Quote in New Post.
  var menuItems: () -> [NSMenuItem] = { [] }
  /// The menu for a link to a file, like the Files list's for the file.
  var fileLinkMenu: ((URL) -> NSMenu?)? = nil
  /// What clicking a link does, when it's something other than what SwiftUI's openURL does.
  var openURL: ((URL) -> Void)? = nil
  /// Whether links to images have previews, as they're set to, in chat and everywhere else.
  var previewsImages = Prefs.shared.previewChatImages

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> MarkdownTextView {
    let textView = MarkdownTextView(usingTextLayoutManager: true)
    textView.configure()
    textView.delegate = context.coordinator
    return textView
  }

  func updateNSView(_ textView: MarkdownTextView, context: Context) {
    // Through SwiftUI's openURL, unless it's told otherwise, so hotline:// links stay in the app.
    let environment = context.environment
    let openURL = self.openURL ?? { url in environment.openURL(url) }
    context.coordinator.openURL = openURL
    textView.openURLAction = openURL
    textView.openImageAction = { url in
      environment.openWindow(id: "preview-quicklook", value: PreviewFileInfo(webImage: url))
    }
    textView.menuItems = self.menuItems
    textView.fileLinkMenu = self.fileLinkMenu
    textView.inset = self.inset
    textView.applyServerTheme(environment.serverTheme)
    var layout = self.layout
    if !self.previewsImages {
      layout.imagePreviews = 0
    }
    layout.colors = Markdown.Colors(theme: environment.serverTheme)
    textView.colors = layout.colors
    textView.show(self.text, layout: layout)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: MarkdownTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width.isFinite else {
      return nil
    }
    return CGSize(width: width, height: textView.height(forWidth: width))
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var openURL: ((URL) -> Void)?

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      guard let url = (link as? URL) ?? (link as? String).flatMap({ URL(string: $0) }) else {
        return false
      }
      if let openURL = self.openURL {
        openURL(url)
      }
      else {
        NSWorkspace.shared.open(url)
      }
      return true
    }
  }
}

/// Markdown's words, to read, select and copy, but not to change. Selecting in one leaves nothing
/// selected in the one selected before it, so there's only ever one selection.
///
/// Don't use `layoutManager` here, even to read it. Asking for it switches the view to TextKit 1
/// for good. Use `textLayoutManager` instead.
final class MarkdownTextView: NSTextView, LinkActions {
  var openURLAction: ((URL) -> Void)?
  /// What clicking an image's preview does: open the image in a preview window.
  var openImageAction: ((URL) -> Void)?
  /// What the menu has first, before what's for words.
  var menuItems: () -> [NSMenuItem] = { [] }
  /// The menu for a link to a file, like the Files list's for the file.
  var fileLinkMenu: ((URL) -> NSMenu?)?
  /// How far in from the view's edges the words are.
  var inset: NSSize = .zero {
    didSet {
      if self.inset != oldValue {
        self.measured = nil
        self.textContainerInset = self.inset
      }
    }
  }
  /// Code blocks' languages and backgrounds, quotes' bars, and lines across, in a server's theme's
  /// colors, or the system's.
  var colors = Markdown.Colors() {
    didSet {
      if self.colors != oldValue {
        self.fragments.apply(self.colors)
        self.redrawText(in: nil)
      }
    }
  }

  /// What's shown, as it's written, and how, so it's only shown again when that changes.
  private var shown: (text: String, layout: Markdown.Layout)?
  /// How tall the words are at the width they were last measured at.
  private var measured: (width: CGFloat, height: CGFloat)?
  /// The one with the selection, if any has one.
  private static weak var selecting: MarkdownTextView?
  private var pointerTracking: NSTrackingArea?
  /// For code blocks' backgrounds, quotes' bars and lines across, as in the editor, and the link
  /// under the pointer, underlined, as in chat.
  private var fragments = MarkdownFragments(layout: .board)

  /// Sets the view up. Separate from init so `init(usingTextLayoutManager:)` can be used.
  func configure() {
    self.textLayoutManager?.delegate = self.fragments
    self.isEditable = false
    self.isSelectable = true
    // Copied as rich text too, which pastes into a new post with its bold, italic, code and links.
    self.isRichText = true
    self.importsGraphics = false
    self.drawsBackground = false
    self.usesFindBar = false
    self.isAutomaticLinkDetectionEnabled = false
    self.focusRingType = .none
    self.textContainerInset = self.inset
    self.textContainer?.lineFragmentPadding = 0
    self.textContainer?.widthTracksTextView = true
    self.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    // As tall as SwiftUI makes it, which is as tall as its words.
    self.isVerticallyResizable = false
    self.isHorizontallyResizable = false
    // Links keep the color they're styled in, without an underline, as the board's always had them.
    // The pointer over them is handled here.
    self.linkTextAttributes = [:]
  }

  func show(_ text: String, layout: Markdown.Layout) {
    guard self.shown?.text != text || self.shown?.layout != layout else {
      return
    }
    if self.shown?.layout.codePadding != layout.codePadding {
      let fragments = MarkdownFragments(layout: layout)
      fragments.apply(self.colors)
      self.fragments = fragments
      self.textLayoutManager?.delegate = fragments
    }
    self.shown = (text, layout)
    self.measured = nil
    self.textStorage?.setAttributedString(Markdown.shown(text, layout: layout))
  }

  /// How tall the words are, laid out at a width, with the room around them.
  func height(forWidth width: CGFloat) -> CGFloat {
    if let measured = self.measured, measured.width == width {
      return measured.height
    }
    guard let layoutManager = self.textLayoutManager, let container = self.textContainer else {
      return 0
    }
    let inset = self.inset
    container.size = NSSize(width: max(width - 2 * inset.width, 1), height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: layoutManager.documentRange)
    let usage = layoutManager.usageBoundsForTextContainer

    // TextKit leaves out the room before the first paragraph and after the last, which, for a code
    // block at the top or bottom, is where its background goes, past its code. So it's made around
    // the words instead, for the block to be as far in from the edges as words.
    var above: CGFloat = 0, below: CGFloat = 0
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
      if fragment is MarkdownCodeLineFragment {
        above = max(0, -(fragment.layoutFragmentFrame.minY + fragment.renderingSurfaceBounds.minY))
      }
      return false
    }
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.endLocation, options: .reverse) { fragment in
      if fragment is MarkdownCodeLineFragment {
        below = max(0, fragment.layoutFragmentFrame.minY + fragment.renderingSurfaceBounds.maxY - usage.maxY)
      }
      return false
    }
    self.textContainerInset = NSSize(width: inset.width, height: inset.height + above)

    let height = (usage.height + 2 * inset.height + above + below).rounded(.up)
    self.measured = (width, height)
    // Measured at another width than it's shown at, as SwiftUI does while the window's resized, it's
    // laid out again at the width it's shown at, or what's shown would wrap at the width it was
    // measured at, cut off, or not be laid out at all.
    if self.frame.width > 0, abs(self.frame.width - width) > 0.5 {
      self.fitContainer()
      self.layOutShown()
    }
    return height
  }

  /// Its words as wide as it is, or is about to be, less the room beside them. Told to keep to its
  /// width, TextKit 2 doesn't, once it's been measured at another.
  private func fitContainer(to width: CGFloat? = nil) {
    guard let container = self.textContainer else {
      return
    }
    let width = max((width ?? self.frame.width) - 2 * self.textContainerInset.width, 1)
    if abs(container.size.width - width) > 0.5 {
      container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }
  }

  /// Lays out what's on screen again, and draws it, as TextKit 2 lays out only what's on screen, and
  /// a text view among others, with only part of it on screen, isn't told to again itself.
  private func layOutShown() {
    // All of it first, at the width it's shown at, as it may have been laid out at another to be
    // measured, and what's on screen is laid out after what's above it, wherever that ended up.
    if let layoutManager = self.textLayoutManager {
      layoutManager.ensureLayout(for: layoutManager.documentRange)
    }
    self.textLayoutManager?.textViewportLayoutController.layoutViewport()
    // And again in its own layout, once it's where it's going, as what's on screen can be another
    // part of it by then, which NSTextView doesn't lay out itself while the window's being resized.
    self.needsShownLayout = true
    self.needsLayout = true
    self.needsDisplay = true
  }

  /// Whether what's on screen is to be laid out again in its own layout.
  private var needsShownLayout = false

  override func layout() {
    super.layout()
    if self.needsShownLayout {
      self.needsShownLayout = false
      self.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }
  }

  /// A preview's grown, or shrunk, to fit its image, and the words with it, which SwiftUI measures
  /// again.
  func previewDidResize() {
    self.measured = nil
    self.invalidateIntrinsicContentSize()
  }

  // MARK: Resizing

  // At a new width, its words are as wide, and what's on screen is laid out again, straight away, as
  // neither is done for it, and it would show its words as they were before, cut off, while the
  // window's being resized, or else none at all.
  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = abs(newSize.width - self.frame.width) > 0.5 && newSize.width > 0
    // First, for it to be laid out at the new width as it's sized.
    if widthChanged {
      self.fitContainer(to: newSize.width)
    }
    super.setFrameSize(newSize)
    if widthChanged {
      self.stretchSubviews()
      self.layOutShown()
    }
  }

  /// The views it draws its words in, all of it, as big as it is, as they're set to be. While the
  /// window's resized, NSTextView leaves them as they were when the resize started until it's over,
  /// cutting its words off at that width, or leaving some out.
  private func stretchSubviews() {
    for view in self.subviews where view.autoresizingMask.contains([.width, .height]) && view.frame.origin == .zero && view.frame.size != self.bounds.size {
      view.frame = self.bounds
    }
  }

  // Drawn again all over as the window's resized, as its lines are laid out again, and not kept as
  // they were, cut off at the width they were.
  override var preservesContentDuringLiveResize: Bool {
    false
  }

  override func becomeFirstResponder() -> Bool {
    guard super.becomeFirstResponder() else {
      return false
    }
    if let other = Self.selecting, other !== self {
      other.setSelectedRange(NSRange(location: 0, length: 0))
    }
    Self.selecting = self
    return true
  }

  // MARK: Pointer

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let area = self.pointerTracking {
      self.removeTrackingArea(area)
    }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    self.addTrackingArea(area)
    self.pointerTracking = area
  }

  // The pointing hand over a link, which is underlined, as chat has it, and the text pointer over
  // the rest.
  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    let link = self.link(at: self.convert(event.locationInWindow, from: nil))
    self.underline(link)
    (link != nil ? NSCursor.pointingHand : NSCursor.iBeam).set()
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    self.underline(nil)
  }

  override func cursorUpdate(with event: NSEvent) {
    if self.link(at: self.convert(event.locationInWindow, from: nil)) != nil {
      NSCursor.pointingHand.set()
    }
    else {
      super.cursorUpdate(with: event)
    }
  }

  /// A click on a link to a file opens its menu under it, like a pull-down button.
  override func mouseDown(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    if !event.modifierFlags.contains(.control), let link = self.fileLink(at: point), let menu = self.fileLinkMenu?(link.url) {
      menu.popUp(positioning: nil, at: NSPoint(x: link.frame.minX, y: link.frame.maxY + 2), in: self)
      return
    }
    super.mouseDown(with: event)
  }

  /// The character under a point, if the point's over one, and not just past the end of a line, as
  /// the nearest place between two characters can be.
  private func character(at point: NSPoint) -> Int? {
    guard let window = self.window, let storage = self.textStorage else {
      return nil
    }
    let screenPoint = window.convertPoint(toScreen: self.convert(point, to: nil))
    let index = self.characterIndex(for: screenPoint)
    guard index != NSNotFound, index < storage.length,
          self.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil).insetBy(dx: -1, dy: -1).contains(screenPoint) else {
      return nil
    }
    return index
  }

  /// The link under a point, all of it, if the point's over one.
  private func link(at point: NSPoint) -> NSRange? {
    guard let storage = self.textStorage, let index = self.character(at: point) else {
      return nil
    }
    var range = NSRange()
    return storage.attribute(.link, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) == nil ? nil : range
  }

  /// The link to a file under a point, and where it is in the view, on the line under the point.
  private func fileLink(at point: NSPoint) -> (url: URL, frame: NSRect)? {
    guard let storage = self.textStorage, let index = self.character(at: point) else {
      return nil
    }
    var range = NSRange()
    guard let url = storage.attribute(Markdown.fileLinkKey, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? URL else {
      return nil
    }
    var frame = NSRect(origin: point, size: .zero)
    if let layoutManager = self.textLayoutManager, let content = self.textContentStorage,
       let start = content.location(content.documentRange.location, offsetBy: range.location),
       let end = content.location(start, offsetBy: range.length),
       let textRange = NSTextRange(location: start, end: end) {
      let origin = self.textContainerOrigin
      layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, segment, _, _ in
        let rect = segment.offsetBy(dx: origin.x, dy: origin.y)
        if point.y >= rect.minY, point.y <= rect.maxY {
          frame = rect
          return false
        }
        return true
      }
    }
    return (url, frame)
  }

  /// Underlines a link, and takes the underline off the one before, drawing again where they are.
  private func underline(_ link: NSRange?) {
    let before = self.fragments.hoveredLink
    guard link != before else {
      return
    }
    self.fragments.hoveredLink = link
    for range in [before, link].compactMap({ $0 }) {
      self.redrawText(in: self.rect(of: range))
    }
  }

  /// Where a range of the text is, all of the paragraphs it's in.
  private func rect(of range: NSRange) -> NSRect? {
    guard let layoutManager = self.textLayoutManager, let content = self.textContentStorage,
          let start = content.location(content.documentRange.location, offsetBy: range.location),
          let end = content.location(start, offsetBy: range.length) else {
      return nil
    }
    var rect = NSRect.null
    layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
      rect = rect.union(fragment.layoutFragmentFrame)
      return fragment.rangeInElement.endLocation.compare(end) == .orderedAscending
    }
    let origin = self.textContainerOrigin
    return rect.isNull ? nil : rect.offsetBy(dx: origin.x, dy: origin.y)
  }

  /// Draws again what's in a rect of the text, in the views TextKit draws it in, or all of it.
  private func redrawText(in rect: NSRect?) {
    func redraw(_ view: NSView) {
      for subview in view.subviews where !(subview is ImagePreviewView) {
        if let rect, !subview.convert(subview.bounds, to: self).intersects(rect) {
          continue
        }
        subview.needsDisplay = true
        redraw(subview)
      }
    }
    redraw(self)
  }

  // MARK: Keys

  /// What scrolls with the keys through all of what it's in, among other posts, if it's in one
  /// that has it.
  private weak var keyScrolling: KeyScrollingView?

  /// Scrolls what it's in as a key does: as the posts it's among scroll, or else itself.
  private func keyScroll(_ amount: NSScrollView.KeyScroll, down: Bool) {
    if self.keyScrolling?.enclosingScrollView !== self.enclosingScrollView || self.keyScrolling == nil {
      self.keyScrolling = KeyScrollingView.in(self.enclosingScrollView)
    }
    if let keys = self.keyScrolling {
      keys.scroll(amount, down: down)
    }
    else {
      self.enclosingScrollView?.scroll(amount, down: down)
    }
  }

  // The keys that move through words scroll through what they're in instead, as there's nowhere in
  // words that can't be written in to move to, and as far as where there are no words.
  override func moveUp(_ sender: Any?) {
    self.keyScroll(.line, down: false)
  }

  override func moveDown(_ sender: Any?) {
    self.keyScroll(.line, down: true)
  }

  override func scrollLineUp(_ sender: Any?) {
    self.keyScroll(.line, down: false)
  }

  override func scrollLineDown(_ sender: Any?) {
    self.keyScroll(.line, down: true)
  }

  override func pageUp(_ sender: Any?) {
    self.keyScroll(.page, down: false)
  }

  override func pageDown(_ sender: Any?) {
    self.keyScroll(.page, down: true)
  }

  override func scrollPageUp(_ sender: Any?) {
    self.keyScroll(.page, down: false)
  }

  override func scrollPageDown(_ sender: Any?) {
    self.keyScroll(.page, down: true)
  }

  override func moveToBeginningOfDocument(_ sender: Any?) {
    self.keyScroll(.all, down: false)
  }

  override func moveToEndOfDocument(_ sender: Any?) {
    self.keyScroll(.all, down: true)
  }

  override func scrollToBeginningOfDocument(_ sender: Any?) {
    self.keyScroll(.all, down: false)
  }

  override func scrollToEndOfDocument(_ sender: Any?) {
    self.keyScroll(.all, down: true)
  }

  // Hidden, scrolled out of sight in a lazy stack, which hides what's out of sight, with the keys,
  // it hands them on to what scrolls through the rest, for the keys to go on scrolling, and not stop
  // with nothing to take them.
  override func resignFirstResponder() -> Bool {
    guard super.resignFirstResponder() else {
      return false
    }
    if self.isHiddenOrHasHiddenAncestor {
      self.handKeysOn()
    }
    return true
  }

  // And the same taken out, with the keys.
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil, self.window?.firstResponder === self {
      self.handKeysOn()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  /// Gives the keys to what scrolls through the rest of what it's in, if it has that, once they've
  /// gone to nothing else.
  private func handKeysOn() {
    guard let window = self.window, let keys = KeyScrollingView.in(self.enclosingScrollView) else {
      return
    }
    DispatchQueue.main.async {
      if keys.window === window, !keys.isHiddenOrHasHiddenAncestor, window.firstResponder == nil || window.firstResponder === window {
        window.makeFirstResponder(keys)
      }
    }
  }

  // MARK: Copying

  // Plain text gets real line breaks, the links to files as their links and long links as they were
  // written, rather than as they're shown, and none of the stand-in characters for icons and
  // previews.
  override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
    let wrote = super.writeSelection(to: pboard, types: types)
    if wrote, pboard.string(forType: .string) != nil, let storage = self.textStorage {
      let selected = self.selectedRanges
        .map(\.rangeValue)
        .filter { $0.length > 0 && NSMaxRange($0) <= storage.length }
        .map { Markdown.plainText(storage.attributedSubstring(from: $0)) }
      pboard.setString(selected.joined(separator: "\n"), forType: .string)
    }
    return wrote
  }

  // MARK: Menu

  /// What a text view's menu has for writing, which these words aren't for: Cut, Paste, and the
  /// menus for fonts, spelling and substitutions.
  private static let writing: Set<Selector> = [
    #selector(NSText.cut(_:)),
    #selector(NSText.paste(_:)),
    #selector(NSTextView.pasteAsPlainText(_:)),
    #selector(NSFontManager.addFontTrait(_:)),
    #selector(NSText.showGuessPanel(_:)),
    #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
  ]

  // What it's given to have first, then a file's menu, over a link to one, or else what's for words
  // to read and copy.
  override func menu(for event: NSEvent) -> NSMenu? {
    if let link = self.fileLink(at: self.convert(event.locationInWindow, from: nil)), let menu = self.fileLinkMenu?(link.url) {
      return menu
    }
    let menu = super.menu(for: event) ?? NSMenu()
    for item in menu.items.reversed() {
      let actions = [item.action] + (item.submenu?.items.map(\.action) ?? [])
      if actions.contains(where: { $0.map(Self.writing.contains) ?? false }) {
        menu.removeItem(item)
      }
    }
    // Without the lines that went between what's gone.
    for (index, item) in menu.items.enumerated().reversed() where item.isSeparatorItem {
      if index == 0 || index == menu.items.count - 1 || menu.items[index + 1].isSeparatorItem {
        menu.removeItem(at: index)
      }
    }
    let items = self.menuItems()
    if !items.isEmpty {
      for (index, item) in items.enumerated() {
        menu.insertItem(item, at: index)
      }
      menu.insertItem(.separator(), at: items.count)
    }
    return menu
  }
}

/// An item for the top of shown words' menu, like Quote in New Post, which stays off when it can't
/// be done, as that menu turns its items on and off itself.
final class TextMenuItem: NSMenuItem, NSMenuItemValidation {
  private let isAllowed: Bool
  private let handler: () -> Void

  init(_ title: String, systemImage: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
    self.isAllowed = isEnabled
    self.handler = handler
    super.init(title: title, action: #selector(TextMenuItem.choose), keyEquivalent: "")
    self.target = self
    self.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func choose() {
    self.handler()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    self.isAllowed
  }
}

extension Markdown.Colors {
  /// In a server's theme's colors, or the system's, without one.
  init(theme: ServerTheme?) {
    self.init(secondary: theme?.secondaryText, tertiary: theme?.tertiaryText)
  }
}

// MARK: - Keys

/// Scrolling with the keys through all of a scroll view of posts, like the board's or a news
/// conversation's, behind them, for where there are no words to have the keys: a click in the room
/// between posts gives it the keys, and words that had them, scrolled out of sight in the lazy stack
/// they're in, hand the keys on to it, to go on scrolling. The words' own keys scroll with it too.
struct KeyScrolling: NSViewRepresentable {
  /// Scrolls as a key does, in place of scrolling what it's in itself, for a SwiftUI scroll view
  /// told where to scroll to, which would go back there otherwise.
  var scroll: ((NSScrollView.KeyScroll, _ down: Bool) -> Void)? = nil

  func makeNSView(context: Context) -> KeyScrollingView {
    KeyScrollingView()
  }

  func updateNSView(_ view: KeyScrollingView, context: Context) {
    view.scrolls = self.scroll
  }
}

final class KeyScrollingView: NSView {
  /// Scrolls as a key does, in place of scrolling what it's in itself.
  var scrolls: ((NSScrollView.KeyScroll, Bool) -> Void)?

  /// The one in a scroll view, if it has one.
  static func `in`(_ scrollView: NSScrollView?) -> KeyScrollingView? {
    func find(in view: NSView) -> KeyScrollingView? {
      (view as? KeyScrollingView) ?? view.subviews.lazy.compactMap(find).first
    }
    return scrollView?.documentView.flatMap(find)
  }

  /// Scrolls what it's in as a key does, as it's told to, or itself.
  func scroll(_ amount: NSScrollView.KeyScroll, down: Bool) {
    if let scrolls = self.scrolls {
      scrolls(amount, down)
    }
    else {
      self.enclosingScrollView?.scroll(amount, down: down)
    }
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    self.interpretKeyEvents([event])
  }

  override func moveUp(_ sender: Any?) {
    self.scroll(.line, down: false)
  }

  override func moveDown(_ sender: Any?) {
    self.scroll(.line, down: true)
  }

  override func scrollLineUp(_ sender: Any?) {
    self.scroll(.line, down: false)
  }

  override func scrollLineDown(_ sender: Any?) {
    self.scroll(.line, down: true)
  }

  override func pageUp(_ sender: Any?) {
    self.scroll(.page, down: false)
  }

  override func pageDown(_ sender: Any?) {
    self.scroll(.page, down: true)
  }

  override func scrollPageUp(_ sender: Any?) {
    self.scroll(.page, down: false)
  }

  override func scrollPageDown(_ sender: Any?) {
    self.scroll(.page, down: true)
  }

  override func moveToBeginningOfDocument(_ sender: Any?) {
    self.scroll(.all, down: false)
  }

  override func moveToEndOfDocument(_ sender: Any?) {
    self.scroll(.all, down: true)
  }

  override func scrollToBeginningOfDocument(_ sender: Any?) {
    self.scroll(.all, down: false)
  }

  override func scrollToEndOfDocument(_ sender: Any?) {
    self.scroll(.all, down: true)
  }
}

extension NSScrollView {
  /// How far a key scrolls: a line, a page of what's shown, less a line of it to read on from, or
  /// all the way.
  enum KeyScroll {
    case line
    case page
    case all

    /// How far a line is, a couple of lines of words, as a web page's is.
    static let lineDistance: CGFloat = 40

    /// How far it scrolls, in a view showing `shown` of what it scrolls through, of `whole`.
    func distance(shown: CGFloat, whole: CGFloat) -> CGFloat {
      switch self {
      case .line: Self.lineDistance
      case .page: max(shown - Self.lineDistance, Self.lineDistance)
      case .all: whole + shown
      }
    }
  }

  /// Scrolls what it shows down or up, as far as `amount`, as far as there's more of it.
  func scroll(_ amount: KeyScroll, down: Bool) {
    let clip = self.contentView
    let distance = amount.distance(shown: clip.bounds.height, whole: self.documentView?.frame.height ?? 0)
    var bounds = clip.bounds
    bounds.origin.y += down == (self.documentView?.isFlipped ?? true) ? distance : -distance
    clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
    self.reflectScrolledClipView(clip)
  }
}
