import SwiftUI

// MARK: - Editor

/// The post's text, styled as the board will show it as it's written.
struct PostEditor: NSViewRepresentable {
  /// Where the text starts in the card, which the card's top and its placeholder line up with.
  static let inset = NSSize(width: 16, height: 14)

  @Environment(\.serverTheme) private var theme

  @Binding var text: String
  let controller: MarkdownEditor
  /// Room past the last line, to scroll it up past what's over the bottom of the editor.
  var bottomInset: CGFloat = 0
  /// Whether you start writing here, once it's shown, or somewhere else, as in a title.
  var startsHere = true
  /// How far in from its edges the text is, as far as what's around it is in.
  var inset: NSSize = Self.inset
  /// How it's laid out as it's written, as the board does, or with words alone, as a broadcast is.
  var layout: Markdown.Layout = .board
  /// What's done once you're done writing, and you've gone on to something else.
  var onEndEditing: (() -> Void)? = nil

  func makeCoordinator() -> Coordinator {
    Coordinator(text: self.$text, controller: self.controller, layout: self.layout)
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
    textView.textContainerInset = self.inset
    // From the inset, as the card's top and the placeholder are.
    textView.textContainer?.lineFragmentPadding = 0
    // For pictures dropped on it, as well as text, where they can be drawings.
    textView.takesPictures = self.layout.blocks
    textView.updateDragTypeRegistration()
    textView.font = self.layout.font
    context.coordinator.attach(textView)
    textView.string = self.text
    textView.applyServerTheme(self.theme)

    scrollView.drawsBackground = false
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: self.bottomInset, right: 0)

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
    context.coordinator.onEndEditing = self.onEndEditing
    if textView.string != self.text {
      textView.string = self.text
    }
    textView.applyServerTheme(self.theme)
    context.coordinator.use(Markdown.Colors(theme: self.theme), in: textView)
    self.controller.textView = textView
  }

  final class Coordinator: MarkdownTextCoordinator {
    var text: Binding<String>
    var onEndEditing: (() -> Void)?

    init(text: Binding<String>, controller: MarkdownEditor, layout: Markdown.Layout) {
      self.text = text
      super.init(editor: controller, layout: layout)
    }

    override func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else {
        return
      }
      self.text.wrappedValue = textView.string
    }

    override func textDidEndEditing(_ notification: Notification) {
      self.onEndEditing?()
    }
  }
}

/// The post's text view, where a picture dropped or pasted in goes in as a drawing of it. Rich text
/// pasted goes in as Markdown, as it does wherever Markdown's written. See `MarkdownEditingTextView`.
final class PostTextView: MarkdownEditingTextView {
  // MARK: Pictures

  /// Whether a picture goes in as a drawing, which needs lines of its own, and not where they're
  /// words alone.
  var takesPictures = true

  /// Picture files, and pictures, as well as text.
  private static let pictureTypes: [NSPasteboard.PasteboardType] = [.fileURL, .tiff, .png]

  override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
    let types = super.readablePasteboardTypes
    return self.takesPictures ? types + Self.pictureTypes.filter { !types.contains($0) } : types
  }

  override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
    let types = super.acceptableDragTypes
    return self.takesPictures ? types + Self.pictureTypes.filter { !types.contains($0) } : types
  }

  override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
    self.takesPictures && PostPicture.hasPicture(dragInfo.draggingPasteboard) ? .copy : super.dragOperation(for: dragInfo, type: type)
  }

  // Where it's dropped, or what's selected, as for a paste.
  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
    guard self.takesPictures, PostPicture.hasPicture(pboard) else {
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

/// The formatting a post, or a message, can have, a click away: the styles, as the Format menu has
/// them, then Link, with what's on where you're writing shown as on, as choosing it again takes it
/// off. In a sheet's bottom bar, or in glass over the bottom of what's written. Their keys are the
/// Format menu's.
struct PostFormattingBar: View {
  /// How tall it is: its buttons, and the glass around them.
  static let height: CGFloat = PostFormatButton.height + 2 * Self.padding
  private static let padding: CGFloat = 3

  let editor: MarkdownEditor
  /// Whether it's in a sheet's bottom bar, without glass of its own around its buttons.
  var inToolbar = false

  var body: some View {
    if self.inToolbar {
      self.buttons
    }
    else {
      self.buttons
        .padding(Self.padding)
        .modifier(PostFormattingBackground())
    }
  }

  private var buttons: some View {
    HStack(spacing: 0) {
      ForEach(MarkdownStyle.allCases, id: \.self) { style in
        PostFormatButton(style.title, systemImage: style.systemImage, shortcut: style.shortcut, isOn: self.editor.activeStyles.contains(style)) {
          self.editor.toggle(style)
        }
        .disabled(!self.editor.allows(style))
      }

      // Between the styles and Link, as the Format menu has a line.
      Rectangle()
        .fill(.separator)
        .frame(width: 1, height: 14)
        .padding(.horizontal, 4)

      PostFormatButton("Link", systemImage: "link", shortcut: MarkdownEditor.linkShortcut, isOn: self.editor.inLink) {
        self.editor.link()
      }
      .disabled(!self.editor.allowsLink)
    }
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

/// A formatting button: its symbol, in a capsule that's filled while what it's for is on, faintly
/// while the pointer's over it, and that gives a little as it's pressed, and its name and its key in
/// the Format menu as its help.
struct PostFormatButton: View {
  static let height: CGFloat = 26

  let title: String
  let systemImage: String
  let shortcut: KeyboardShortcut
  var isOn = false
  let action: () -> Void

  @State private var hovered: Bool = false

  init(_ title: String, systemImage: String, shortcut: KeyboardShortcut, isOn: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.shortcut = shortcut
    self.isOn = isOn
    self.action = action
  }

  var body: some View {
    Button(action: self.action) {
      Image(systemName: self.systemImage)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 32, height: Self.height)
        .contentShape(.capsule)
    }
    .buttonStyle(PostFormatButtonStyle(isOn: self.isOn, hovered: self.hovered))
    .help("\(self.title) (\(self.shortcutText))")
    .accessibilityLabel(self.title)
    .accessibilityAddTraits(self.isOn ? .isSelected : [])
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        self.hovered = hovering
      }
    }
  }

  /// The key, as menus show it.
  private var shortcutText: String {
    (self.shortcut.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + String(self.shortcut.key.character).uppercased()
  }
}

/// How a formatting button looks: in the text's color, as any button that's on, and faint when it's
/// off, in a capsule filled while what it's for is on, or pressed, and faintly while the pointer's
/// over it, and a little smaller while it's pressed.
private struct PostFormatButtonStyle: ButtonStyle {
  let isOn: Bool
  let hovered: Bool

  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let filled = self.isEnabled && (self.isOn || configuration.isPressed)
    configuration.label
      .foregroundStyle(self.isEnabled ? .primary : .tertiary)
      .background {
        Capsule()
          .fill(filled ? AnyShapeStyle(.fill) : AnyShapeStyle(.fill.tertiary))
          .opacity(filled || (self.hovered && self.isEnabled) ? 1 : 0)
      }
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.12), value: self.isOn)
  }
}
