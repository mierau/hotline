import SwiftUI

struct MessageBoardView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverTheme) private var theme
  @Environment(HotlineState.self) private var model: HotlineState
  
  @State private var composerDisplayed: Bool = false
  @State private var composerText: String = ""
  
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(idealWidth: 450, idealHeight: 350)
    }
    .toolbar {
      ToolbarItem(placement:.primaryAction) {
        Button {
          self.composerDisplayed.toggle()
        } label: {
          Image(systemName: "pin")
        }
        .disabled((self.model.access?.contains(.canPostMessageBoard) != true) || (self.model.access?.contains(.canReadMessageBoard) != true))
        .help("Post to Message Board")
      }
    }
    .task {
      if !self.model.messageBoardLoaded {
        let _ = try? await self.model.getMessageBoard()
      }
    }
  }
  
  /// Scrolls to a post a link in chat asked for, by its reference, once the board has laid out.
  private func reveal(_ reference: String?, with proxy: ScrollViewProxy) {
    guard let reference else {
      return
    }
    self.model.boardPostToReveal = nil
    guard let post = self.model.messageBoard.first(where: { $0.reference == reference }) else {
      return
    }
    Task { @MainActor in
      proxy.scrollTo(post.id, anchor: .top)
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
              if post.looksLikeASCIIArt {
                Text(post.body.attributedStringHighlightingLinks())
                  .tint(Color("Link Color"))
                  .font(.system(.body, design: .monospaced))
                  .lineLimit(100)
                  .lineSpacing(4)
                  .textSelection(.enabled)
                  .padding(.horizontal, 24)
              } else {
                Text(LocalizedStringKey(post.body.convertingLinksToMarkdown()))
                  .tint(Color("Link Color"))
                  .lineLimit(100)
                  .lineSpacing(4)
                  .textSelection(.enabled)
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
          // In the server's theme, the page's color sets the posts apart. Without one, the page is
          // nearly as white as they are.
          .shadow(color: .black.opacity(self.theme == nil ? 0.08 : 0), radius: 2, x: 0, y: 1)
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

#Preview {
  MessageBoardView()
    .environment(HotlineState())
}
