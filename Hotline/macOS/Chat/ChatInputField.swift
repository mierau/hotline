import SwiftUI
import AppKit

/// A chat input field that supports:
/// - **Enter**: Send message
/// - **Option+Enter**: Send as announcement
/// - **Shift+Enter**: Insert newline, going on with a list or a quote
/// - **Tab**: Complete the name being typed, then the next name that fits; **Shift+Tab** goes back.
///   In a link or a code block, Tab does what it does in a post.
/// - **/**: A command, like /me or /msg, from a list above the field of the ones that fit what's
///   typed, then of who it's for, with what's left to type in gray after the caret. Up and Down
///   choose in the list, Tab puts in what's chosen, Return does too, or runs the command once it's
///   typed, and Escape hides the list.
///
/// Markdown is styled as it's typed, as in a post's editor: marks faint, and bold bold.
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
  /// What the Format menu works through, for Markdown in what you're typing.
  var markdownEditor: MarkdownEditor
  /// The list shown above the field while a command's typed, or nil for a field without commands.
  var commands: ChatCommandList? = nil
  /// Where commands are typed, for what they can do there, and who for.
  var commandContext: () -> ChatCommandContext = { ChatCommandContext() }
  /// Does what a command asks, once it's typed with nothing wrong with it.
  var onCommand: (ChatCommandRequest) -> Void = { _ in }
  /// Sends a message, or an announcement: what's typed, but for a slash that isn't a command, like
  /// the first of the two in “//shrug”, which isn't sent.
  var onSubmit: (_ message: String, _ announce: Bool) -> Void

  /// How what's typed is laid out: in the chat's font, with lines as close as plain text's, so the
  /// field's as tall as it was before it was styled.
  static let layout = Markdown.Layout(font: .systemFont(ofSize: NSFont.systemFontSize), lineSpacing: 0, imagePreviews: 0)

  /// A line's height, with nothing on it.
  static let lineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: Self.layout.font))

  /// Single-line height matching what `recalculateHeight` computes for an empty field.
  static let defaultHeight: CGFloat = Self.lineHeight + ChatInputTextView.verticalInset * 2

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
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.font = Self.layout.font
    textView.drawsBackground = false
    textView.updateInsets()
    textView.textContainer?.lineFragmentPadding = 0

    context.coordinator.attach(textView)
    textView.submitHandler = { [weak coordinator = context.coordinator] announce in
      coordinator?.submit(announce: announce)
    }
    textView.namesToComplete = { [weak coordinator = context.coordinator] in
      coordinator?.parent.namesToComplete() ?? []
    }
    // The list of commands only while the field has the keys.
    textView.focusHandler = { [weak coordinator = context.coordinator] focused in
      if focused {
        coordinator?.updateCommands(edited: false)
      }
      else {
        coordinator?.parent.commands?.hide()
      }
    }
    self.commands?.choose = { [weak coordinator = context.coordinator] index in
      coordinator?.choose(index, by: .click)
    }
    // Nothing from a field before this one, after SwiftUI's done making it.
    DispatchQueue.main.async { [commands = self.commands] in
      commands?.hide()
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
    // A command, and who it's for, in the accent, as the caret is, and what's left to type of it as
    // faint as what matters least in the chat.
    context.coordinator.commandColor = context.environment.serverTheme?.accent ?? .controlAccentColor
    textView.hintColor = context.environment.serverTheme?.tertiaryText ?? .placeholderTextColor
    context.coordinator.use(Markdown.Colors(theme: context.environment.serverTheme), in: textView)
    // A generic one for an icon this copy of Hotline doesn't have.
    textView.icon = self.iconID.flatMap { HotlineState.getClassicIcon($0) ?? NSImage(named: "User") }
    // Dimmed while the window isn't in front, as the sidebar's icons are.
    textView.dimsIcon = context.environment.controlActiveState == .inactive
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
        // As it is now, as for a draft that's come back, or an empty field once it's sent.
        context.coordinator.updateCommands(edited: true)
      }
    }
  }

  class Coordinator: MarkdownTextCoordinator {
    var parent: ChatInputField
    weak var textView: ChatInputTextView?
    weak var scrollView: NSScrollView?

    /// How a row in the list of commands is chosen, for what choosing it does.
    enum Choice {
      case tab
      case returnKey
      case click
    }

    /// The color a command's name is in once it's typed, and who it's for: the server's accent, or
    /// the system's.
    var commandColor: NSColor = .controlAccentColor {
      didSet {
        if self.commandColor != oldValue, let storage = self.textView?.textStorage {
          self.highlightCommand(in: storage)
        }
      }
    }
    /// Whether Escape's hidden the list of commands, until what's typed changes.
    fileprivate var listDismissed = false
    /// People chosen from the list, of everyone with a name, for which of them a command's for.
    fileprivate var chosen: Set<UInt16> = []
    /// What's typed for who a command's for, when Return found that it isn't clear who that is, for
    /// someone chosen from the list to go in place of.
    fileprivate var problemName: NSRange?
    /// The colors what's typed was last styled in, for styling a command's again when they change.
    private var styledColors: Markdown.Colors?

    init(_ parent: ChatInputField) {
      self.parent = parent
      super.init(editor: parent.markdownEditor, layout: ChatInputField.layout)
    }

    override func textDidChange(_ notification: Notification) {
      guard let textView = self.textView else { return }
      self.parent.text = textView.string
      self.recalculateHeight()
      self.updateCommands(edited: true)
    }

    override func textViewDidChangeSelection(_ notification: Notification) {
      super.textViewDidChangeSelection(notification)
      self.updateCommands(edited: false)
    }

    override func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if let list = self.parent.commands, list.isShown, self.handleListKey(commandSelector, in: list) {
        return true
      }
      return super.textView(textView, doCommandBy: commandSelector)
    }

    override func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
      super.textStorage(textStorage, didProcessEditing: editedMask, range: editedRange, changeInLength: delta)
      if editedMask.contains(.editedCharacters) {
        self.highlightCommand(in: textStorage)
      }
    }

    override func use(_ colors: Markdown.Colors, in textView: NSTextView) {
      super.use(colors, in: textView)
      // Styled again in them, which takes a command's color out.
      if colors != self.styledColors {
        self.styledColors = colors
        if let storage = textView.textStorage {
          self.highlightCommand(in: storage)
        }
      }
    }

    /// The arrow keys move in the list of commands, Tab puts in what's chosen in it, and Escape
    /// hides it. Whether the key was for the list.
    private func handleListKey(_ selector: Selector, in list: ChatCommandList) -> Bool {
      // Icons are in a grid, which the arrows move in, across and up and down.
      let down = list.isGrid ? list.iconColumns : 1
      switch selector {
      case #selector(NSResponder.moveUp(_:)) where !list.rows.isEmpty:
        list.move(by: -down)
      case #selector(NSResponder.moveDown(_:)) where !list.rows.isEmpty:
        list.move(by: down)
      case #selector(NSResponder.moveLeft(_:)) where list.isGrid:
        list.move(by: -1)
      case #selector(NSResponder.moveRight(_:)) where list.isGrid:
        list.move(by: 1)
      case #selector(NSResponder.insertTab(_:)) where !list.rows.isEmpty:
        self.choose(list.selection, by: .tab)
      case #selector(NSResponder.cancelOperation(_:)):
        self.listDismissed = true
        list.hide()
      default:
        return false
      }
      return true
    }

    func recalculateHeight() {
      guard let textView = self.textView else { return }

      let lineHeight = ChatInputField.lineHeight
      let maxContentHeight = ceil(lineHeight * CGFloat(self.parent.maxLines))

      // TextKit 2 first, as asking for the layout manager switches a text view to TextKit 1, which
      // can't draw code blocks' backgrounds and quotes' bars.
      let contentHeight: CGFloat
      if let textLayoutManager = textView.textLayoutManager {
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let usageBounds = textLayoutManager.usageBoundsForTextContainer
        contentHeight = max(ceil(usageBounds.height), lineHeight)
      } else if let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer {
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        contentHeight = max(ceil(usedRect.height), lineHeight)
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

// MARK: - Commands

extension ChatInputField.Coordinator {
  /// Shows in the list what fits the command being typed, when one is: the commands that start with
  /// what's typed of its name, or the people it could be for, whose names start with what's typed
  /// of theirs. What's left to type of it goes in gray after the caret. What's wrong with what was
  /// typed, as Return found it, stays until it's changed, and Escape hides the list until then too.
  func updateCommands(edited: Bool) {
    guard let textView = self.textView, let list = self.parent.commands else {
      return
    }
    if edited {
      self.listDismissed = false
      self.problemName = nil
    }
    let text = textView.string
    let selection = textView.selectedRange()
    guard text.hasPrefix("/"), !textView.hasMarkedText() else {
      list.hide()
      textView.commandHint = nil
      self.chosen = []
      return
    }
    let context = self.parent.commandContext()
    textView.commandHint = self.hint(for: text, selection: selection, in: context)
    if !edited, list.problem != nil {
      return
    }
    guard !self.listDismissed, selection.length == 0, textView.window?.firstResponder === textView else {
      list.hide()
      return
    }
    switch ChatCommandPlace(text: text, caret: selection.location, in: context) {
    case .name(let typed, _):
      list.show(ChatCommand.matching(typed, in: context).map { .command($0) }, inPrivateChat: context.isPrivateChat)
    case .person(let command, let typed, let range):
      var candidates = command.candidates(in: context)
      // Not those named before it.
      if command.argument == .people {
        let start = Self.argumentsStart(in: text)
        let before = (text as NSString).substring(with: NSRange(location: start, length: max(range.location - start, 0)))
        let named = Set(ChatCommand.names(in: before, among: context.people).names.flatMap { $0.people.map(\.id) })
        candidates.removeAll { named.contains($0.id) }
      }
      list.show(ChatCommand.people(matching: typed, among: candidates).map { .person($0) }, inPrivateChat: context.isPrivateChat)
    case .icon(let typed, _):
      // Those whose numbers start with what's typed, as Settings has them, with the one typed, or
      // with nothing typed, yours, chosen.
      let icons = HotlineState.classicIconSet.filter { String($0).hasPrefix(typed) }
      let yours = context.people.first(where: { $0.id == context.ownUserID }).map { Int($0.iconID) }
      let current = typed.isEmpty ? yours : Int(typed)
      list.show(icons.map { .icon($0) }, inPrivateChat: context.isPrivateChat, selecting: current.map { .icon($0) })
    case .after, nil:
      list.hide()
    }
  }

  /// Return: chooses the row selected in the list of commands, while it has rows, or else runs the
  /// command that's typed, or sends what's typed.
  func submit(announce: Bool) {
    guard let textView = self.textView else {
      return
    }
    if let list = self.parent.commands, !list.rows.isEmpty {
      self.choose(list.selection, by: .returnKey)
      return
    }
    self.send(textView.string, announce: announce)
  }

  /// Puts in what a row in the list stands for, in place of what's typed of it: a command's name,
  /// someone's, or the command that was meant. Return on a command that's typed all the way runs it
  /// instead, when nothing has to be typed after it, as it does on someone, typed all the way, for a
  /// command that's only for someone. Someone chosen from everyone with a name is who it's for, which
  /// Return then runs it for. Return and a click send what was typed as a message, after all, from
  /// the row that says so.
  func choose(_ index: Int, by choice: Choice) {
    guard let textView = self.textView, let list = self.parent.commands, list.rows.indices.contains(index) else {
      return
    }
    let text = textView.string
    let string = text as NSString
    let context = self.parent.commandContext()
    let place = ChatCommandPlace(text: text, caret: textView.selectedRange().location, in: context)
    let sameName: (String, String) -> Bool = { $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }

    switch list.rows[index] {
    case .command(let command):
      guard case .name(let typed, let range) = place else {
        return
      }
      let isTyped = (typed as NSString).length == range.length && command.answers(to: typed.lowercased())
      // Run as it is, for one that can do without anything after it: /invite with no one, too.
      let runsAsItIs = command.argument == .none || command.argument == .optionalText || command.argument == .people
      if choice == .returnKey, isTyped, runsAsItIs {
        self.send(text, announce: false)
      }
      else {
        self.put(command.rawValue, in: range, space: command.argument != .none)
      }

    case .suggestion(let command):
      // In place of the word that isn't a command, with the caret back at the end, where it was, so
      // Return runs it, as it was going to.
      let space = string.rangeOfCharacter(from: .whitespacesAndNewlines)
      let end = space.location == NSNotFound ? string.length : space.location
      self.put(command.rawValue, in: NSRange(location: 1, length: end - 1), space: false)
      textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

    case .person(let user):
      // The one chosen, of everyone with their name.
      self.chosen.subtract(context.people.filter { sameName($0.name, user.name) }.map(\.id))
      self.chosen.insert(user.id)
      if list.problem != nil {
        guard let name = self.problemName, NSMaxRange(name) <= string.length else {
          return
        }
        let typed = string.substring(with: name).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if name.length > 0, sameName(typed, user.name) {
          if choice == .returnKey {
            self.send(text, announce: false)
          }
          else {
            list.hide()
          }
        }
        else {
          // In place of who isn't here, with the caret back at the end, as for a command that was
          // meant.
          self.put(user.name, in: name, space: true)
          textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
      }
      else {
        guard case .person(let command, let typed, let range) = place else {
          return
        }
        let onlyForPeople = command.argument == .person(thenText: false) || command.argument == .people
        if choice == .returnKey, onlyForPeople, sameName(typed, user.name) {
          self.send(text, announce: false)
        }
        else {
          self.put(user.name, in: range, space: true)
        }
      }

    case .icon(let iconID):
      guard case .icon(_, let range) = place else {
        return
      }
      // Tab puts its number in, and Return and a click change yours to it.
      if choice == .tab {
        self.put(String(iconID), in: range, space: false)
      }
      else {
        self.clearText()
        self.parent.onCommand(.icon(iconID))
      }

    case .message(let message):
      if choice != .tab {
        self.sendMessage(message, announce: false)
      }
    }

    // The keys stay in the field, as a click in the list could take them.
    if let window = textView.window, window.firstResponder !== textView {
      window.makeFirstResponder(textView)
    }
  }

  /// Runs the command `text` is, or says what's wrong with it, or sends it as a message, which is
  /// what it is when it isn't a command, or anything like one.
  private func send(_ text: String, announce: Bool) {
    guard let list = self.parent.commands, text.hasPrefix("/") else {
      self.sendMessage(text, announce: announce)
      return
    }
    let context = self.parent.commandContext()
    switch ChatCommandInput(text, in: context) {
    case .message(let message):
      self.sendMessage(message, announce: announce)
    case .help:
      self.replaceText(with: "/")
    case .unknown(let word, let suggestions):
      self.show("/\(word) isn’t a command.", rows: suggestions.map { .suggestion($0) } + [.message(text)], in: list, context: context)
      self.problemName = nil
    case .command(let command, let arguments):
      switch command.request(arguments, in: context, chosen: self.chosen) {
      case .success(let request):
        self.clearText()
        self.parent.onCommand(request)
      case .failure(let problem):
        self.show(problem.message, rows: problem.people.map { .person($0) }, in: list, context: context)
        self.problemName = NSRange(location: Self.argumentsStart(in: text) + problem.nameStart, length: problem.nameLength)
      }
    }
  }

  /// Sends a message, done with any command.
  private func sendMessage(_ message: String, announce: Bool) {
    self.parent.commands?.hide()
    self.chosen = []
    self.problemName = nil
    self.textView?.commandHint = nil
    self.parent.onSubmit(message, announce)
  }

  /// Says what's wrong with what's typed, above the field, with what could be meant instead, and
  /// to VoiceOver, as the field keeps the keys.
  private func show(_ problem: String, rows: [ChatCommandList.Row], in list: ChatCommandList, context: ChatCommandContext) {
    self.listDismissed = false
    list.show(rows, problem: problem, inPrivateChat: context.isPrivateChat)
    AccessibilityNotification.Announcement(problem).post()
  }

  /// Puts `string` in place of `range`, and a space after it, unless there's one there already,
  /// which the caret goes past instead.
  private func put(_ string: String, in range: NSRange, space: Bool) {
    guard let textView = self.textView else {
      return
    }
    let text = textView.string as NSString
    guard NSMaxRange(range) <= text.length else {
      return
    }
    let spaced = NSMaxRange(range) < text.length && text.character(at: NSMaxRange(range)) == 0x20
    self.listDismissed = false
    textView.insertText(string + (space && !spaced ? " " : ""), replacementRange: range)
    if space && spaced {
      textView.setSelectedRange(NSRange(location: range.location + (string as NSString).length + 1, length: 0))
    }
  }

  /// Puts `string` in place of all that's typed, as /help does a slash, for the list of every command.
  private func replaceText(with string: String) {
    guard let textView = self.textView else {
      return
    }
    textView.insertText(string, replacementRange: NSRange(location: 0, length: (textView.string as NSString).length))
  }

  /// Empties the field once a command's run, as sending a message does.
  private func clearText() {
    self.parent.commands?.hide()
    self.chosen = []
    self.problemName = nil
    guard let textView = self.textView else {
      return
    }
    textView.commandHint = nil
    textView.string = ""
    self.parent.text = ""
    self.recalculateHeight()
  }

  /// What's left to type of a command, to show in gray after the caret, while it's at the end of
  /// what's typed: what goes after the command's name, like “name message”, or for /away, the reply
  /// you have, which it replies with when there's no other, for /msg, once someone's named, the
  /// message, and for /invite in the public chat, once there's someone named, a subject.
  private func hint(for text: String, selection: NSRange, in context: ChatCommandContext) -> String? {
    guard selection.length == 0, selection.location == (text as NSString).length, !text.contains(where: \.isNewline),
          let (word, arguments) = ChatCommandInput.split(text), let command = ChatCommand(word: word),
          command.unavailable(in: context) == nil else {
      return nil
    }
    let space = text.last?.isWhitespace == true ? "" : " "
    if arguments.isEmpty {
      if command == .away, let reply = context.automaticResponse.split(whereSeparator: \.isNewline).first, !reply.allSatisfy(\.isWhitespace) {
        return space + reply
      }
      let placeholder = command.placeholder(inPrivateChat: context.isPrivateChat)
      return placeholder.isEmpty ? nil : space + placeholder
    }
    if command == .msg, let named = ChatCommand.person(in: arguments, among: context.people), named.rest.isEmpty {
      return space + "message"
    }
    if command == .invite, !context.isPrivateChat {
      let named = ChatCommand.names(in: arguments, among: context.people)
      if !named.names.isEmpty, named.restStart == (arguments as NSString).length {
        return space + "subject"
      }
    }
    return nil
  }

  /// A command's name in the accent once it's typed, and who it's for, once they're typed, so it's
  /// clear it'll run rather than be sent. Styling the text again, which a change does to the lines
  /// it's in, takes them out, and they're put back after.
  func highlightCommand(in storage: NSTextStorage) {
    let text = storage.string
    guard let (word, arguments) = ChatCommandInput.split(text), let command = ChatCommand(word: word) else {
      return
    }
    let context = self.parent.commandContext()
    guard command.unavailable(in: context) == nil else {
      return
    }
    storage.addAttribute(.foregroundColor, value: self.commandColor, range: NSRange(location: 0, length: 1 + (word as NSString).length))
    let start = Self.argumentsStart(in: text)
    switch command.argument {
    case .person:
      if let named = ChatCommand.person(in: arguments, among: context.people) {
        storage.addAttribute(.foregroundColor, value: self.commandColor, range: NSRange(location: start, length: named.length))
      }
    case .people:
      for name in ChatCommand.names(in: arguments, among: context.people).names {
        storage.addAttribute(.foregroundColor, value: self.commandColor, range: NSRange(location: start + name.range.location, length: name.range.length))
      }
    default:
      break
    }
  }

  /// Where what's typed after a command's name starts, past the spaces after it.
  static func argumentsStart(in text: String) -> Int {
    let string = text as NSString
    func isSpace(_ index: Int) -> Bool {
      Unicode.Scalar(string.character(at: index)).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
    }
    var index = 1
    while index < string.length, !isSpace(index) {
      index += 1
    }
    while index < string.length, isSpace(index) {
      index += 1
    }
    return index
  }
}

/// NSTextView subclass that intercepts Enter key variants and provides
/// asymmetric internal padding so the text area is inset from the edges.
/// Laid out like the messages above: your icon where they have their senders', and the text where
/// theirs starts.
class ChatInputTextView: MarkdownEditingTextView {
  var submitHandler: ((_ announce: Bool) -> Void)?
  var frameResizeHandler: (() -> Void)?
  /// The names Tab completes, best first.
  var namesToComplete: (() -> [String])?
  /// The name Tab last put in, and the others that fit what was typed, so another Tab can swap it
  /// for the next one.
  private var completion: (names: [String], index: Int, range: NSRange, inserted: String)?
  /// Told when the field gets the keys, and when it loses them.
  var focusHandler: ((_ focused: Bool) -> Void)?

  /// What's left to type of a command, in gray after the caret, at the end of the text, like
  /// “name message” after “/msg”.
  var commandHint: String? {
    didSet {
      // Drawn again where the text ends now, too.
      if self.commandHint != nil || oldValue != nil {
        self.needsDisplay = true
      }
    }
  }

  /// The hint's color.
  var hintColor: NSColor = .placeholderTextColor {
    didSet {
      if self.commandHint != nil, self.hintColor != oldValue {
        self.needsDisplay = true
      }
    }
  }

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

  /// Whether your icon's dimmed, as the sidebar's icons are while the window isn't in front.
  var dimsIcon = false {
    didSet {
      self.iconView.alphaValue = self.dimsIcon ? 0.5 : 1
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

  /// The keys, once it's in a window, if they've gone to nothing else there, as on connecting, and
  /// not from what has them, like the sidebar, when Chat's chosen in it, which keeps them.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if self.window != nil {
      DispatchQueue.main.async { [weak self] in
        guard let self, let window = self.window, window.firstResponder == nil || window.firstResponder === window else {
          return
        }
        window.makeFirstResponder(self)
      }
    }
  }

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became {
      // Once it's the window's first responder, which it isn't until this returns.
      DispatchQueue.main.async { [weak self] in
        self?.focusHandler?(true)
      }
    }
    return became
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned {
      self.focusHandler?(false)
    }
    return resigned
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    self.drawCommandHint()
  }

  /// Draws the hint where the text ends, on its line, as much of it as there's room for there.
  private func drawCommandHint() {
    guard let hint = self.commandHint, !hint.isEmpty, let window = self.window else {
      return
    }
    let end = NSRange(location: (self.string as NSString).length, length: 0)
    let caret = self.convert(window.convertFromScreen(self.firstRect(forCharacterRange: end, actualRange: nil)), from: nil)
    let room = self.bounds.width - self.rightInset - caret.maxX
    guard caret.height > 0, room > 16 else {
      return
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    (hint as NSString).draw(
      with: NSRect(x: caret.maxX, y: caret.minY, width: room, height: caret.height),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: [.font: ChatInputField.layout.font, .foregroundColor: self.hintColor, .paragraphStyle: paragraph]
    )
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
    // The first line, or with no text, where it would be. TextKit 2 first, as asking for the layout
    // manager switches a text view to TextKit 1.
    var lineRect = NSRect(x: 0, y: 0, width: 0, height: ChatInputField.lineHeight)
    if let textLayoutManager = self.textLayoutManager {
      if let fragment = textLayoutManager.textLayoutFragment(for: textLayoutManager.documentRange.location),
         let line = fragment.textLineFragments.first {
        lineRect = line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)
      }
    } else if let layoutManager = self.layoutManager, layoutManager.numberOfGlyphs > 0 {
      lineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
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
      // Shift+Enter: insert newline, through the delegate, which goes on with a list or a quote.
      self.doCommand(by: #selector(NSResponder.insertNewline(_:)))
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
