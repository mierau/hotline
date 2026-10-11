import SwiftUI
import AppKit

/// The chat transcript, on TextKit 2. A drop-in for ChatTextView with the same inputs, plus what
/// links to Hotline servers do.
struct ChatTranscriptView: NSViewRepresentable {
  let messages: [ChatMessage]
  var searchQuery: String = ""
  var watchWords: [HighlightWord] = []
  var isFiltered: Bool = false
  var cachedText: NSAttributedString?
  var cachedCount: Int = 0
  var onCacheUpdate: ((NSAttributedString, Int) -> Void)?
  var openURL: ((URL) -> Void)?
  /// What clicking a hotline:// link does, for its tooltip. Nil if it does nothing.
  var describeHotlineLink: ((URL) -> String?)?
  /// The menu for a link to a file.
  var fileLinkMenu: ((URL) -> NSMenu?)?
  /// The menu for whoever sent a message, from their name and the icon they had.
  var userMenu: ((_ name: String, _ iconID: UInt?) -> NSMenu?)?
  /// Whether messages have their sender's icon before them.
  var showsIcons = true
  /// Whether links to images have a preview under them.
  var previewsImages = true
  /// Whether people connecting and disconnecting are shown, among the messages.
  var showsConnections = true
  /// Asked for older messages, as the start of what's shown comes near.
  var onNearStart: (() -> Void)?
  /// Told when the view leaves the newest message, or comes back to it.
  var onAtBottomChange: ((Bool) -> Void)?
  /// Goes to the newest message each time this changes.
  var scrollToNewest = 0

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    coordinator.saveForLater()
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = ChatTranscriptTextView(usingTextLayoutManager: true)
    textView.configure()

    // The text view is the document, so NSTextView keeps the chat still as it scrolls back.
    let scrollView = ChatTranscriptScrollView()
    scrollView.documentView = textView
    textView.autoresizingMask = [.width]
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
    coordinator.onCacheUpdate = self.onCacheUpdate
    let theme = context.environment.serverTheme
    coordinator.options = ChatMessageRenderer.Options(showsIcons: self.showsIcons, previewsImages: self.previewsImages, showsConnections: self.showsConnections, adminColor: theme?.admin, secondaryColor: theme?.secondaryText, tertiaryColor: theme?.tertiaryText)

    if let textView = coordinator.textView {
      textView.applyServerTheme(theme)
      textView.tertiaryColor = theme?.tertiaryText
      textView.openURLAction = self.openURL
      let openWindow = context.environment.openWindow
      textView.openImageAction = { url in
        openWindow(id: "preview-quicklook", value: PreviewFileInfo(webImage: url))
      }
      textView.describeHotlineLink = self.describeHotlineLink
      textView.fileLinkMenu = self.fileLinkMenu
      textView.userMenu = self.userMenu
      // Before the text changes, so new messages are highlighted the new way.
      textView.highlights = ChatTranscriptTextView.Highlights(query: self.searchQuery, watchWords: self.watchWords)
    }

