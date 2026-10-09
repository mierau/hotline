import SwiftUI

/// Writing a post for the board, in a card like the ones there, with your name and icon at the top
/// as everyone's are, so it's your post as it'll be. The board shows Markdown's bold, italic,
/// strikethrough, code, code blocks, links, quotes and lists, and so does what you write, as you
/// write it, with the marks kept but faint, and code blocks colored as chat colors them. The
/// buttons on the post's bottom edge, and their keys, put the marks around what's selected, or take
/// them away. What you write stays when the sheet's put away without posting it, for the next time,
/// until you leave the server. A post is only as long as a Hotline field holds, and near that, it
/// says how much more there's room for.
struct MessageBoardEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(HotlineState.self) private var model: HotlineState

  /// How round the post's corners are.
  private static let cornerRadius: CGFloat = 12
  /// How near the most a post can be before it says how much more there's room for.
  private static let roomShown = 2_000

  @State private var editor = PostEditorController()
  @State private var posting: Bool = false
  @State private var failed: Bool = false

  var body: some View {
    @Bindable var model = self.model
    let post = Self.cleaned(self.model.boardDraft)
    let room = PostMarkdown.maximumLength - post.utf8.count

    VStack(alignment: .leading, spacing: 16) {
      // What it's for, at the top, with the icon the board has in the sidebar.
      HStack(alignment: .center, spacing: 12) {
        Image("Section Board")
          .resizable()
          .scaledToFit()
          .frame(width: 32, height: 32)

        Text("New Post")
          .font(.title3)
          .fontWeight(.semibold)
      }

      // The post, as it'll be on the board.
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          if let icon = HotlineState.getClassicIcon(self.model.ownIconID) {
            Image(nsImage: icon)
              .frame(width: 16, height: 16)
          }
          Text(self.model.ownUser?.name ?? Prefs.shared.username)
            .fontWeight(.semibold)
            .lineLimit(1)
          Spacer()
          // When it is, or if it didn't go through, that it didn't, or near the most there's room for,
          // how much more there is, or how much less it has to be.
          if self.failed {
            Label("not posted", systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(.red)
              .help("It didn't go through. Try posting it again.")
              .transition(.opacity)
          }
          else if room < Self.roomShown {
            Text(room >= 0 ? "\(room.formatted()) left" : "\((-room).formatted()) too long")
              .monospacedDigit()
              .foregroundStyle(room >= 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
              .help("A post can be up to \(PostMarkdown.maximumLength.formatted()) characters long, and fewer with emoji or accented letters, which take more room.")
          }
          else {
            Text("now")
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, PostEditor.inset.width)

        // With room at the bottom to scroll the last lines up past the formatting.
        PostEditor(text: $model.boardDraft, controller: self.editor, bottomInset: PostFormattingBar.height / 2 + 6)
          .overlay(alignment: .topLeading) {
            if self.model.boardDraft.isEmpty {
              Text("Write something…")
                .foregroundStyle(.tertiary)
                .padding(.horizontal, PostEditor.inset.width)
                .padding(.vertical, PostEditor.inset.height)
                .allowsHitTesting(false)
            }
          }
          .serverBackground(.post)
          .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.cornerRadius - 1, bottomTrailingRadius: Self.cornerRadius - 1))
          // A point of the header's color around it, as a line.
          .padding([.horizontal, .bottom], 1)
      }
      // The header's color, at the top, and around the rest.
      .serverBackground(.postHeader)
      .clipShape(.rect(cornerRadius: Self.cornerRadius))
      // The formatting, floating over the post's bottom edge in the middle, half on it.
      .overlay(alignment: .bottom) {
        PostFormattingBar(editor: self.editor)
          .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
      }
      // Room for the half that's past it.
      .padding(.bottom, PostFormattingBar.height / 2)
    }
    .padding(20)
    .frame(minWidth: 440, idealWidth: 540, maxWidth: .infinity, minHeight: 380, idealHeight: 480, maxHeight: .infinity)
    .toolbar {
      if self.posting {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }

      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
        // In the text's color, as without a theme, and not the theme's, which is Post's.
        .tint(.primary)
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("Post") {
          self.post()
        }
        .buttonStyle(.borderedProminent)
        // Return is for new lines.
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(post.isEmpty || room < 0 || self.posting)
        .help("Post to the Board (⌘↩)")
      }
    }
  }

  /// Posts it, and once it's on the board, goes to it there. If it doesn't go through, it's still
  /// here to try again.
  private func post() {
    let text = Self.cleaned(self.model.boardDraft)
    guard !text.isEmpty else {
      return
    }

    self.posting = true
    withAnimation(.easeOut(duration: 0.15)) {
      self.failed = false
    }
    Task {
      do {
        try await self.model.postToMessageBoard(text: text)
      }
      catch {
        self.posting = false
        withAnimation(.easeOut(duration: 0.15)) {
          self.failed = true
        }
        return
      }
      self.model.boardDraft = ""
      self.posting = false
      self.dismiss()

      // Yours, at the top, as the board shows it, or what's at the top if it's gone by another name.
      let _ = try? await self.model.getMessageBoard()
      let posted = self.model.messageBoard.first(where: { $0.body == text }) ?? self.model.messageBoard.first
      self.model.boardPostToReveal = posted?.reference
    }
  }

  /// What's written, without blank lines before it or spaces after it, which would only push it
  /// apart on the board, but with any spaces at the start of its first line, as for a drawing.
  static func cleaned(_ text: String) -> String {
    var lines = text.components(separatedBy: .newlines)
    while let first = lines.first, first.isBlank {
      lines.removeFirst()
    }
    return lines.joined(separator: "\n").replacing(/\s+\z/, with: "")
  }
}

