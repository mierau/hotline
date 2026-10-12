import SwiftUI
import SplitView

struct NewsView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.openWindow) private var openWindow
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverTheme) private var theme
  
  @State private var selection: NewsInfo?
//  @State private var splitHidden: SideHolder = SideHolder(.bottom)
  @State private var splitFraction = FractionHolder.usingUserDefaults(0.25, key: "News Split Fraction")
  @State private var editorOpen: Bool = false
  /// The article being replied to, in the sheet for it, and what the reply starts with.
  @State private var replyingTo: NewsInfo?
  @State private var replyQuote = ""
  @State private var loading: Bool = false
  @State private var newFolderShown: Bool = false
  @State private var newCategoryShown: Bool = false
  @State private var confirmDeleteShown: Bool = false
  @State private var conflictAlertShown: Bool = false
  @State private var pendingCreate: PendingNewsCreate?
  /// A linked file's info, from its link's menu.
  @State private var fileDetails: FileDetails?
  
  var body: some View {
    NavigationStack {
      if self.model.serverVersion < 151 {
        self.disabledNewsView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
      }
      else if !self.model.newsLoaded {
        self.loadingIndicator
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
      }
      else if self.model.news.isEmpty {
        self.emptyNewsView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
      }
      else {
        VSplit(
          top: {
            self.newsBrowser
          },
          bottom: {
            self.articleViewer
          }
        )
        .fraction(splitFraction)
        .constraints(minPFraction: 0.1, minSFraction: 0.3)
        // In the server's theme, no line, only the topics' deeper color meeting the article's. Its
        // thickness changes with the theme, where its color is only taken when it first shows.
        .styling(color: colorScheme == .dark ? .black : Splitter.defaultColor, inset: 0, visibleThickness: self.theme == nil ? 0.5 : 0, invisibleThickness: 5, hideSplitter: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    // The topics' color, under them, and the toolbar over them, and what shows while news loads.
    .serverBackground(.browser)
    .task {
      if !model.newsLoaded {
        loading = true
        try? await model.getNewsList()
        loading = false
      }
    }
    .sheet(item: self.$fileDetails) { details in
      FileDetailsSheet(details: details)
    }
    .sheet(isPresented: $editorOpen) {
    } content: {
      if let selection = selection {
        switch selection.type {
        case .article, .category:
          NewsEditorView(editorTitle: selection.path.last ?? "New Article", isReply: false, path: selection.path, parentID: 0, selection: self.$selection)
        default:
          EmptyView()
        }
      }
      else {
        EmptyView()
      }
    }
    .sheet(item: self.$replyingTo) {
      self.replyQuote = ""
    } content: { article in
      NewsEditorView(editorTitle: "Reply to \(article.articleUsername ?? "Article")", isReply: true, path: article.path, parentID: UInt32(article.articleID ?? 0), selection: self.$selection, title: article.name.replyToString(), quote: self.replyQuote)
    }
    .alert("Are you sure you want to permanently delete \"\(self.selection?.name ?? "this item")\"?", isPresented: self.$confirmDeleteShown) {
      Button("Delete", role: .destructive) {
        if let s = self.selection {
          Task {
            await self.deleteNewsItem(s)
          }
        }
      }
    } message: {
      Text("You cannot undo this action.")
    }
    .alert("An item named \"\(self.pendingCreate?.name ?? "")\" already exists in this location.", isPresented: self.$conflictAlertShown) {
      Button("Replace") {
        if let pending = self.pendingCreate {
          Task {
            try? await self.model.deleteNewsItem(path: pending.path + [pending.name])
            await self.performCreate(pending)
          }
        }
      }
      Button("Keep Both") {
        if let pending = self.pendingCreate {
          let uniqueName = self.uniqueName(pending.name, at: pending.path)
          let adjusted = PendingNewsCreate(name: uniqueName, path: pending.path, kind: pending.kind)
          Task {
            await self.performCreate(adjusted)
          }
        }
      }
      Button("Cancel", role: .cancel) {
        self.pendingCreate = nil
      }
    } message: {
      Text("Do you want to replace it or keep both?")
    }
    .toolbar {
      ToolbarItem {
        Button {
          if selection?.type == .category || selection?.type == .article {
            editorOpen = true
          }
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .help("New article under current topic")
        .disabled(selection?.type != .category && selection?.type != .article || !self.canPost)
      }
      
      ToolbarItem {
        Button {
          if selection?.type == .article {
            self.replyingTo = selection
          }
        } label: {
          Image(systemName: "arrowshape.turn.up.left")
        }
        .help("Reply to selected article")
        .disabled(selection?.type != .article || !self.canPost)
      }
      
      if #available(macOS 26.0, *) {
        ToolbarSpacer(.fixed)
      }
      
      if self.model.access?.contains(.canCreateNewsCategories) == true {
        ToolbarItem {
          Button {
            self.newCategoryShown = true
          } label: {
            Image(systemName: "newspaper")
          }
          .help("Create a new topic")
          .popover(isPresented: self.$newCategoryShown, arrowEdge: .bottom) {
            NewNewsItemPopover(title: "New Topic", placeholder: "Topic Name", defaultName: "Untitled Topic") { name in
              self.createNewsItem(name: name, kind: .category)
            }
          }
        }
      }
      
      if self.model.access?.contains(.canCreateNewsFolders) == true {
        ToolbarItem {
          Button {
            self.newFolderShown = true
          } label: {
            Image(systemName: "tray")
          }
          .help("Create a new category")
          .popover(isPresented: self.$newFolderShown, arrowEdge: .bottom) {
            NewNewsItemPopover(title: "New Category", placeholder: "Category Name", defaultName: "Untitled Category") { name in
              self.createNewsItem(name: name, kind: .folder)
            }
          }
        }
      }
      
      ToolbarItem {
        Button {
          loading = true
          if let selectionPath = selection?.path {
            Task {
              try? await model.getNewsList(at: selectionPath)
              loading = false
            }
          }
          else {
            Task {
              try? await model.getNewsList()
              loading = false
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Reload selected topic")
        .disabled(loading)
      }
    }
  }
  
  private var disabledNewsView: some View {
    ContentUnavailableView {
      Label("No News", systemImage: "newspaper")
    } description: {
      Text("This server has turned off newsgroups")
    }
  }
  
  private var emptyNewsView: some View {
    ContentUnavailableView {
      Label("No News", systemImage: "newspaper")
    } description: {
      Text("This server has no newsgroups")
    }
  }
  
  private var newsBrowser: some View {
    List(model.news, id: \.self, selection: $selection) { newsItem in
      NewsItemView(news: newsItem, depth: 0).tag(newsItem.id)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.defaultMinListRowHeight, 28)
    .listStyle(.inset)
    .serverThemedList(selection: self.selection)
    .contextMenu(forSelectionType: NewsInfo.self) { items in
      let selectedItem = items.first
      let isBackground = items.isEmpty
      let canPost = selectedItem?.type == .category || selectedItem?.type == .article
      let canReply = selectedItem?.type == .article
      let canNewTopic = isBackground || selectedItem?.type == .bundle
      let canNewCategory = isBackground || selectedItem?.type == .bundle
      
      Button {
        self.selection = selectedItem
        self.editorOpen = true
      } label: {
        Label("New Article", systemImage: "square.and.pencil")
      }
      .disabled(!canPost || !self.canPost)
      
      Button {
        self.replyingTo = selectedItem
      } label: {
        Label("Reply...", systemImage: "arrowshape.turn.up.left")
      }
      .disabled(!canReply || !self.canPost)
      
      Divider()
      
      Button {
        self.selection = isBackground ? nil : selectedItem
        self.newCategoryShown = true
      } label: {
        Label("New Topic", systemImage: "newspaper")
      }
      .disabled(!canNewTopic || self.model.access?.contains(.canCreateNewsCategories) != true)
      
      Button {
        self.selection = isBackground ? nil : selectedItem
        self.newFolderShown = true
      } label: {
        Label("New Category", systemImage: "tray")
      }
      .disabled(!canNewCategory || self.model.access?.contains(.canCreateNewsFolders) != true)
      
      Divider()
      
      Button {
        self.selection = selectedItem
        self.confirmDeleteShown = true
      } label: {
        Label(self.deleteLabel(for: selectedItem), systemImage: "trash")
      }
      .disabled(!self.canDeleteSelectedItem(selectedItem))
      
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
      if let article = selection, article.type == .article {
        article.read = true
//          if self.splitHidden.side != nil {
//            withAnimation(.easeOut(duration: 0.15)) {
//              self.splitHidden.side = nil
//            }
//          }
      }
//      else {
//        if self.splitHidden.side != .bottom {
//          withAnimation(.easeOut(duration: 0.25)) {
//            self.splitHidden.side = .bottom
//          }
//        }
//      }
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
  
  private var loadingIndicator: some View {
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
  
  /// The article chosen, in its conversation, with the replies to it, and the replies to those.
  private var articleViewer: some View {
    Group {
      if let selection, selection.type == .article {
        NewsThreadView(article: selection, canReply: self.canPost) { article, quote in
          self.replyQuote = quote
          self.replyingTo = article
        } fileLinkMenu: { url in
          FileLinkMenu(model: self.model, openWindow: self.openWindow, showInfo: { self.fileDetails = $0 }).menu(for: url)
        }
      }
      else {
        ContentUnavailableView {
          Label("No Article", systemImage: "richtext.page")
        } description: {
          Text("Select an article to read")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .transition(.move(edge: .bottom))
    .serverBackground(.content)
  }

  /// Whether you can post to the news, and reply in it.
  private var canPost: Bool {
    self.model.access?.contains(.canPostNews) == true
  }
  
  // MARK: - Helpers
  
  private var selectedBundlePath: [String] {
    guard let selection = self.selection else { return [] }
    switch selection.type {
    case .bundle:
      return selection.path
    case .category, .article:
      if selection.path.count > 1 {
        return Array(selection.path.dropLast())
      }
      return []
    }
  }
  
  private func canDeleteSelectedItem(_ item: NewsInfo?) -> Bool {
    guard let item = item else { return false }
    switch item.type {
    case .bundle:
      return self.model.access?.contains(.canDeleteNewsFolders) == true
    case .category:
      return self.model.access?.contains(.canDeleteNewsCategories) == true
    case .article:
      return self.model.access?.contains(.canDeleteNewsArticles) == true
    }
  }
  
  private func deleteLabel(for item: NewsInfo?) -> String {
    guard let item = item else { return "Delete..." }
    switch item.type {
    case .bundle:
      return "Delete Category..."
    case .category:
      return "Delete Topic..."
    case .article:
      return "Delete Article..."
    }
  }
  
  private func deleteNewsItem(_ item: NewsInfo) async {
    switch item.type {
    case .bundle, .category:
      try? await self.model.deleteNewsItem(path: item.path)
    case .article:
      if let articleID = item.articleID {
        try? await self.model.deleteNewsArticle(id: articleID, path: item.path)
      }
    }
    self.selection = nil
  }
  
  private func createNewsItem(name: String, kind: PendingNewsCreate.Kind) {
    let path = self.selectedBundlePath
    let pending = PendingNewsCreate(name: name, path: path, kind: kind)
    
    if self.newsItemExists(name: name, at: path) {
      self.pendingCreate = pending
      self.conflictAlertShown = true
    }
    else {
      Task {
        await self.performCreate(pending)
      }
    }
  }
  
  private func performCreate(_ pending: PendingNewsCreate) async {
    switch pending.kind {
    case .folder:
      try? await self.model.newNewsFolder(name: pending.name, path: pending.path)
    case .category:
      try? await self.model.newNewsCategory(name: pending.name, path: pending.path)
    }
  }
  
  private func newsItemExists(name: String, at path: [String]) -> Bool {
    let siblings: [NewsInfo]
    if path.isEmpty {
      siblings = self.model.news
    }
    else if let parent = self.findNewsItem(in: self.model.news, at: path) {
      siblings = parent.children
    }
    else {
      return false
    }
    return siblings.contains { $0.name == name }
  }
  
  private func findNewsItem(in items: [NewsInfo], at path: [String]) -> NewsInfo? {
    guard !path.isEmpty, !items.isEmpty else { return nil }
    let currentName = path[0]
    for item in items {
      if item.name == currentName {
        if path.count == 1 {
          return item
        }
        return self.findNewsItem(in: item.children, at: Array(path[1...]))
      }
    }
    return nil
  }
  
  private func uniqueName(_ name: String, at path: [String]) -> String {
    var candidate = name
    var counter = 2
    while self.newsItemExists(name: candidate, at: path) {
      candidate = "\(name) \(counter)"
      counter += 1
    }
    return candidate
  }
}

struct PendingNewsCreate {
  enum Kind {
    case folder
    case category
  }
  
  let name: String
  let path: [String]
  let kind: Kind
}

struct NewNewsItemPopover: View {
  @Environment(\.dismiss) private var dismiss
  
  let title: String
  let placeholder: String
  let defaultName: String
  let action: ((String) -> Void)?
  
  @State private var itemName: String = ""
  
  var body: some View {
    VStack(spacing: 16) {
      TextField(self.placeholder, text: self.$itemName)
        .onSubmit(of: .text) {
          self.create()
        }
      
      HStack(spacing: 8) {
        Spacer()
        
        Button("Cancel", role: .cancel) {
          self.dismiss()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        
        if #available(macOS 26.0, *) {
          Button(self.title, role: .confirm) {
            self.create()
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
        }
        else {
          Button("OK") {
            self.create()
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
        }
      }
    }
    .frame(width: 250)
    .padding()
    .onAppear {
      self.itemName = self.defaultName
    }
  }
  
  private func create() {
    self.dismiss()
    self.action?(self.itemName)
  }
}

#Preview {
  NewsView()
    .environment(HotlineState())
}