    coordinator.onNearStart = self.onNearStart
    coordinator.onAtBottomChange = self.onAtBottomChange
    if self.scrollToNewest != coordinator.scrollToNewest {
      coordinator.scrollToNewest = self.scrollToNewest
      coordinator.scrollToBottom()
    }
    coordinator.update(
      messages: self.messages,
      isFiltered: self.isFiltered,
      cachedText: self.isFiltered ? nil : self.cachedText,
      cachedCount: self.isFiltered ? 0 : self.cachedCount
    )
    coordinator.textView?.updateHighlights()
    // A chat too short to scroll starts in view, and needs no scrolling to ask for more.
    DispatchQueue.main.async {
      coordinator.checkNearStart()
      coordinator.reportAtBottom()
    }
  }

  // MARK: - Coordinator

  final class Coordinator {
    weak var textView: ChatTranscriptTextView?
    weak var scrollView: NSScrollView? {
      didSet { self.observeScrolling() }
    }
    var onCacheUpdate: ((NSAttributedString, Int) -> Void)?
    var onNearStart: (() -> Void)?
    var onAtBottomChange: ((Bool) -> Void)?
    var scrollToNewest = 0
    /// Where the view was last said to be, which a new one always says.
    private var wasAtBottom: Bool?
    /// How messages are shown. When the settings change, or the server's theme, every message is
    /// rendered again.
    var options = ChatMessageRenderer.Options() {
      didSet {
        if self.options != oldValue {
          self.renderedMessages = [:]
          self.renderedContinuations = [:]
          self.savedText = nil
          self.savedRanges = nil
          self.needsRebuild = true
        }
      }
    }
    private var needsRebuild = false
    /// Whether the text's being brought up to date, which scrolls through places that aren't where
    /// it ends up.
    private var isUpdating = false
    /// Whether the text is search results, rather than the chat.
    private var isShowingResults = false

    /// The messages in the text view, in order.
    private var renderedIDs: [UUID] = []
    private var renderedCount: Int { self.renderedIDs.count }
    /// Each message's text, kept so search results and the chat can be put back together without
    /// rendering every message again: on its own, and going on from the message before it, since
    /// the same message can be either, as in search results.
    private var renderedMessages: [UUID: NSAttributedString] = [:]
    private var renderedContinuations: [UUID: NSAttributedString] = [:]
    /// The saved text the chat was opened from. Until a message is in `renderedMessages`, its
    /// text is cut from this rather than rendered again.
    private var savedText: NSAttributedString?
    /// Where each message is in `savedText`, found the first time one's needed.
    private var savedRanges: [UUID: NSRange]?
    private var scrollObserver: NSObjectProtocol?

    deinit {
      if let observer = self.scrollObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }

    private func observeScrolling() {
      if let observer = self.scrollObserver {
        NotificationCenter.default.removeObserver(observer)
      }
      guard let clipView = self.scrollView?.contentView else {
        return
      }
      clipView.postsBoundsChangedNotifications = true
      self.scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
        self?.textView?.viewDidScroll()
        self?.checkNearStart()
        self?.reportAtBottom()
      }
    }

    /// Says when the view's left the newest message, or come back to it, once it's settled.
    func reportAtBottom() {
      guard let onAtBottomChange = self.onAtBottomChange, !self.isUpdating, let textView = self.textView else {
        return
      }
      let atBottom = textView.isAtBottom
      if atBottom != self.wasAtBottom {
        self.wasAtBottom = atBottom
        onAtBottomChange(atBottom)
      }
    }

    /// Asks for older messages once the start of what's shown is within a couple of screens.
    func checkNearStart() {
      guard let onNearStart = self.onNearStart, !self.isUpdating, !self.renderedIDs.isEmpty,
            let textView = self.textView, let clipView = self.scrollView?.contentView,
            let distance = textView.distanceFromStart, distance < clipView.bounds.height * 2 else {
        return
      }
      onNearStart()
    }

    /// A message's text, rendered once each way.
    private func rendered(_ message: ChatMessage, continuing: Bool) -> NSAttributedString {
      if let text = continuing ? self.renderedContinuations[message.id] : self.renderedMessages[message.id] {
        return text
      }
      let text = self.savedRender(of: message, continuing: continuing) ?? ChatMessageRenderer.render(message, continuing: continuing, options: self.options)
      if continuing {
        self.renderedContinuations[message.id] = text
      }
      else {
        self.renderedMessages[message.id] = text
      }
      return text
    }

    /// A message's text from the saved text, if it's there, rendered the same way.
    private func savedRender(of message: ChatMessage, continuing: Bool) -> NSAttributedString? {
      guard let savedText = self.savedText else {
        return nil
      }
      if self.savedRanges == nil {
        var ranges: [UUID: NSRange] = [:]
        savedText.enumerateAttribute(ChatMessageRenderer.messageIDKey, in: NSRange(location: 0, length: savedText.length)) { value, range, _ in
          if let id = value as? UUID {
            ranges[id] = range
          }
        }
        self.savedRanges = ranges
      }
      guard let range = self.savedRanges?[message.id],
            (savedText.attribute(ChatMessageRenderer.groupedKey, at: range.location, effectiveRange: nil) != nil) == continuing else {
        return nil
      }
      return savedText.attributedSubstring(from: range)
    }

    /// Marks the text the chat is saved as with how it was rendered, since only text rendered the
    /// way the settings now ask can be used again.
    private static let renderingKey = NSAttributedString.Key("chatRendering")

    private var rendering: String {
      "icons \(self.options.showsIcons), previews \(self.options.previewsImages), connections \(self.options.showsConnections), admins \(self.options.adminColor?.description ?? "red"), secondary \(self.options.secondaryColor?.description ?? "system"), tertiary \(self.options.tertiaryColor?.description ?? "system")"
    }

    /// Keeps the chat's text for when it's shown again, as it goes, rather than copying all of it
    /// with each message.
    func saveForLater() {
      if let storage = self.textView?.textStorage {
        self.saveText(storage)
      }
    }

    private func saveText(_ storage: NSTextStorage) {
      guard let onCacheUpdate = self.onCacheUpdate, !self.isShowingResults else {
        return
      }
      let text = NSMutableAttributedString(attributedString: storage)
      if text.length > 0 {
        text.addAttribute(Self.renderingKey, value: self.rendering, range: NSRange(location: 0, length: 1))
      }
      onCacheUpdate(text, self.renderedCount)
    }

    /// Whether messages in a row from the same person go together, which they don't in search
    /// results, where they weren't next to each other.
    private func continues(_ messages: [ChatMessage], at index: Int, isFiltered: Bool) -> Bool {
      !isFiltered && index > 0 && ChatMessageRenderer.continues(messages[index], after: messages[index - 1])
    }

    // MARK: Updating

    /// Brings the text up to date with `messages`. New messages are appended, and ones that fell
    /// off the front (the chat keeps only the latest couple thousand) are deleted from the top.
    /// Any other change, like restored history or search results, rebuilds the text.
    func update(messages: [ChatMessage], isFiltered: Bool, cachedText: NSAttributedString?, cachedCount: Int) {
      let messages = self.options.showsConnections ? messages : Self.withoutConnections(messages)
      self.isUpdating = true
      defer {
        self.isUpdating = false
      }
      // The chat, kept before search results take its place, to come back to when they're gone.
      if isFiltered, !self.isShowingResults, self.renderedCount > 0 {
        self.saveForLater()
      }
      defer {
        self.isShowingResults = isFiltered
      }
      if self.needsRebuild {
        self.needsRebuild = false
        self.rebuild(messages: messages, isFiltered: isFiltered, cachedText: cachedText, cachedCount: cachedCount)
      }
      else if let dropped = self.droppedFromFront(of: messages) {
        if dropped > 0 || messages.count > self.renderedCount - dropped {
          self.trimAndAppend(messages: messages, dropped: dropped, isFiltered: isFiltered)
        }
      }
      else if let added = self.addedToFront(of: messages) {
        self.prepend(messages: messages, added: added, isFiltered: isFiltered)
      }
      else if !messages.isEmpty || !self.renderedIDs.isEmpty {
        self.rebuild(messages: messages, isFiltered: isFiltered, cachedText: cachedText, cachedCount: cachedCount)
      }

      // Keep only the messages still in the chat. Search results are some of them.
      if !isFiltered && self.renderedMessages.count + self.renderedContinuations.count > messages.count + ChatTranscriptView.renderedMessageSlack {
        let current = Set(messages.map(\.id))
        self.renderedMessages = self.renderedMessages.filter { current.contains($0.key) }
        self.renderedContinuations = self.renderedContinuations.filter { current.contains($0.key) }
      }
    }

    /// The messages without people connecting and disconnecting, as if they weren't there: with one
    /// date divider between sessions that had nothing else in them, rather than two together.
    private static func withoutConnections(_ messages: [ChatMessage]) -> [ChatMessage] {
      var shown: [ChatMessage] = []
      shown.reserveCapacity(messages.count)
      for message in messages where !message.isConnection {
        if message.type == .signOut, shown.last?.type == .signOut {
          continue
        }
        shown.append(message)
      }
      return shown
    }

    /// How many of the rendered messages are gone from the front of `messages`, if the rest are
    /// still there in the same order. Nil for any other kind of change.
    private func droppedFromFront(of messages: [ChatMessage]) -> Int? {
      guard let firstID = messages.first?.id, let lastRenderedID = self.renderedIDs.last else {
        return nil
      }
      // Usually nothing was dropped, so check the front before searching.
      guard let dropped = self.renderedIDs.first == firstID ? 0 : self.renderedIDs.firstIndex(of: firstID) else {
        return nil
      }
      let keptCount = self.renderedCount - dropped
      guard messages.count >= keptCount, messages[keptCount - 1].id == lastRenderedID else {
        return nil
      }
      return dropped
    }

    /// How many messages are new at the front of `messages`, if the rendered ones follow them, in the
    /// same order, maybe with new ones after. Nil for any other kind of change.
    private func addedToFront(of messages: [ChatMessage]) -> Int? {
      guard let firstID = self.renderedIDs.first, let lastID = self.renderedIDs.last,
            let added = messages.firstIndex(where: { $0.id == firstID }), added > 0,
            messages.count >= added + self.renderedCount,
            messages[added + self.renderedCount - 1].id == lastID else {
        return nil
      }
      return added
    }

    /// Puts older messages above the ones shown, keeping what's in view where it is, and adds any
    /// new ones after.
    private func prepend(messages: [ChatMessage], added: Int, isFiltered: Bool) {
      guard let textView = self.textView, let storage = textView.textStorage else {
        return
      }
      let readingPosition = textView.anchorAtStart()
      textView.clearHoveredLink()

      let front = NSMutableAttributedString()
      for index in 0..<added {
        front.append(self.rendered(messages[index], continuing: self.continues(messages, at: index, isFiltered: isFiltered)))
        front.append(NSAttributedString(string: "\n"))
      }

      storage.beginEditing()
      // The message that was first, which may now go on from the one before it.
      var firstRange = NSRange(location: 0, length: 0)
      var firstGrowth = 0
      if storage.length > 0, self.continues(messages, at: added, isFiltered: isFiltered) {
        _ = storage.attribute(ChatMessageRenderer.messageIDKey, at: 0, longestEffectiveRange: &firstRange, in: NSRange(location: 0, length: storage.length))
        let first = self.rendered(messages[added], continuing: true)
        storage.replaceCharacters(in: firstRange, with: first)
        firstGrowth = first.length - firstRange.length
      }
      storage.insert(front, at: 0)
      storage.endEditing()

      self.renderedIDs.insert(contentsOf: messages[..<added].map(\.id), at: 0)
      textView.textWasReplaced()
      textView.invalidateToolTips()

      // What was in view, back where it was, below what came in.
      switch readingPosition {
      case .message(let offset, let distance):
        var moved = offset + front.length
        if firstRange.length > 0, offset >= NSMaxRange(firstRange) {
          moved += firstGrowth
        }
        textView.keep(inPlace: .message(offset: moved, distance: distance))
      case .bottom:
        self.scrollToBottom()
      case .top:
        break
      }

      if messages.count > self.renderedCount {
        self.trimAndAppend(messages: messages, dropped: 0, isFiltered: isFiltered)
      }
    }

    private func rebuild(messages: [ChatMessage], isFiltered: Bool, cachedText: NSAttributedString?, cachedCount: Int) {
      guard let textView = self.textView, let storage = textView.textStorage else {
        return
      }
      textView.clearHoveredLink()

      if let cachedText, cachedCount == messages.count, cachedCount > 0,
         cachedText.attribute(Self.renderingKey, at: 0, effectiveRange: nil) as? String == self.rendering {
        storage.setAttributedString(cachedText)
        if self.savedText !== cachedText {
          self.savedText = cachedText
          self.savedRanges = nil
        }
      }
      else {
        let text = NSMutableAttributedString()
        for (index, message) in messages.enumerated() {
          if index > 0 {
            text.append(NSAttributedString(string: "\n"))
          }
          text.append(self.rendered(message, continuing: self.continues(messages, at: index, isFiltered: isFiltered)))
        }
        storage.setAttributedString(text)
        self.renderedIDs = messages.map(\.id)
      }

      self.renderedIDs = messages.map(\.id)
      textView.invalidateToolTips()
      textView.textWasReplaced()
      self.scrollToBottom()
    }

    /// Deletes the first `dropped` rendered messages from the top of the text and appends the
    /// messages after the ones that stay.
    private func trimAndAppend(messages: [ChatMessage], dropped: Int, isFiltered: Bool) {
      guard let textView = self.textView, let storage = textView.textStorage else {
        return
      }

      // Everything before the first message that stays: the dropped messages and their newlines.
      var removedLength = 0
      if dropped > 0 {
        guard let start = self.start(ofMessage: messages[0].id, in: storage) else {
          self.rebuild(messages: messages, isFiltered: isFiltered, cachedText: nil, cachedCount: 0)
          return
        }
        removedLength = start
      }

      let wasAtBottom = self.isScrolledToBottom()
      // Scrolled back through the chat, the text removed from the top would otherwise pull what
      // you're reading up the screen.
      let readingPosition = (wasAtBottom || removedLength == 0) ? nil : textView.anchor()
      if removedLength > 0 {
        textView.clearHoveredLink()
      }

      let firstNew = self.renderedCount - dropped
      let newMessages = messages[firstNew...]
      let appended = NSMutableAttributedString()
      for index in firstNew..<messages.count {
        appended.append(NSAttributedString(string: "\n"))
        appended.append(self.rendered(messages[index], continuing: self.continues(messages, at: index, isFiltered: isFiltered)))
      }

      storage.beginEditing()
      // How much the message now first changes length, going from part of a group to its start.
      var firstRange = NSRange(location: 0, length: 0)
      var firstGrowth = 0
      if removedLength > 0 {
        storage.deleteCharacters(in: NSRange(location: 0, length: removedLength))
        if storage.length > 0, storage.attribute(ChatMessageRenderer.groupedKey, at: 0, effectiveRange: nil) != nil {
          _ = storage.attribute(ChatMessageRenderer.messageIDKey, at: 0, longestEffectiveRange: &firstRange, in: NSRange(location: 0, length: storage.length))
          let first = self.rendered(messages[0], continuing: false)
          storage.replaceCharacters(in: firstRange, with: first)
          firstGrowth = first.length - firstRange.length
        }
      }
      storage.append(appended)
      storage.endEditing()
      // Removing text from the top moves everything after it, highlights included.
      if removedLength > 0 {
        textView.textWasReplaced()
      }
      else {
        textView.textWasAppended(NSRange(location: storage.length - appended.length, length: appended.length))
      }

      self.renderedIDs.removeFirst(dropped)
      self.renderedIDs.append(contentsOf: newMessages.map(\.id))
      textView.invalidateToolTips()

      if wasAtBottom {
        self.scrollToBottom()
      }
      else if case .message(let offset, let distance)? = readingPosition {
        var offset = offset - removedLength
        if offset >= NSMaxRange(firstRange) && firstRange.length > 0 {
          offset += firstGrowth
        }
        textView.scroll(to: .message(offset: offset, distance: distance))
      }
    }

    /// Where a rendered message starts in the text.
    private func start(ofMessage id: UUID, in storage: NSTextStorage) -> Int? {
      var start: Int?
      storage.enumerateAttribute(ChatMessageRenderer.messageIDKey, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
        if (value as? UUID) == id {
          start = range.location
          stop.pointee = true
        }
      }
      return start
    }

    // MARK: Scrolling

    func isScrolledToBottom() -> Bool {
      self.textView?.isAtBottom ?? true
    }

    /// Shows the newest messages. The end of the chat is laid out first so its height there is
    /// exact rather than estimated.
    func scrollToBottom() {
      self.pinToBottom()
      // The text view settles its height after this pass of layout, so check again after it.
      DispatchQueue.main.async { [weak self] in
        self?.pinToBottom()
      }
    }

    private func pinToBottom() {
      guard let textView = self.textView, let textLayoutManager = textView.textLayoutManager else {
        return
      }
      textLayoutManager.ensureLayout(for: NSTextRange(location: textLayoutManager.documentRange.endLocation))
      textView.fit(keepingBottom: true)
      textView.updateToolTips()
    }
  }

  /// How many more rendered messages than the chat holds to keep before clearing out old ones.
  fileprivate static let renderedMessageSlack = 500
}
