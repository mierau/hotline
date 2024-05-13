import SwiftUI

struct NewsItemView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  var news: NewsInfo
  let depth: Int
  
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
      if news.expandable {
        Button {
          news.expanded.toggle()
        } label: {
          Text(Image(systemName: news.expanded ? "chevron.down" : "chevron.right"))
            .bold()
            .font(.system(size: 10))
            .opacity(0.5)
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: 10)
        .padding(.leading, 4)
        .padding(.trailing, 8)
      }
      else {
        Spacer()
          .frame(width: 10)
          .padding(.leading, 4)
          .padding(.trailing, 8)
      }
      
      // Tree indent
      Spacer()
        .frame(width: (CGFloat(depth) * 22))
      
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
      
      Text(news.name)
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
      
      if news.type == .bundle || news.type == .category {
        ZStack {
//          Text("^[\(news.count) \(news.type == .bundle ? "Category" : "Post")](inflect: true)")
          Text("\(news.count)")
            .foregroundStyle(.clear)
//            .font(.caption)
            .lineLimit(1)
            .padding([.leading, .trailing], 8)
            .padding([.top, .bottom], 2)
            .background(.secondary)
            .clipShape(Capsule())
          
          Text("\(news.count)")
            .foregroundStyle(.white)
//            .font(.caption)
            .lineLimit(1)
            .padding([.leading, .trailing], 8)
            .padding([.top, .bottom], 2)
            .blendMode(.destinationOut)
        }
        .drawingGroup(opaque: false)
      }
      if news.type == .article && news.articleUsername != nil {
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
      guard news.expanded, news.type == .bundle || news.type == .category else {
        return
      }
      
      Task {
        await model.getNewsList(at: news.path)
      }
    }
    
    if news.expanded {
      ForEach(news.children.reversed(), id: \.self) { childNews in
        NewsItemView(news: childNews, depth: self.depth + 1).tag(childNews.id)
      }
    }
  }
}

#Preview {
  NewsItemView(news: NewsInfo(hotlineNewsArticle: HotlineNewsArticle(id: 0, parentID: 0, flags: 0, title: "Title", username: "username", date: Date.now, flavors: [("", 1)], path: ["Guest"])), depth: 0)
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
