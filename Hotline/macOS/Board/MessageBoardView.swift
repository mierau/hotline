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
            
            HStack(spacing: 0) {
              if post.looksLikeASCIIArt && !post.hasCodeBlocks {
                Text(post.body.attributedStringHighlightingLinks())
                  .tint(Color("Link Color"))
                  .font(.system(.body, design: .monospaced))
                  .lineLimit(100)
                  .lineSpacing(4)
                  .textSelection(.enabled)
                  .padding(.horizontal, 24)
              } else {
                BoardPostText(text: post.body)
                  .padding(.horizontal, 24)
              }

              Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
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

/// A post's words, as Markdown, with its code blocks, quotes and lists apart from them: code colored
/// as chat colors it, quotes along a bar, and lists with their bullets and numbers. Worked out once
/// for each post, rather than each time the board's drawn.
private struct BoardPostText: View {
  let text: String

  fileprivate enum Part {
    case words(String)
    case code(String, language: String?)
    case quote(String)
    case list([ListItem])
  }

  fileprivate struct ListItem {
    /// A bullet, or the number and what's after it, as 2.
    var mark: String
    var words: String
  }

  private final class Parts {
    let parts: [Part]

    init(_ parts: [Part]) {
      self.parts = parts
    }
  }

  private static let cache = NSCache<NSString, Parts>()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(self.parts.enumerated()), id: \.offset) { _, part in
        switch part {
        case .words(let words):
          Self.markdown(words)
        case .code(let code, let language):
          BoardCodeBlock(code: code, language: language)
        case .quote(let words):
          HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5)
              .fill(.tertiary)
              .frame(width: 3)
            Self.markdown(words)
              .foregroundStyle(.secondary)
          }
          .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.mark)
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
                Self.markdown(item.words)
              }
              // All of an item's lines, and not just its first.
              .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
  }

  private static func markdown(_ words: String) -> some View {
    Text(LocalizedStringKey(words.convertingLinksToMarkdown()))
      .tint(Color("Link Color"))
      .lineLimit(100)
      .lineSpacing(4)
      .textSelection(.enabled)
  }

  private var parts: [Part] {
    if let parts = Self.cache.object(forKey: self.text as NSString) {
      return parts.parts
    }
    let parts = Self.parts(of: self.text)
    Self.cache.setObject(Parts(parts), forKey: self.text as NSString)
    return parts
  }

  /// The code blocks, and the words between them, without the blank lines around them.
  private static func parts(of text: String) -> [Part] {
    let source = text as NSString
    var parts: [Part] = []
    var start = 0
    for block in PostMarkdown.codeBlocks(in: source) {
      parts += self.parts(ofWords: source.substring(with: NSRange(location: start, length: block.range.location - start)))
      // Nothing for one with no code in it.
      let code = source.substring(with: block.code).trimmingCharacters(in: .newlines)
      if !code.isEmpty {
        parts.append(.code(code, language: block.language))
      }
      start = NSMaxRange(block.range)
    }
    parts += self.parts(ofWords: source.substring(from: start))
    return parts
  }

  /// Words, a line at a time: a quote's lines together, a list's items together, with any lines
  /// after an item without a mark of their own going with it, and the rest together. A blank line
  /// ends a quote or a list.
  private static func parts(ofWords text: String) -> [Part] {
    let source = text as NSString
    var parts: [Part] = []
    enum Kind {
      case words, quote, list
    }
    var kind: Kind?
    var lines: [String] = []
    var items: [ListItem] = []
    func finish() {
      switch kind {
      case .words:
        let words = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if !words.isBlank {
          parts.append(.words(words))
        }
      case .quote:
        parts.append(.quote(lines.joined(separator: "\n")))
      case .list:
        parts.append(.list(items))
      case nil:
        break
      }
      kind = nil
      lines = []
      items = []
    }

    var lineStart = 0
    while lineStart < source.length {
      let range = source.lineRange(for: NSRange(location: lineStart, length: 0))
      let line = source.substring(with: range).trimmingCharacters(in: .newlines)
      if let mark = PostMarkdown.lineMark(in: source, line: range) {
        let words = String((line as NSString).substring(from: min(mark.length, (line as NSString).length)))
        switch mark.kind {
        case .quote:
          if kind != .quote {
            finish()
            kind = .quote
          }
          lines.append(words)
        case .bullet, .number:
          if kind != .list {
            finish()
            kind = .list
          }
          items.append(ListItem(mark: mark.kind == .bullet ? "•" : mark.mark, words: words))
        }
      }
      else if line.trimmingCharacters(in: .whitespaces).isEmpty {
        if kind == .words {
          lines.append(line)
        }
        else {
          finish()
        }
      }
      else if kind == .list, !items.isEmpty {
        items[items.count - 1].words += "\n" + line.trimmingCharacters(in: .whitespaces)
      }
      else {
        if kind != .words {
          finish()
          kind = .words
        }
        lines.append(line)
      }
      lineStart = NSMaxRange(range)
    }
    finish()
    return parts
  }
}

/// A code block in a post, as chat has them: its code colored when it names a language we know,
/// with the language small above it, on a background of its own. Colored once for each block.
private struct BoardCodeBlock: View {
  let code: String
  let language: String?

  private final class Highlighted {
    let text: AttributedString

    init(_ text: AttributedString) {
      self.text = text
    }
  }

  private static let cache = NSCache<NSString, Highlighted>()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let language = self.language {
        Text(language)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Text(self.highlighted)
        .font(.system(size: NSFont.systemFontSize - 1, design: .monospaced))
        .lineSpacing(3)
        .textSelection(.enabled)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: ChatMessageRenderer.codeBlockBackground), in: .rect(cornerRadius: 6))
  }

  private var highlighted: AttributedString {
    let key = "\(self.language ?? "")\n\(self.code)" as NSString
    if let highlighted = Self.cache.object(forKey: key) {
      return highlighted.text
    }
    let code = NSMutableAttributedString(string: self.code, attributes: [.foregroundColor: NSColor.textColor])
    if let language = self.language.flatMap({ ChatCodeHighlighter.language(named: $0) }) {
      ChatCodeHighlighter.highlight(code, in: NSRange(location: 0, length: code.length), as: language)
    }
    var highlighted = AttributedString()
    code.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: code.length)) { color, range, _ in
      var run = AttributedString(code.attributedSubstring(from: range).string)
      if let color = color as? NSColor {
        run.foregroundColor = Color(nsColor: color)
      }
      highlighted += run
    }
    Self.cache.setObject(Highlighted(highlighted), forKey: key)
    return highlighted
  }
}

#Preview {
  MessageBoardView()
    .environment(HotlineState())
}
