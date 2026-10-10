import SwiftUI

struct MessageBoardView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverTheme) private var theme
  @Environment(HotlineState.self) private var model: HotlineState
  
  @State private var composerDisplayed: Bool = false
  /// The post just gone to, from a link to it in chat or once you've posted it, outlined a moment.
  @State private var highlightedPost: MessageBoardPost.ID?
  
  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        self.messageBoardView
          .onChange(of: self.model.boardPostToReveal, initial: true) { _, reference in
            self.reveal(reference, with: proxy)
          }
      }
    }
    .overlay {
      if self.model.messageBoard.isEmpty && (self.model.access?.contains(.canReadMessageBoard) != true) {
        self.disabledBoardView
      }
      else if self.model.messageBoardLoaded && self.model.messageBoard.isEmpty {
        self.emptyBoardView
      }
    }
//    .background(self.colorScheme == .light ? Color(nsColor: .tertiarySystemFill).ignoresSafeArea() : Color(nsColor: .controlBackgroundColor).ignoresSafeArea())
//    .containerBackground(.hotlineRed, for: .window)
    .serverBackground(.page)
    .sheet(isPresented: $composerDisplayed) {
      MessageBoardEditorView()
    }
    .toolbar {
      ToolbarItem(placement:.primaryAction) {
        Button {
          self.composerDisplayed.toggle()
        } label: {
          Image(systemName: "pin")
        }
        .disabled(!self.canPost)
        .help("Post to Message Board")
      }
    }
    .task {
      if !self.model.messageBoardLoaded {
        let _ = try? await self.model.getMessageBoard()
      }
    }
  }
  
  /// Whether you can post to the board, which you can't without reading it too.
  private var canPost: Bool {
    self.model.access?.contains(.canPostMessageBoard) == true && self.model.access?.contains(.canReadMessageBoard) == true
  }

  /// A post, quoted in a new one, with who wrote it, after whatever's being written already, which
  /// the new post's sheet opens on.
  private func quote(_ post: MessageBoardPost) {
    let lines = post.body.components(separatedBy: .newlines).map { $0.isEmpty ? ">" : "> \($0)" }
    let quote = (post.username.map { "\($0) wrote:\n" } ?? "") + lines.joined(separator: "\n") + "\n\n"
    let draft = self.model.boardDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    self.model.boardDraft = draft.isEmpty ? quote : draft + "\n\n" + quote
    self.composerDisplayed = true
  }

  /// Scrolls to a post a link in chat asked for, or you've just posted, by its reference, once the
  /// board has laid out, and outlines it a moment, so it's the one you see.
  private func reveal(_ reference: String?, with proxy: ScrollViewProxy) {
    guard let reference else {
      return
    }
    self.model.boardPostToReveal = nil
    guard let post = self.model.messageBoard.first(where: { $0.reference == reference }) else {
      return
    }
    Task { @MainActor in
      withAnimation(.smooth) {
        proxy.scrollTo(post.id, anchor: .top)
      }
      withAnimation(.easeOut(duration: 0.25)) {
        self.highlightedPost = post.id
      }
      try? await Task.sleep(for: .seconds(1.4))
      guard self.highlightedPost == post.id else {
        return
      }
      withAnimation(.easeInOut(duration: 0.9)) {
        self.highlightedPost = nil
      }
    }
  }

  private var disabledBoardView: some View {
    ContentUnavailableView {
      Label("No Message Board", systemImage: "quote.bubble")
    } description: {
      Text("This server has turned off their message board")
    }
  }
  
  private var emptyBoardView: some View {
    ContentUnavailableView {
      Label("No Posts", systemImage: "quote.bubble")
    } description: {
      Text("Message board posts will appear here")
    }
  }
  
  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    formatter.formattingContext = .listItem
    return formatter
  }()

  private var messageBoardView: some View {
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: 16) {
        ForEach(self.model.messageBoard) { post in
          
          VStack(alignment: .leading, spacing: 0) {
            if let signature = self.model.messageBoardSignature {
              HStack {
                Spacer()
                Text(signature)
                  .font(.system(.caption, design: .monospaced))
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .foregroundStyle(.tertiary)
                  .padding(.top, 8)
                  .padding(.bottom, 8)
                Spacer()
              }
              .serverBackground(.postHeader)
              
              Divider().opacity(self.colorScheme == .light ? 0.7 : 0.3)
            }
            
            if post.username != nil || post.date != nil || post.rawDateString != nil {
              HStack(spacing: 8) {
                Text(post.username ?? "Unknown")
                  .fontWeight(.semibold)
                  .lineLimit(1)
                  .truncationMode(.tail)
                
                Spacer()
                
                if let date = post.date {
                  Text(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date.now))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(post.rawDateString ?? "")
                } else if let rawDate = post.rawDateString {
                  Text(rawDate)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                }
              }
              .textSelection(.enabled)
              .padding(.vertical, 16)
              .padding(.horizontal, 24)
              .serverBackground(.postHeader)
//              Divider()
            }
            
            BoardPostText(text: post.body, canQuote: self.canPost) {
              self.quote(post)
            }
          }
//          .padding(.bottom, 16)
          .serverBackground(.post)
          
//          .background(self.colorScheme == .light ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.thickMaterial))
//          .background(self.colorScheme == .light ? Color(nsColor: .controlBackgroundColor) : Color.clear)
          .clipShape(.rect(cornerRadius: 16))
          .overlay {
            RoundedRectangle(cornerRadius: 16)
              .strokeBorder(.tint, lineWidth: 2)
              .opacity(self.highlightedPost == post.id ? 1 : 0)
          }
          // In the server's theme, the page's color sets the posts apart. Without one, the page is
          // nearly as white as they are.
          .shadow(color: .black.opacity(self.theme == nil ? 0.08 : 0), radius: 2, x: 0, y: 1)
          .contextMenu {
            Button("Quote in New Post", systemImage: "quote.opening") {
              self.quote(post)
            }
            .disabled(!self.canPost)
          }
          .padding(.horizontal, 24)
          
//          Divider()
        }
      }
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
    .defaultScrollAnchor(.top)
    .overlay {
      if !self.model.messageBoardLoaded {
        VStack {
          ProgressView()
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }
}

/// A post's words, as the board shows them: styled as they were written, without the marks, on
/// TextKit 2, as the editor has them. They're selectable all at once, from one end of the post to
/// the other, but not on into the next post, and links go where they go, as they do in chat.
private struct BoardPostText: NSViewRepresentable {
  /// How far in from the post's edges its words are, as its header's are.
  static let inset = NSSize(width: 24, height: 24)

  let text: String
  /// Whether it can be quoted in a new post, which it can't if you can't post.
  var canQuote = false
  var quote: () -> Void = {}

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> BoardPostTextView {
    let textView = BoardPostTextView(usingTextLayoutManager: true)
    textView.configure()
    textView.delegate = context.coordinator
    return textView
  }

  func updateNSView(_ textView: BoardPostTextView, context: Context) {
    context.coordinator.openURL = context.environment.openURL
    textView.canQuote = self.canQuote
    textView.quote = self.quote
    textView.applyServerTheme(context.environment.serverTheme)
    textView.show(self.text)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: BoardPostTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width.isFinite else {
      return nil
    }
    return CGSize(width: width, height: textView.height(forWidth: width))
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var openURL: OpenURLAction?

    // Through SwiftUI's openURL, so hotline:// links stay in the app.
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

/// A post's words on the board, to read, select and copy, but not to change. Selecting in one post
/// leaves nothing selected in the one selected before it, so there's only ever one selection.
///
/// Don't use `layoutManager` here, even to read it. Asking for it switches the view to TextKit 1
/// for good. Use `textLayoutManager` instead.
private final class BoardPostTextView: NSTextView {
  var canQuote = false
  var quote: () -> Void = {}

  /// The post shown, as it's written, so it's only shown again when it changes.
  private var shown: String?
  /// How tall the words are at the width they were last measured at.
  private var measured: (width: CGFloat, height: CGFloat)?
  /// The post with the selection, if any has one.
  private static weak var selecting: BoardPostTextView?
  private var pointerTracking: NSTrackingArea?
  /// For code blocks' backgrounds and quotes' bars, as in the editor, and the link under the
  /// pointer, underlined, as in chat.
  private let fragments = PostFragments.board()

  /// Sets the view up for a post. Separate from init so `init(usingTextLayoutManager:)` can be used.
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
    self.textContainerInset = BoardPostText.inset
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

  func show(_ text: String) {
    guard text != self.shown else {
      return
    }
    self.shown = text
    self.measured = nil
    self.textStorage?.setAttributedString(PostMarkdown.shown(text))
  }

  /// How tall the post's words are, laid out at a width, with the room around them.
  func height(forWidth width: CGFloat) -> CGFloat {
    if let measured = self.measured, measured.width == width {
      return measured.height
    }
    guard let layoutManager = self.textLayoutManager, let container = self.textContainer else {
      return 0
    }
    let inset = BoardPostText.inset
    container.size = NSSize(width: max(width - 2 * inset.width, 1), height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: layoutManager.documentRange)
    let usage = layoutManager.usageBoundsForTextContainer

    // TextKit leaves out the room before the first paragraph and after the last, which, for a code
    // block at the top or bottom of the post, is where its background goes, past its code. So it's
    // made around the words instead, for the block to be as far in from the post's edges as words.
    var above: CGFloat = 0, below: CGFloat = 0
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
      if fragment is PostCodeLineFragment {
        above = max(0, -(fragment.layoutFragmentFrame.minY + fragment.renderingSurfaceBounds.minY))
      }
      return false
    }
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.endLocation, options: .reverse) { fragment in
      if fragment is PostCodeLineFragment {
        below = max(0, fragment.layoutFragmentFrame.minY + fragment.renderingSurfaceBounds.maxY - usage.maxY)
      }
      return false
    }
    self.textContainerInset = NSSize(width: inset.width, height: inset.height + above)

    let height = (usage.height + 2 * inset.height + above + below).rounded(.up)
    self.measured = (width, height)
    return height
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

  /// The link under a point, all of it, if the point's over one, and not just past the end of it,
  /// as the nearest place between two characters can be.
  private func link(at point: NSPoint) -> NSRange? {
    guard let window = self.window, let storage = self.textStorage else {
      return nil
    }
    let screenPoint = window.convertPoint(toScreen: self.convert(point, to: nil))
    let index = self.characterIndex(for: screenPoint)
    guard index != NSNotFound, index < storage.length,
          self.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil).insetBy(dx: -1, dy: -1).contains(screenPoint) else {
      return nil
    }
    var range = NSRange()
    return storage.attribute(.link, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) == nil ? nil : range
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
      for subview in view.subviews {
        if let rect, !subview.convert(subview.bounds, to: self).intersects(rect) {
          continue
        }
        subview.needsDisplay = true
        redraw(subview)
      }
    }
    redraw(self)
  }

  // MARK: Menu

  /// What a text view's menu has for writing, which a post's words aren't for: Cut, Paste, and the
  /// menus for fonts, spelling and substitutions.
  private static let writing: Set<Selector> = [
    #selector(NSText.cut(_:)),
    #selector(NSText.paste(_:)),
    #selector(NSTextView.pasteAsPlainText(_:)),
    #selector(NSFontManager.addFontTrait(_:)),
    #selector(NSText.showGuessPanel(_:)),
    #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
  ]

  // Quote in New Post, as the rest of the post has it, and then what's for words to read and copy.
  override func menu(for event: NSEvent) -> NSMenu? {
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
    menu.insertItem(BoardQuoteMenuItem(canQuote: self.canQuote, quote: self.quote), at: 0)
    menu.insertItem(.separator(), at: 1)
    return menu
  }
}

/// Quote in New Post, in a post's words' menu, which stays off when you can't post, as that menu
/// turns its items on and off itself.
private final class BoardQuoteMenuItem: NSMenuItem, NSMenuItemValidation {
  private let canQuote: Bool
  private let quote: () -> Void

  init(canQuote: Bool, quote: @escaping () -> Void) {
    self.canQuote = canQuote
    self.quote = quote
    super.init(title: "Quote in New Post", action: #selector(BoardQuoteMenuItem.choose), keyEquivalent: "")
    self.target = self
    self.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: nil)
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func choose() {
    self.quote()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    self.canQuote
  }
}

#Preview {
  MessageBoardView()
    .environment(HotlineState())
}
