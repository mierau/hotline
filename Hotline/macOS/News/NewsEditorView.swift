import SwiftUI

/// Writing a news article, or a reply to one, in a card like the ones on the board, with where it's
/// going at the top, then its title, and what it says, in Markdown, styled as the news will show it,
/// as you write it, with the marks kept but faint, and code blocks colored as chat colors them. The
/// buttons on the card's bottom edge, and their keys, put the marks around what's selected, or take
/// them away. A picture dropped in becomes a drawing of it, as on the board. What you write stays
/// when the sheet's put away without posting it, for the next time, until you leave the server. An
/// article is only as long as a Hotline field holds, and near that, it says how much more there's
/// room for.
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

  /// How round the card's corners are.
  private static let cornerRadius: CGFloat = 12
  /// How near the most an article can be before it says how much more there's room for.
  private static let roomShown = 2_000
  /// As small as there's room for the title and the article in.
  private static let smallest = CGSize(width: 440, height: 420)

  @State private var editor = PostEditorController()
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

    VStack(alignment: .leading, spacing: 16) {
      // The article, as it'll be in the news, which is all there is to say what it's for.
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          if self.isReply {
            Image(systemName: "arrowshape.turn.up.left")
              .foregroundStyle(.secondary)
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
          // If it didn't go through, that it didn't, or near the most there's room for, how much
          // more there is, or how much less it has to be.
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
              .help("An article can be up to \(Markdown.maximumLength.formatted()) characters long, and fewer with emoji or accented letters, which take more room.")
          }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, PostEditor.inset.width)

        VStack(spacing: 0) {
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
            .padding(.horizontal, PostEditor.inset.width)
            .padding(.top, PostEditor.inset.height)
            .padding(.bottom, 10)
          Divider()
            .padding(.horizontal, PostEditor.inset.width)
          // With room at the bottom to scroll the last lines up past the formatting.
          PostEditor(text: self.draft.text, controller: self.editor, bottomInset: PostFormattingBar.height / 2 + 6, startsHere: !title.isEmpty)
            .overlay(alignment: .topLeading) {
              if draft.text.isEmpty {
                Text(self.isReply ? "Write your reply…" : "Write an article for \(self.editorTitle)…")
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, PostEditor.inset.width)
                  .padding(.vertical, PostEditor.inset.height)
                  .allowsHitTesting(false)
              }
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
      // The formatting, floating over the card's bottom edge in the middle, half on it, and off
      // while the title's being written, which has none.
      .overlay(alignment: .bottom) {
        PostFormattingBar(editor: self.editor)
          .disabled(self.titleFocused)
          .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
      }
      // Room for the half that's past it.
      .padding(.bottom, PostFormattingBar.height / 2)
    }
    .padding(20)
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
      // A new article starts with its title, and a reply, which has one, with what it says.
      if self.draft.wrappedValue.title.isBlank {
        self.titleFocused = true
      }
    }
    .onDisappear {
      // Nothing written isn't kept, so a reply opens with the article's title again.
      if let draft = self.model.newsDrafts[self.place], draft.text.isBlank, draft.title == self.title || draft.title.isBlank {
        self.model.newsDrafts[self.place] = nil
      }
    }
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