// MARK: - Formatting

/// The formatting the board shows, a click or a key away, in glass over the bottom of the post.
private struct PostFormattingBar: View {
  /// How tall it is: its buttons, and the glass around them.
  static let height: CGFloat = PostFormatButton.height + 2 * Self.padding
  private static let padding: CGFloat = 3

  let editor: PostEditorController

  var body: some View {
    // None of it shows in code, so it's off there, but for taking code off `code`.
    let code = self.editor.codeContext
    HStack(spacing: 0) {
      PostFormatButton("Bold", systemImage: "bold", key: "b") {
        self.editor.toggle(.bold)
      }
      .disabled(code != nil)
      PostFormatButton("Italic", systemImage: "italic", key: "i") {
        self.editor.toggle(.italic)
      }
      .disabled(code != nil)
      PostFormatButton("Strikethrough", systemImage: "strikethrough", key: "x", modifiers: [.command, .shift]) {
        self.editor.toggle(.strikethrough)
      }
      .disabled(code != nil)
      PostFormatButton("Code", systemImage: "chevron.left.forwardslash.chevron.right", key: "e") {
        self.editor.toggle(.code)
      }
      .disabled(code == .block)
      PostFormatButton("Link", systemImage: "link", key: "k") {
        self.editor.link()
      }
      .disabled(code != nil)
    }
    .padding(Self.padding)
    .modifier(PostFormattingBackground())
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

/// A formatting button: its symbol, a light fill behind it while the pointer's over it, and its
/// name and key as its help.
private struct PostFormatButton: View {
  static let height: CGFloat = 26

  let title: String
  let systemImage: String
  let key: KeyEquivalent
  let modifiers: EventModifiers
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var hovered: Bool = false

  init(_ title: String, systemImage: String, key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.key = key
    self.modifiers = modifiers
    self.action = action
  }

  var body: some View {
    Button(action: self.action) {
      Image(systemName: self.systemImage)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 32, height: Self.height)
        .foregroundStyle(!self.isEnabled ? .tertiary : self.hovered ? .primary : .secondary)
        .background(.fill.tertiary.opacity(self.hovered && self.isEnabled ? 1 : 0), in: .capsule)
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .keyboardShortcut(self.key, modifiers: self.modifiers)
    .help("\(self.title) (\(self.shortcut))")
    .accessibilityLabel(self.title)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        self.hovered = hovering
      }
    }
  }

  /// The key, as menus show it.
  private var shortcut: String {
    (self.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + String(self.key.character).uppercased()
  }
}
