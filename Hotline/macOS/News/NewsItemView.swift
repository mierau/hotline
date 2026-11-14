import SwiftUI

/// A row in the news: in the topics, a category, which opens to show the topics and categories in
/// it, or a topic, which doesn't, as its articles are listed beside it, each with how many it has;
/// or in a topic's articles, an article, which opens to show the replies to it, and the replies to
/// those, with who wrote it and when.
struct NewsItemView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  
  var news: NewsInfo
  let depth: Int

  /// How wide the arrows' column is, before the icon or title, and as much, how much further in each
  /// row is than the one it's in, for each arrow to be under the start of what it's in, as the
  /// Finder has them. Rows without an arrow keep the column, for titles to line up.
  private static let indent: CGFloat = 15

  /// Whether it opens: a category, to what's in it, or an article with replies, to them.
  private var opens: Bool {
    switch self.news.type {
    case .bundle:
      return true
    case .category:
      return false
    case .article:
      return !self.news.children.isEmpty
    }
  }
  
  static var dateFormatter: DateFormatter = {
    var dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .long
    dateFormatter.timeStyle = .short
    dateFormatter.timeZone = .gmt
    return dateFormatter
  }()
  
  static var relativeDateFormatter: RelativeDateTimeFormatter = {
    var formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    formatter.formattingContext = .listItem
    return formatter
  }()
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      // Tree indent, before the arrow, for each arrow to be beside what it opens.
      Spacer()
        .frame(width: CGFloat(self.depth) * Self.indent)

      if self.opens {
        Button {
          news.expanded.toggle()
        } label: {
          Text(Image(systemName: news.expanded ? "chevron.down" : "chevron.right"))
            .fontWeight(.semibold)
            .font(.system(size: 10))
            .foregroundStyle(.serverDisclosure)
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: 10)
        .padding(.trailing, Self.indent - 10)
      }
      else {
        Spacer()
          .frame(width: Self.indent)
      }
      
      switch news.type {
      case .category:
        Image("News Category")
          .resizable()
          .frame(width: 16, height: 16, alignment: .center)
          .padding(.trailing, 6)
      case .bundle:
        Image("News Bundle")
          .resizable()
          .frame(width: 16, height: 16, alignment: .center)
          .padding(.trailing, 6)
      case .article:
        EmptyView()
      }
      
      Text(news.name.hidingOffensiveWords)
        .fontWeight((news.type == .bundle || news.type == .category || !news.read) ? .semibold : .regular)
        .lineLimit(1)
        .truncationMode(.tail)
      
      if news.type == .article && news.articleUsername != nil {
        Text(news.articleUsername!)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 8)
      }
      
      Spacer()
      
      // How many articles a topic has, or topics a category, as a number, in the narrow list of
      // them, with what of in its tip.
      if news.type == .category && news.count > 0 {
        Text(Int(news.count), format: .number)
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .padding(.trailing, 8)
          .help(Text("^[\(news.count) Article](inflect: true)"))
      }
      else if news.type == .bundle && news.count > 0 {
        Text(Int(news.count), format: .number)
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .padding(.trailing, 8)
          .help(Text("^[\(news.count) Category](inflect: true)"))
      }
//      if news.type == .bundle {
//        Text("\(news.count)")
//          .lineLimit(1)
//          .foregroundStyle(.tertiary)
//          .padding(.trailing, 8)
        
//        ZStack {
//          Text("^[\(news.count) \(news.type == .bundle ? "Category" : "Article")](inflect: true)")
//          Text("\(news.count)")
//            .foregroundStyle(.clear)
////            .font(.caption)
//            .lineLimit(1)
//            .padding([.leading, .trailing], 8)
//            .padding([.top, .bottom], 2)
//            .background(.secondary)
//            .clipShape(Capsule())
//          
//          Text("\(news.count)")
//            .foregroundStyle(.white)
////            .font(.caption)
//            .lineLimit(1)
//            .padding([.leading, .trailing], 8)
//            .padding([.top, .bottom], 2)
//            .blendMode(.destinationOut)
//        }
//        .drawingGroup(opaque: false)
//      }
      else if news.type == .article && news.articleUsername != nil {
        if let d = news.articleDate {
          Text(NewsItemView.relativeDateFormatter.localizedString(for: d, relativeTo: Date.now))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.trailing, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: news.expanded) {
      // What's in a category, read as it's opened. A topic's articles are read as it's chosen.
      guard news.expanded, news.type == .bundle else {
        return
      }

      Task {
        try? await model.getNewsList(at: news.path)
      }
    }
    .serverThemedRow(for: self.news)
    
    if news.expanded && self.opens {
      // A category's topics in the server's order, as those at the top are, and an article's
      // replies newest first, as the articles are.
      ForEach(news.type == .article ? news.children.reversed() : news.children, id: \.self) { childNews in
        NewsItemView(news: childNews, depth: self.depth + 1).tag(childNews.id)
      }
    }
  }
}

#Preview {
  NewsItemView(news: NewsInfo(hotlineNewsArticle: HotlineNewsArticle(id: 0, parentID: 0, flags: 0, title: "Title", username: "username", date: Date.now, flavors: [("", 1)], path: ["Guest"])), depth: 0)
    .environment(HotlineState())
}
