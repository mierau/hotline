import SwiftUI

/// Writing a news article, or a reply to one, across all of the sheet, as a post for the board is
/// written, with where it's going in a header at the top, and for a reply, who it's from, then its
/// title, and what it says, in Markdown, styled as the news will show it, as you write it, with the
/// marks kept but faint, and code blocks colored as chat colors them. The buttons at the bottom on
/// the left, and their keys, put the marks around what's selected, or take them away, and are off
/// while the title's being written. A picture dropped in becomes a drawing of it, as on the board.
/// Cancel throws away what's written, and asks first, once you've written something in the
/// article. An article is only as long as a Hotline field holds, and near that, it says how much
/// more there's room for, beside Cancel.
struct NewsEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(HotlineState.self) private var model: HotlineState

  /// Where it's going: the topic it's in, or who it's a reply to.
  let editorTitle: String
  let isReply: Bool
  let path: [String]
  let parentID: UInt32
  @Binding var selection: NewsInfo?
  /// The title it starts with, as a reply's is the article's, until it's given one of its own.
  var title: String = ""
  /// What it opens with, after anything written for it already, like a quote of the article it's a
  /// reply to.
  var quote: String = ""

  /// How far in from the sheet's sides the title and article are, as far as a post for the board is,
  /// and how far the article is from the line over it.
  private static let inset = NSSize(width: 24, height: 16)
  /// As small as there's room for the title and the article in.
  private static let smallest = CGSize(width: 440, height: 420)

  @State private var editor = MarkdownEditor()
  @State private var posting = false
  @State private var failed = false
  /// How big it opens: as big as it was last made, or else as it's meant to be.
  @State private var opening: CGSize = {
    let saved = NSSizeFromString(Prefs.shared.newsArticleSize)
    return saved.width >= Self.smallest.width && saved.height >= Self.smallest.height ? saved : CGSize(width: 560, height: 520)
  }()
  /// How big it is, as it's shown, to keep once it's made bigger or smaller.
  @State private var shown = ShownSize()
  @FocusState private var titleFocused: Bool
  /// What the article opened with, like a quote, which isn't something you've written.
  @State private var openedWith = ""
  @State private var confirmingDiscard = false

  private var place: NewsDraft.Place {
    NewsDraft.Place(path: self.path, parentID: self.parentID)
  }

  /// What's written, kept as it's written, until it's posted.
  private var draft: Binding<NewsDraft> {
    Binding {
      self.model.newsDrafts[self.place] ?? NewsDraft(title: self.title)
    } set: { draft in
      self.model.newsDrafts[self.place] = draft
    }
  }

  var body: some View {
    let draft = self.draft.wrappedValue
    let text = MessageBoardPost.cleaned(draft.text)
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let room = Markdown.maximumLength - text.utf8.count

    // The article, as it'll be in the news, which is all there is to say what it's for: where it's
    // going, in a header as tall as the board's, then its title, and what it says, under it, to the
    // bottom bar, with its formatting.
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        if self.isReply {
          Image(systemName: "arrowshape.turn.up.left.fill")
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 16)
        }
        else {
          Image("News Category")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        Text(self.editorTitle)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        // If it didn't go through, that it didn't.
        if self.failed {
          Label("not posted", systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
            .help("It didn't go through. Try posting it again.")
            .transition(.opacity)
        }
        // A reply's from you, across from who it's to, with your icon and name, as the board's post
        // sheet has them, a little apart from that.
        if self.isReply {
          HStack(spacing: 8) {
            UserIconView(iconID: self.model.ownIconID)
            Text(self.model.ownUser?.name ?? Prefs.shared.username)
              .fontWeight(.semibold)
              .lineLimit(1)
          }
          .padding(.leading, 4)
        }
      }
      .padding(.vertical, 16)
      .padding(.horizontal, Self.inset.width)
      .serverBackground(.postHeader)

      // Its title, as the news shows it over the article, and Return goes on to the article.
      TextField("Title", text: self.draft.title, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 17, weight: .semibold))
        .lineLimit(1...3)
        .focused(self.$titleFocused)
        .onSubmit {
          self.titleFocused = false
          if let textView = self.editor.textView {
            textView.window?.makeFirstResponder(textView)
          }
        }
        .padding(.horizontal, Self.inset.width)
        .padding(.top, 20)
        .padding(.bottom, 14)
      Divider()
        .serverThemedDivider()
        .padding(.horizontal, Self.inset.width)
      PostEditor(text: self.draft.text, controller: self.editor, startsHere: !title.isEmpty, inset: Self.inset)
        .overlay(alignment: .topLeading) {
          if draft.text.isEmpty {
            Text(self.isReply ? "Write your reply…" : "Write an article for \(self.editorTitle)…")
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
      Prefs.shared.newsArticleSize = NSStringFromSize(size)
    })
    // As big as it's meant to be, as above.
    .presentationSizing(.fitted)
    .toolbar {
      if self.posting {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }

      // The formatting, at the bottom on the left, across from Cancel and Post, as the private
      // message sheet has it, and off while the title's being written, which has none. See there.
      ToolbarItem(placement: .destructiveAction) {
        PostFormattingBar(editor: self.editor)
          .disabled(self.titleFocused)
      }

      ToolbarItem(placement: .cancellationAction) {
        PostCancelButton(room: room, what: "An article") {
          if self.draft.wrappedValue.text.isWritten(besides: self.openedWith) {
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
        .disabled(text.isEmpty || title.isEmpty || room < 0 || self.posting)
        .help(self.isReply ? "Post Reply (⌘↩)" : "Post to the News (⌘↩)")
      }
    }
    .onAppear {
      if !self.quote.isEmpty {
        var draft = self.draft.wrappedValue
        let written = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.text = written.isEmpty ? self.quote : written + "\n\n" + self.quote
        self.draft.wrappedValue = draft
      }
      self.openedWith = self.draft.wrappedValue.text
      // A new article starts with its title, and a reply, which has one, with what it says.
      if self.draft.wrappedValue.title.isBlank {
        self.titleFocused = true
      }
    }
    .discardConfirmation(self.isReply ? "Discard this reply?" : "Discard this article?", isPresented: self.$confirmingDiscard, discard: self.discard)
    .onDisappear {
      // Nothing written isn't kept, so a reply opens with the article's title again.
      if let draft = self.model.newsDrafts[self.place], draft.text.isBlank, draft.title == self.title || draft.title.isBlank {
        self.model.newsDrafts[self.place] = nil
      }
    }
  }

  /// Throws away what's written, and puts the sheet away.
  private func discard() {
    self.model.newsDrafts[self.place] = nil
    self.dismiss()
  }

  /// Posts it, and once it's in the news, goes to it there. If it doesn't go through, it's still
  /// here to try again.
  private func post() {
    let draft = self.draft.wrappedValue
    let text = MessageBoardPost.cleaned(draft.text)
    // On one line, as titles are.
    let title = draft.title.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, !title.isEmpty else {
      return
    }

    self.posting = true
    withAnimation(.easeOut(duration: 0.15)) {
      self.failed = false
    }
    Task {
      do {
        let posted = try await self.model.postNewsArticle(title: title, body: text, at: self.path, parentID: self.parentID)
        self.model.newsDrafts[self.place] = nil
        self.posting = false
        if let posted {
          self.selection = posted
        }
        self.dismiss()
      }
      catch {
        self.posting = false
        withAnimation(.easeOut(duration: 0.15)) {
          self.failed = true
        }
      }
    }
  }
}
