import SwiftUI

/// An article, the width of the window, and under it, the replies to it, and the replies to those,
/// all at once, on gray, in the server's theme: who wrote each and when, its title, and what it
/// says, in Markdown, as it's shown everywhere. Each reply is under what it replies to, and further
/// in, so a conversation reads from top to bottom without choosing each reply. The replies are all
/// joined, as one, with lines between them. Choosing a reply shows it in its conversation,
/// highlighted a moment. Each has a button to reply to it, when you can post. Each is marked read
/// once it's on screen, and what it says is read from the server then, not before.
struct NewsThreadView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.serverTheme) private var theme

  /// The article chosen, which may be a reply, shown in its conversation.
  let article: NewsInfo
  /// Whether you can post to the news, and so reply.
  let canReply: Bool
  /// Replies to an article, starting with a quote of it, or with nothing.
  let reply: (_ article: NewsInfo, _ quote: String) -> Void
  /// The menu for a link to a file.
  let fileLinkMenu: (URL) -> NSMenu?

  /// The article just gone to, highlighted a moment, so it's the one you see.
  @State private var highlighted: NewsInfo.ID?
  /// Articles that couldn't be read from the server, by where they are.
  @State private var unreadable: Set<String> = []
  /// Articles being read from the server, by where they are, to read each only once.
  @State private var loading: Set<String> = []
  /// Where the conversation's scrolled to, set to go to an article, and to scroll with the keys, which
  /// it would go back to the article from otherwise, as it keeps where it was told to go.
  @State private var position = ScrollPosition(idType: NewsInfo.ID.self)
  /// How far it's scrolled, and how much there is, kept out of sight of SwiftUI, which would show it
  /// all again for each step of scrolling otherwise.
  @State private var scrolled = Scrolled()

  /// How far the conversation's scrolled, and how much there is.
  private final class Scrolled {
    var geometry: ScrollGeometry?
  }

  /// The room around the replies.
  private static let margin: CGFloat = 12
  /// How far in each post's words are from its edges.
  private static let inset: CGFloat = 16
  /// How round each post's corners are.
  private static let cornerRadius: CGFloat = 10
  /// How far in from a reply's edges its highlight is, and how round, as round as the corners around
  /// it, for as far in.
  private static let highlightInset: CGFloat = 6
  private static let highlightRadius = cornerRadius - highlightInset
  /// How far in from what it replies to each reply to a reply is.
  private static let indent: CGFloat = 20
  /// How deep replies go in, past which they stay as far in as the deepest.
  private static let deepest = 4

  /// An article in the conversation, how many replies deep it is, and where it is, to find what it
  /// says by.
  private struct Entry: Identifiable {
    let article: NewsInfo
    let depth: Int
    let place: String

    var id: NewsInfo.ID { self.article.id }
  }

  var body: some View {
    let first = self.first(of: self.article)
    let thread = Self.thread(from: first)
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(thread.enumerated()), id: \.element.id) { index, entry in
          Group {
            if index == 0 {
              // Its words in line with the replies'.
              self.post(entry, isFirst: true, title: first.name)
                .padding(.horizontal, Self.margin + Self.inset)
                .padding(.vertical, 20)
                .serverBackground(.content)
            }
            else {
              let stepAbove = Self.step(at: index, in: thread)
              let shape = ReplyShape(cornerRadius: Self.cornerRadius, stepAbove: stepAbove, stepBelow: Self.step(at: index + 1, in: thread))
              self.post(entry, isFirst: false, title: first.name)
                .padding(Self.inset)
                // Highlighted a moment, when it's gone to, behind its words, in the color of
                // selected text, inside its edges, clear of the lines between replies.
                .background {
                  RoundedRectangle(cornerRadius: Self.highlightRadius)
                    .fill(self.theme?.textSelection.map { Color(nsColor: $0) } ?? Color(nsColor: .selectedTextBackgroundColor))
                    .padding(Self.highlightInset)
                    .opacity(self.highlighted == entry.id ? 1 : 0)
                }
                .background(.serverSurface(.post), in: shape)
                // A line between it and the reply above, as far in as the words of the one further
                // in.
                .overlay(alignment: .top) {
                  if let stepAbove {
                    Divider()
                      .serverThemedDivider()
                      .padding(.leading, Self.inset + max(0, -stepAbove))
                      .padding(.trailing, Self.inset)
                  }
                }
                .padding(.leading, Self.leading(of: entry))
                .padding(.trailing, Self.margin)
                // Right under the reply above, or for the first, apart from the article.
                .padding(.top, index == 1 ? Self.margin : 0)
            }
          }
          .id(entry.id)
        }
      }
      .padding(.bottom, thread.count > 1 ? Self.margin : 0)
      // The keys scroll through it all, from the room between posts, or after a post with them is
      // scrolled away, through where it's scrolled to.
      .background(KeyScrolling { amount, down in
        self.scroll(amount, down: down)
      })
    }
    .scrollPosition(self.$position)
    .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in
      self.scrolled.geometry = geometry
    }
    // Gray behind the replies, and on down to the bottom, when there are any.
    .serverBackground(thread.count > 1 ? .thread : .content)
    .onChange(of: self.article, initial: true) { _, article in
      self.go(to: article, first: first)
    }
  }

  // MARK: Conversation

  /// The article a reply's conversation starts with, the one that isn't a reply.
  private func first(of article: NewsInfo) -> NewsInfo {
    var first = article
    var seen: Set<NewsInfo.ID> = [article.id]
    while let parent = first.parentArticleLookupPath.flatMap({ self.model.newsLookup[$0] }), !seen.contains(parent.id) {
      seen.insert(parent.id)
      first = parent
    }
    return first
  }

  /// An article and all the replies to it, each after what it replies to, and the replies to each
  /// newest first, as the list of articles has them, the other way from the server's order.
  private static func thread(from first: NewsInfo) -> [Entry] {
    var entries: [Entry] = []
    var seen: Set<NewsInfo.ID> = []
    func add(_ article: NewsInfo, depth: Int) {
      guard seen.insert(article.id).inserted, let place = article.lookupPath else {
        return
      }
      entries.append(Entry(article: article, depth: depth, place: place))
      for reply in article.children.reversed() where reply.type == .article {
        add(reply, depth: depth + 1)
      }
    }
    add(first, depth: 0)
    return entries
  }

  /// How much further in a reply is than the reply right above it, which it's joined to: more under
  /// what it replies to, less back out from the replies to another reply above it, or none under
  /// another reply to the same one. Nil for the first reply, with only the article above it, and
  /// past the last.
  private static func step(at index: Int, in thread: [Entry]) -> CGFloat? {
    guard index > 1, index < thread.count else {
      return nil
    }
    return Self.leading(of: thread[index]) - Self.leading(of: thread[index - 1])
  }

  /// How far in a reply is: further for each reply it's a reply to, as far as the deepest go.
  private static func leading(of entry: Entry) -> CGFloat {
    Self.margin + CGFloat(min(entry.depth, Self.deepest) - 1) * Self.indent
  }

  /// Reads what an article says from the server, once it's on screen, unless it's been read
  /// already, or is being read, or couldn't be. Once it's started, it goes on even if the article's
  /// scrolled away again, for it to be there when it's back.
  private func load(_ place: String) {
    guard self.model.newsArticleTexts[place] == nil, !self.unreadable.contains(place), self.loading.insert(place).inserted else {
      return
    }
    Task { @MainActor in
      let read = await self.model.loadNewsArticleText(at: place)
      self.loading.remove(place)
      if !read {
        self.unreadable.insert(place)
      }
    }
  }

  /// Goes to an article, at the top of the conversation for the first, or to a reply, highlighted a
  /// moment.
  private func go(to article: NewsInfo, first: NewsInfo) {
    Task { @MainActor in
      self.position.scrollTo(id: article.id, anchor: .top)
      guard article !== first else {
        return
      }
      withAnimation(.easeOut(duration: 0.25)) {
        self.highlighted = article.id
      }
      try? await Task.sleep(for: .seconds(1.4))
      guard self.highlighted == article.id else {
        return
      }
      withAnimation(.easeInOut(duration: 0.9)) {
        self.highlighted = nil
      }
    }
  }

  /// Scrolls as a key does, from where it's scrolled to, as far as there's more of the conversation,
  /// or all the way, through where it's scrolled to, in place of the article it went to.
  private func scroll(_ amount: NSScrollView.KeyScroll, down: Bool) {
    guard let geometry = self.scrolled.geometry else {
      return
    }
    if amount == .all {
      self.position.scrollTo(edge: down ? .bottom : .top)
      return
    }
    let distance = amount.distance(shown: geometry.containerSize.height, whole: geometry.contentSize.height)
    let top = -geometry.contentInsets.top
    let bottom = max(top, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
    self.position.scrollTo(y: min(max(geometry.contentOffset.y + (down ? distance : -distance), top), bottom))
  }

  // MARK: Posts

  private func post(_ entry: Entry, isFirst: Bool, title: String) -> some View {
    let article = entry.article
    let text = self.model.newsArticleTexts[entry.place]
    // A reply's title, unless it only says it's a reply to the conversation's.
    let showsTitle = isFirst || Self.withoutReplyMarks(article.name).caseInsensitiveCompare(Self.withoutReplyMarks(title)) != .orderedSame

    return VStack(alignment: .leading, spacing: 0) {
      // Who wrote it, when, and replying to it.
      HStack(alignment: .firstTextBaseline) {
        Text(article.articleUsername ?? "Unknown")
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.enabled)
        Spacer()
        if let date = article.articleDate {
          Text(NewsItemView.dateFormatter.string(from: date))
            .foregroundStyle(.serverSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
        }
        if self.canReply {
          Button {
            self.reply(article, "")
          } label: {
            Image(systemName: "arrowshape.turn.up.left")
          }
          .buttonStyle(.borderless)
          .help("Reply to \(article.articleUsername ?? "This Article")")
          .padding(.leading, 6)
        }
      }
      .padding(.bottom, isFirst ? 16 : 8)

      // Under the article's, a line across, between who wrote it and what it says.
      if isFirst {
        Divider()
          .serverThemedDivider()
          .padding(.bottom, 16)
      }

      if showsTitle {
        Text(article.name)
          .font(isFirst ? .title : .headline)
          .textSelection(.enabled)
          .padding(.bottom, isFirst ? 12 : 6)
      }

      Group {
        if let text {
          MarkdownText(
            text: text,
            menuItems: {
              [TextMenuItem("Quote in Reply", systemImage: "quote.opening", isEnabled: self.canReply) {
                self.reply(article, Markdown.quote(text, by: article.articleUsername))
              }]
            },
            fileLinkMenu: self.fileLinkMenu
          )
        }
        else if self.unreadable.contains(entry.place) {
          Text("This article couldn't be read.")
            .foregroundStyle(.secondary)
        }
        else {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      article.read = true
      self.load(entry.place)
    }
  }

  /// A title without the Re: a reply's starts with, however many times.
  private static func withoutReplyMarks(_ title: String) -> String {
    var title = Substring(title.trimmingCharacters(in: .whitespaces))
    while title.lowercased().hasPrefix("re:") {
      title = title.dropFirst(3).drop(while: \.isWhitespace)
    }
    return String(title)
  }
}

/// A reply's card: round at its corners, but square where it's joined to the reply above or below
/// it, for the two to be one. Where one of the two is further in than the other, the edge of the one
/// further in curves out into the edge of the other, as the inside of a corner does, beside the
/// other's own round corner.
private struct ReplyShape: Shape {
  let cornerRadius: CGFloat
  /// How much further in it is than the reply right above it, when it's joined to it: more, under
  /// what it replies to, or less, back out from the replies to another, or none.
  let stepAbove: CGFloat?
  /// How much further in the reply right below it is, when it's joined to it.
  let stepBelow: CGFloat?

  func path(in rect: CGRect) -> Path {
    let radius = self.cornerRadius
    // A corner beside a reply joined to it, further in by `step`, is round, as small as it has to
    // be for the curve into that reply's edge to fit beside it. One beside a reply as far in, or
    // further out, is square, as that reply's edge goes on from it.
    func corner(besideStep step: CGFloat?) -> CGFloat {
      guard let step else {
        return radius
      }
      return step > 0 ? min(radius, step / 2) : 0
    }
    var path = UnevenRoundedRectangle(
      topLeadingRadius: corner(besideStep: self.stepAbove.map { -$0 }),
      bottomLeadingRadius: corner(besideStep: self.stepBelow),
      bottomTrailingRadius: self.stepBelow == nil ? radius : 0,
      topTrailingRadius: self.stepAbove == nil ? radius : 0
    ).path(in: rect)
    // The inside of the corner where it meets the reply above, at whichever's edge is further in.
    if let step = self.stepAbove, step != 0 {
      let curve = min(radius, abs(step) / 2)
      if step > 0 {
        // Its own edge, curving out into the bottom of the one above.
        path.move(to: CGPoint(x: rect.minX - curve, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + curve), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      }
      else {
        // The edge of the one above, curving out into its own top.
        let edge = rect.minX - step
        path.move(to: CGPoint(x: edge, y: rect.minY - curve))
        path.addQuadCurve(to: CGPoint(x: edge - curve, y: rect.minY), control: CGPoint(x: edge, y: rect.minY))
        path.addLine(to: CGPoint(x: edge, y: rect.minY))
      }
      path.closeSubpath()
    }
    return path
  }
}
