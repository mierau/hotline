import SwiftUI
import MarkdownUI
import SplitView

struct NewsView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.openWindow) private var openWindow
  @Environment(\.colorScheme) private var colorScheme
  
  @State private var selection: NewsInfo?
  @State private var articleText: String?
  @State private var splitHidden = SideHolder(.bottom)
  @State private var splitFraction = FractionHolder.usingUserDefaults(0.25, key: "News Split Fraction")
  @State private var editorOpen: Bool = false
  @State private var replyOpen: Bool = false
  @State private var loading: Bool = false
  
  var body: some View {
    Group {
      if model.serverVersion < 151 {
        VStack {
          Text("No News")
            .bold()
            .foregroundStyle(.secondary)
            .font(.title3)
          Text("This server has news turned off.")
            .foregroundStyle(.tertiary)
            .font(.system(size: 13))
        }
        .padding()
      }
      else {
        NavigationStack {
          VSplit(
            top: {
              if !model.newsLoaded {
                loadingIndicator
              }
              else if model.news.isEmpty {
                ZStack(alignment: .center) {
                  Text("No News")
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
                }
                .frame(maxWidth: .infinity)
              }
              else {
                newsBrowser
              }
            },
            bottom: {
              articleViewer
            }
          )
          .fraction(splitFraction)
          .constraints(minPFraction: 0.1, minSFraction: 0.3)
          .hide(splitHidden)
          .styling(color: colorScheme == .dark ? .black : Splitter.defaultColor, inset: 0, visibleThickness: 0.5, invisibleThickness: 5, hideSplitter: true)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color(nsColor: .textBackgroundColor))
        }
        .task {
          if !model.newsLoaded {
            loading = true
            await model.getNewsList()
            loading = false
          }
        }
      }
    }
    .sheet(isPresented: $editorOpen) {
    } content: {
      if let selection = selection {
        switch selection.type {
        case .article, .category:
          NewsEditorView(editorTitle: selection.path.last ?? "New Post", isReply: false, path: selection.path, parentID: 0)
        default:
          EmptyView()
        }
      }
      else {
        EmptyView()
      }
    }
    .sheet(isPresented: $replyOpen) {
    } content: {
      if let selection = selection, selection.type == .article {
        NewsEditorView(editorTitle: "Reply to \(selection.articleUsername ?? "Post")", isReply: true, path: selection.path, parentID: UInt32(selection.articleID!), title: selection.name.replyToString())
      }
      else {
        EmptyView()
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          if selection?.type == .category || selection?.type == .article {
            editorOpen = true
          }
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .help("New Post")
        .disabled(selection?.type != .category && selection?.type != .article)
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          if selection?.type == .article {
            replyOpen = true
          }
        } label: {
          Image(systemName: "arrowshape.turn.up.left")
        }
        .help("Reply to Post")
        .disabled(selection?.type != .article)
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          loading = true
          if let selectionPath = selection?.path {
            Task {
              await model.getNewsList(at: selectionPath)
              loading = false
            }
          }
          else {
            Task {
              await model.getNewsList()
              loading = false
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Reload News")
        .disabled(loading)
      }
    }
  }
  
  var newsBrowser: some View {
    List(model.news, id: \.self, selection: $selection) { newsItem in
      NewsItemView(news: newsItem, depth: 0).tag(newsItem.id)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.defaultMinListRowHeight, 28)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .contextMenu(forSelectionType: NewsInfo.self) { items in
      let selectedItem = items.first
      
      Button {
        if selectedItem?.type == .article {
          replyOpen = true
        }
      } label: {
        Label("Reply to \(selectedItem?.articleUsername ?? "Post")", systemImage: "arrowshape.turn.up.left")
      }
      .disabled(selectedItem == nil || selectedItem?.type != .article)
      
    } primaryAction: { items in
      guard let clickedNews = items.first else {
        return
      }
      
      self.selection = clickedNews
      if clickedNews.type == .bundle || clickedNews.type == .category || clickedNews.children.count > 0 {
        clickedNews.expanded.toggle()
      }
    }
    .onChange(of: selection) {
      self.articleText = nil
      if let article = selection, article.type == .article {
        article.read = true
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
      if let s = selection, s.expandable {
        s.expanded = true
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.leftArrow) {
      if let s = selection, s.expandable {
        s.expanded = false
        return .handled
      }
      return .ignored
    }
  }
  
  var loadingIndicator: some View {
    VStack {
      HStack {
        ProgressView {
          Text("Loading Newsgroups")
        }
        .controlSize(.regular)
      }
    }
    .frame(maxWidth: .infinity)
  }
  
  var articleViewer: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if let selection = selection, selection.type == .article {
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
        else {
          HStack(alignment: .center) {
            Spacer()
            HStack(alignment: .center, spacing: 8) {
//              Image(systemName: "doc.append")
//                .resizable()
//                .scaledToFit()
//                .foregroundStyle(.tertiary)
//                .frame(width: 16, height: 16)
              Text("Select a news post to read")
                .foregroundStyle(.tertiary)
                .font(.system(size: 13))
            }
            Spacer()
          }
          .padding()
          .padding(.top, 48)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .transition(.move(edge: .bottom))
  }
}

#Preview {
  NewsView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
