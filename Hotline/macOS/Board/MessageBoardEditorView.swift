import SwiftUI

/// Writing a post for the board, across all of the sheet, as a post is across the board, with your
/// name and icon at the top as everyone's are, so it's your post as it'll be. The board shows
/// Markdown's bold, italic, underline, strikethrough, code, code blocks, links, headings, quotes and
/// lists, and so does what you write, as you write it, with the marks kept but faint, and code
/// blocks colored as chat colors them. The buttons at the bottom on the left, and their keys, put
/// the marks around what's selected, or take them away, as they do for a private message. A picture
/// dropped in becomes a drawing of it, in characters, as ASCII art. Cancel throws away what's
/// written, and asks first, once you've written something. A post is only as long as a Hotline
/// field holds, and near that, it says how much more there's room for, beside Cancel.
struct MessageBoardEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(HotlineState.self) private var model: HotlineState

  /// How far in from the sheet's edges the post is, as far as a post on the board is in from its
  /// card's.
  private static let inset = NSSize(width: 24, height: 24)

  @State private var editor = MarkdownEditor()
  @State private var posting: Bool = false
  @State private var failed: Bool = false
  /// What it opened with, like a quote, which isn't something you've written.
  @State private var openedWith = ""
  @State private var confirmingDiscard = false
  /// How big it opens: as big as it was last made, or else as it's meant to be.
  @State private var opening: CGSize = {
    let saved = NSSizeFromString(Prefs.shared.boardPostSize)
    return saved.width >= Self.smallest.width && saved.height >= Self.smallest.height ? saved : CGSize(width: 540, height: 480)
  }()
  /// How big it is, as it's shown, to keep once it's made bigger or smaller.
  @State private var shown = ShownSize()

  /// As small as there's room for the post in.
  private static let smallest = CGSize(width: 440, height: 380)

  var body: some View {
    @Bindable var model = self.model
    let post = MessageBoardPost.cleaned(self.model.boardDraft)
    let room = Markdown.maximumLength - post.utf8.count

    // The post, as it'll be on the board, which is all there is to say what it's for: its header,
    // as tall as the board's, and what it says, under it, to the bottom bar, with its formatting.
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        UserIconView(iconID: self.model.ownIconID)
        Text(self.model.ownUser?.name ?? Prefs.shared.username)
          .fontWeight(.semibold)
          .lineLimit(1)
        Spacer()
        // When it is, or if it didn't go through, that it didn't.
        if self.failed {
          Label("not posted", systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
            .help("It didn't go through. Try posting it again.")
            .transition(.opacity)
        }
        else {
          Text("now")
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 16)
      .padding(.horizontal, Self.inset.width)
      .serverBackground(.postHeader)

      PostEditor(text: $model.boardDraft, controller: self.editor, inset: Self.inset)
        .overlay(alignment: .topLeading) {
          if self.model.boardDraft.isEmpty {
            Text(self.placeholder)
              .foregroundStyle(.tertiary)
              .padding(.horizontal, Self.inset.width)
              .padding(.vertical, Self.inset.height)
              .allowsHitTesting(false)
          }
        }
    }
    .serverBackground(.post)
    .frame(minWidth: Self.smallest.width, idealWidth: self.opening.width, maxWidth: .infinity, minHeight: Self.smallest.height, idealHeight: self.opening.height, maxHeight: .infinity)
    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
      self.shown.size = size
    }
    .background(ResizableSheet(smallest: Self.smallest, opening: self.opening, shown: self.shown) { size in
      Prefs.shared.boardPostSize = NSStringFromSize(size)
    })
    // As big as it's meant to be, as above.
    .presentationSizing(.fitted)
    .onAppear {
      self.openedWith = self.model.boardDraft
    }
    .discardConfirmation("Discard this post?", isPresented: self.$confirmingDiscard, discard: self.discard)
    .toolbar {
      if self.posting {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }

      // The formatting, at the bottom on the left, across from Cancel and Post, as the private
      // message sheet has it. See there.
      ToolbarItem(placement: .destructiveAction) {
        PostFormattingBar(editor: self.editor)
      }

      ToolbarItem(placement: .cancellationAction) {
        PostCancelButton(room: room, what: "A post") {
          if self.model.boardDraft.isWritten(besides: self.openedWith) {
            self.confirmingDiscard = true
          }
          else {
            self.discard()
          }
        }
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

  /// What the post says before anything's written in it: who it's for, by the server's name, as the
  /// window has it, or else the board.
  private var placeholder: String {
    self.model.serverTitle.isBlank ? "Write a post for the board…" : "Write a post for \(self.model.serverTitle)…"
  }

  /// Throws away what's written, and puts the sheet away.
  private func discard() {
    self.model.boardDraft = ""
    self.dismiss()
  }

  /// Posts it, and once it's on the board, goes to it there. If it doesn't go through, it's still
  /// here to try again.
  private func post() {
    let text = MessageBoardPost.cleaned(self.model.boardDraft)
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
}
