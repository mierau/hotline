import SwiftUI

struct MessageBoardView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverTheme) private var theme
  @Environment(\.openWindow) private var openWindow
  @Environment(HotlineState.self) private var model: HotlineState
  
  @State private var composerDisplayed: Bool = false
  /// A linked file's info, from its link's menu.
  @State private var fileDetails: FileDetails?
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
    .sheet(item: self.$fileDetails) { details in
      FileDetailsSheet(details: details)
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
    let quote = Markdown.quote(post.body, by: post.username)
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
            
            // Its words, as far in from its edges as its header's are.
            MarkdownText(
              text: post.body,
              inset: NSSize(width: 24, height: 24),
              menuItems: {
                [TextMenuItem("Quote in New Post", systemImage: "quote.opening", isEnabled: self.canPost) { self.quote(post) }]
              },
              fileLinkMenu: { url in
                FileLinkMenu(model: self.model, openWindow: self.openWindow, showInfo: { self.fileDetails = $0 }).menu(for: url)
              }
            )
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
      // The keys scroll through it all, from the room between posts, or after a post with them is
      // scrolled away.
      .background(KeyScrolling())
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

#Preview {
  MessageBoardView()
    .environment(HotlineState())
}
