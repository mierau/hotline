import SwiftUI
import MarkdownUI
import SplitView

struct NewsView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.openWindow) private var openWindow
  
  @State private var selection: NewsInfo?
  @State private var articleText: String?
  @State private var splitHidden = SideHolder(.bottom)
  @State private var splitFraction = FractionHolder.usingUserDefaults(0.25, key: "News Split Fraction")
  @State private var editorOpen: Bool = false
  
  var body: some View {
    NavigationStack {
      VSplit(
        top: {
          newsBrowser
        },
        bottom: {
          articleViewer
        }
      )
      .fraction(splitFraction)
      .constraints(minPFraction: 0.1, minSFraction: 0.3)
      .hide(splitHidden)
      .styling(inset: 0, visibleThickness: 0.5, invisibleThickness: 5, hideSplitter: true)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .textBackgroundColor))
    }
//    .sheet(isPresented: $editorOpen) {
//      print("Sheet dismissed!")
//    } content: {
//      NewsEditorView()
//    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          
        } label: {
          Image(systemName: "trash")
        }
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
//          if let selection = selection {
//            editorOpen = true
////            openWindow(id: "news-editor", value: NewsArticle(parentID: nil, path: selection.path, title: "", body: ""))
//          }
        } label: {
          Image(systemName: "square.and.pencil")
        }
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          
        } label: {
          Image(systemName: "arrowshape.turn.up.left")
        }
      }
    }
  }
  
  var newsBrowser: some View {
    List(model.news, id: \.self, selection: $selection) { newsItem in
      NewsItemView(news: newsItem, depth: 0).tag(newsItem.id)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .task {
      if !model.newsLoaded {
        let _ = await model.getNewsList()
      }
    }
    .contextMenu(forSelectionType: NewsInfo.self) { items in
        // ...
    } primaryAction: { items in
      guard let clickedNews = items.first else {
        return
      }
      
      self.selection = clickedNews
      if clickedNews.type == .bundle || clickedNews.type == .category {
        clickedNews.expanded.toggle()
      }
    }
    .onChange(of: selection) {
      self.articleText = nil
      if let article = selection, article.type == .article {
        if let articleFlavor = article.articleFlavors?.first,
           let articleID = article.articleID {
          Task {
            if let articleText = await self.model.getNewsArticle(id: articleID, at: article.path, flavor: articleFlavor) {
              self.articleText = articleText
            }
          }
          if self.splitHidden.side != nil {
            withAnimation(.easeOut(duration: 0.15)) {
              self.splitHidden.side = nil
            }
          }
          
        }
      }
      else {
        if self.splitHidden.side != .bottom {
          withAnimation(.easeOut(duration: 0.25)) {
            self.splitHidden.side = .bottom
          }
        }
      }
    }
    .onKeyPress(.rightArrow) {
      if let s = selection, s.type == .bundle || s.type == .category {
        s.expanded = true
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.leftArrow) {
      if let s = selection, s.type == .bundle || s.type == .category {
        s.expanded = false
        return .handled
      }
      return .ignored
    }
    .overlay {
      if !model.newsLoaded {
        VStack {
          ProgressView()
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }
  
  var articleViewer: some View {
    ScrollView {
      if let selection = selection {
        VStack(alignment: .leading, spacing: 0) {
          if let poster = selection.articleUsername, let postDate = selection.articleDate {
            HStack(alignment: .firstTextBaseline) {
              Text(poster)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .padding(.bottom, 16)
              Spacer()
              Text("\(NewsItemView.dateFormatter.string(from: postDate))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .padding(.bottom, 16)
            }
          }
          
          Divider()
          
          Text(selection.name).font(.title)
            .textSelection(.enabled)
            .padding(.bottom, 8)
            .padding(.top, 16)
          
          if let newsText = self.articleText {
            Markdown(newsText)
              .markdownTheme(.basic)
              .textSelection(.enabled)
              .lineSpacing(6)
              .padding(.top, 16)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .transition(.move(edge: .bottom))
  }
}

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
    HStack(alignment: .center, spacing: 6) {
      if news.type == .bundle || news.type == .category {
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
      }
      else if news.type == .article {
        if news.parentID != nil {
          Image(systemName: "arrowshape.turn.up.left.fill")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 10)
            .foregroundStyle(.secondary)
            .opacity(0.5)
        }
      }
      Text(news.name)
        .fontWeight((news.type == .bundle || news.type == .category) ? .bold : .regular)
        .lineLimit(1)
        .truncationMode(.tail)
      if news.type == .article && news.articleUsername != nil {
        Text(news.articleUsername!).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      if news.type == .bundle || news.type == .category {
        Text("^[\(news.count) \(news.type == .bundle ? "Category" : "Post")](inflect: true)")
        
//        Text("\(news.count) \(news.type == .bundle ? "Categories" : "Posts")")
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding([.leading, .trailing], 8)
          .padding([.top, .bottom], 2)
          .background(Capsule(style: .circular).stroke(.secondary.opacity(0.3), lineWidth: 1))
      }
      if news.type == .article && news.articleUsername != nil {
        if let d = news.articleDate {
          Text(NewsItemView.relativeDateFormatter.localizedString(for: d, relativeTo: Date.now)).lineLimit(1).foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.leading, CGFloat(depth * (12 + 10)))
    .onChange(of: news.expanded) {
      if news.type == .bundle || news.type == .category {
        if news.expanded {
          Task {
            await model.getNewsList(at: news.path)
          }
        }
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
  NewsView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
