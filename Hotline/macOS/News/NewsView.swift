import SwiftUI
import SplitView

/// The server's news, in three parts. At the top on the left are its categories, which open to show
/// the topics in them, and its topics. Beside them are the articles of the topic chosen, newest
/// first, which open to show the replies to them. Below both is the article chosen, in its
/// conversation. Dragging between the parts makes them bigger or smaller, and the topic and article
/// chosen stay chosen while the server's other parts are shown.
struct NewsView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.openWindow) private var openWindow
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverTheme) private var theme
  @Environment(\.displayScale) private var displayScale
  
  /// The server's window, which keeps the topic and article chosen.
  let serverState: ServerState

  @State private var splitFraction = FractionHolder.usingUserDefaults(0.25, key: "News Split Fraction")
  /// How much of the width the topics have, beside the articles. They keep their width as the
  /// window's made wider or narrower, and the articles take the rest.
  @State private var topicsFraction = FractionHolder.usingUserDefaults(0.3, key: "News Topics Split Fraction")
  /// The topic a new article's being written in, in the sheet for it.
  @State private var writingIn: NewsInfo?
  /// The article being replied to, in the sheet for it, and what the reply starts with.
  @State private var replyingTo: NewsInfo?
  @State private var replyQuote = ""
  @State private var loading: Bool = false
  /// The topic whose articles are being read from the server, by where it is.
  @State private var loadingTopic: String?
  /// The topic whose articles couldn't be read from the server, by where it is.
  @State private var unreadableTopic: String?
  @State private var newFolderShown: Bool = false
  @State private var newCategoryShown: Bool = false
  /// What's to be deleted, once that's confirmed.
  @State private var toDelete: NewsInfo?
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
            HSplit(
              left: {
                self.topicBrowser
              },
              right: {
                self.articleBrowser
              }
            )
            .fraction(self.topicsFraction)
            // As narrow as an eighth of the width, which a window as wide as most screens doesn't
            // make wider than they were made.
            .constraints(minPFraction: 0.12, minSFraction: 0.4, priority: .left)
            // Without lines of their own, which would keep the color they first show with when the
            // theme comes or goes. The topics and the article have them along their edges instead.
            .styling(inset: 0, visibleThickness: 0, invisibleThickness: 5)
          },
          bottom: {
            self.articleViewer
              .overlay(alignment: .top) {
                self.splitLine(.horizontal)
              }
          }
        )
        .fraction(self.splitFraction)
        .constraints(minPFraction: 0.1, minSFraction: 0.3)
        .styling(inset: 0, visibleThickness: 0, invisibleThickness: 5, hideSplitter: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    // The topics' and articles' color, under them, and the toolbar over them, and what shows while
    // news loads.
    .serverBackground(.browser)
    .task {
      if !self.model.newsLoaded {
        self.loading = true
        try? await self.model.getNewsList()
        self.loading = false
      }
    }
    .sheet(item: self.$fileDetails) { details in
      FileDetailsSheet(details: details)
    }
    .sheet(item: self.$writingIn) { topic in
      NewsEditorView(editorTitle: topic.path.last ?? "New Article", isReply: false, path: topic.path, parentID: 0, selection: self.articleSelection)
    }
    .sheet(item: self.$replyingTo) {
      self.replyQuote = ""
    } content: { article in
      NewsEditorView(editorTitle: "Reply to \(article.articleUsername ?? "Article")", isReply: true, path: article.path, parentID: UInt32(article.articleID ?? 0), selection: self.articleSelection, title: article.name.replyToString(), quote: self.replyQuote)
    }
    .alert("Are you sure you want to permanently delete \"\(self.toDelete?.name ?? "this item")\"?", isPresented: self.$confirmDeleteShown, presenting: self.toDelete) { item in
      Button("Delete", role: .destructive) {
        Task {
          await self.deleteNewsItem(item)
        }
      }
    } message: { _ in
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
          if let topic = self.topic, topic.type == .category {
            self.write(in: topic)
          }
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .help("New article under current topic")
        .disabled(self.topic?.type != .category || !self.canPost)
      }
      
      ToolbarItem {
        Button {
          self.replyingTo = self.article
        } label: {
          Image(systemName: "arrowshape.turn.up.left")
        }
        .help("Reply to selected article")
        .disabled(self.article == nil || !self.canPost)
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
          self.loading = true
          let path = self.topic?.path ?? []
          Task {
            try? await self.model.getNewsList(at: path)
            self.loading = false
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Reload selected topic")
        .disabled(self.loading)
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
  
  // MARK: - Topics

  /// The topic chosen, or category of topics, as the news has it now.
  private var topic: NewsInfo? {
    self.serverState.newsTopic.flatMap { self.model.newsLookup[$0] }
  }

  /// The topic chosen, for the list of them. Choosing another puts away the article chosen in the
  /// last.
  private var topicSelection: Binding<NewsInfo?> {
    Binding {
      self.topic
    } set: { topic in
      let place = topic?.lookupPath
      guard place != self.serverState.newsTopic else {
        return
      }
      self.serverState.newsTopic = place
      self.serverState.newsArticle = nil
    }
  }

  /// The server's categories, which open to show the topics in them, and its topics, one of which is
  /// chosen for its articles to be listed beside them.
  private var topicBrowser: some View {
    List(self.model.news, id: \.self, selection: self.topicSelection) { item in
      NewsItemView(news: item, depth: 0).tag(item.id)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.defaultMinListRowHeight, 28)
    .listStyle(.inset)
    .serverThemedList(selection: self.topic)
    .accessibilityLabel("Topics")
    .contextMenu(forSelectionType: NewsInfo.self) { items in
      self.topicMenu(for: items.first)
    } primaryAction: { items in
      guard let item = items.first else {
        return
      }
      self.topicSelection.wrappedValue = item
      if item.type == .bundle {
        item.expanded.toggle()
      }
    }
    .onKeyPress(.rightArrow) {
      self.open(self.topic, true)
    }
    .onKeyPress(.leftArrow) {
      self.open(self.topic, false)
    }
    .overlay(alignment: .trailing) {
      self.splitLine(.vertical)
    }
  }

  /// The menu for a category or topic in the topics, or for none.
  @ViewBuilder
  private func topicMenu(for item: NewsInfo?) -> some View {
    // New topics and categories go in the category clicked, or at the top, without one.
    let inside = item == nil || item?.type == .bundle

    Button {
      if let item {
        self.write(in: item)
      }
    } label: {
      Label("New Article", systemImage: "square.and.pencil")
    }
    .disabled(item?.type != .category || !self.canPost)

    Divider()

    Button {
      self.topicSelection.wrappedValue = item
      self.newCategoryShown = true
    } label: {
      Label("New Topic", systemImage: "newspaper")
    }
    .disabled(!inside || self.model.access?.contains(.canCreateNewsCategories) != true)

    Button {
      self.topicSelection.wrappedValue = item
      self.newFolderShown = true
    } label: {
      Label("New Category", systemImage: "tray")
    }
    .disabled(!inside || self.model.access?.contains(.canCreateNewsFolders) != true)

    Divider()

    Button {
      self.confirmDelete(item)
    } label: {
      Label(self.deleteLabel(for: item), systemImage: "trash")
    }
    .disabled(!self.canDeleteSelectedItem(item))
  }

  /// A line between the parts of the news, up between the topics and the articles, or across, over
  /// the article: a pixel in the server's theme, or half a point without one, darker than what it's
  /// between, as the system's are.
  private func splitLine(_ axis: Axis) -> some View {
    let thickness = self.theme == nil ? 0.5 : 1 / self.displayScale
    return Rectangle()
      .fill(self.splitLineColor)
      .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
      .allowsHitTesting(false)
  }

  /// The lines' color: in light mode, the server's theme's color for lines, or gray without one, and
  /// in dark mode, black, or in the theme, black part way, a darker shade of its color, where its
  /// color for lines would be lighter than what they're between, as it's for text.
  private var splitLineColor: Color {
    if self.colorScheme == .dark {
      return self.theme == nil ? .black : .black.opacity(0.6)
    }
    return self.theme.map { Color(nsColor: $0.tertiaryText) } ?? Splitter.defaultColor
  }

  // MARK: - Articles

  /// The article chosen, in the topic's.
  private var article: NewsInfo? {
    self.serverState.newsArticle.flatMap { self.model.newsLookup[$0] }
  }

  /// The article chosen, for the list of them, which is read once it's chosen.
  private var articleSelection: Binding<NewsInfo?> {
    Binding {
      self.article
    } set: { article in
      self.serverState.newsArticle = article?.lookupPath
      if let article, !article.read {
        article.read = true
      }
    }
  }

  /// The articles of the topic chosen, newest first, which open to show the replies to them, one of
  /// which is chosen to read below. While they're read from the server, or without any, or without a
  /// topic, it says so.
  private var articleBrowser: some View {
    let topic = self.topic.flatMap { $0.type == .category ? $0 : nil }
    return ScrollViewReader { proxy in
      List(topic?.children.reversed() ?? [], id: \.self, selection: self.articleSelection) { article in
        NewsItemView(news: article, depth: 0).tag(article.id)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .environment(\.defaultMinListRowHeight, 28)
      .listStyle(.inset)
      .serverThemedList(selection: self.article)
      .accessibilityLabel("Articles")
      .overlay {
        if let topic {
          if topic.children.isEmpty {
            if self.loadingTopic == topic.lookupPath {
              ProgressView()
                .controlSize(.small)
            }
            else {
              self.placeholder(self.unreadableTopic == topic.lookupPath ? "Couldn't Load Articles" : "No Articles")
            }
          }
        }
        else {
          self.placeholder("No Topic Selected")
        }
      }
      .contextMenu(forSelectionType: NewsInfo.self) { items in
        self.articleMenu(for: items.first, in: topic)
      } primaryAction: { items in
        guard let article = items.first else {
          return
        }
        self.articleSelection.wrappedValue = article
        if !article.children.isEmpty {
          article.expanded.toggle()
        }
      }
      .onKeyPress(.rightArrow) {
        self.open(self.article, true)
      }
      .onKeyPress(.leftArrow) {
        self.open(self.article, false)
      }
      // The article chosen in sight, as it was when it was chosen, once the news is shown again, or
      // its articles are read again, or one's just been posted.
      .onChange(of: self.article, initial: true) { _, article in
        self.reveal(article, with: proxy)
      }
    }
    // A list of its own for each topic, from the top, with its articles read again each time it's
    // chosen, for what's been posted since.
    .id(topic?.id)
    .task(id: topic?.id) {
      if let topic {
        await self.loadArticles(in: topic)
      }
    }
  }

  /// The menu for an article in a topic's articles, or for none.
  @ViewBuilder
  private func articleMenu(for article: NewsInfo?, in topic: NewsInfo?) -> some View {
    Button {
      if let topic {
        self.write(in: topic)
      }
    } label: {
      Label("New Article", systemImage: "square.and.pencil")
    }
    .disabled(topic == nil || !self.canPost)

    Button {
      self.replyingTo = article
    } label: {
      Label("Reply...", systemImage: "arrowshape.turn.up.left")
    }
    .disabled(article == nil || !self.canPost)

    Divider()

    Button {
      self.confirmDelete(article)
    } label: {
      Label(self.deleteLabel(for: article), systemImage: "trash")
    }
    .disabled(!self.canDeleteSelectedItem(article))
  }

  /// Shows an article in the list of them: the replies it's among open, and scrolled to, as little as
  /// it takes, once the rows it opened are there.
  private func reveal(_ article: NewsInfo?, with proxy: ScrollViewProxy) {
    guard let article else {
      return
    }
    var seen: Set<NewsInfo.ID> = [article.id]
    var parent = article.parentArticleLookupPath.flatMap { self.model.newsLookup[$0] }
    while let reply = parent, seen.insert(reply.id).inserted {
      if !reply.expanded {
        reply.expanded = true
      }
      parent = reply.parentArticleLookupPath.flatMap { self.model.newsLookup[$0] }
    }
    DispatchQueue.main.async {
      proxy.scrollTo(article)
    }
  }

  /// Reads a topic's articles from the server, saying so while it does, or if it can't.
  private func loadArticles(in topic: NewsInfo) async {
    guard let place = topic.lookupPath else {
      return
    }
    self.loadingTopic = place
    do {
      try await self.model.getNewsList(at: topic.path)
      if self.unreadableTopic == place {
        self.unreadableTopic = nil
      }
    }
    catch {
      if !Task.isCancelled {
        self.unreadableTopic = place
      }
    }
    if self.loadingTopic == place {
      self.loadingTopic = nil
    }
  }

  /// A word on what isn't there, where it would be, which clicks go through to the list under it.
  private func placeholder(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.title3)
      .foregroundStyle(.serverSecondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(false)
  }

  /// The article chosen, in its conversation, with the replies to it, and the replies to those.
  private var articleViewer: some View {
    Group {
      if let article = self.article {
        NewsThreadView(article: article, canReply: self.canPost) { article, quote in
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
  
  /// Opens or closes what's chosen, when it opens: a category, in the topics, or an article with
  /// replies, in the articles.
  private func open(_ item: NewsInfo?, _ opened: Bool) -> KeyPress.Result {
    guard let item, item.type == .bundle || (item.type == .article && !item.children.isEmpty) else {
      return .ignored
    }
    item.expanded = opened
    return .handled
  }

  /// Writes a new article in a topic, chosen first, for the article to be chosen in it once it's
  /// posted.
  private func write(in topic: NewsInfo) {
    self.topicSelection.wrappedValue = topic
    self.writingIn = topic
  }

  private var selectedBundlePath: [String] {
    guard let topic = self.topic else { return [] }
    switch topic.type {
    case .bundle:
      return topic.path
    case .category, .article:
      if topic.path.count > 1 {
        return Array(topic.path.dropLast())
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
  
  /// Asks before deleting a category, topic or article.
  private func confirmDelete(_ item: NewsInfo?) {
    guard let item else {
      return
    }
    self.toDelete = item
    self.confirmDeleteShown = true
  }

  /// Deletes a category, topic or article, and once it's gone, it isn't chosen, nor what was in it.
  private func deleteNewsItem(_ item: NewsInfo) async {
    switch item.type {
    case .bundle, .category:
      guard (try? await self.model.deleteNewsItem(path: item.path)) != nil else {
        return
      }
      if let topic = self.topic, topic.path.starts(with: item.path) {
        self.topicSelection.wrappedValue = nil
      }
    case .article:
      guard let articleID = item.articleID, (try? await self.model.deleteNewsArticle(id: articleID, path: item.path)) != nil else {
        return
      }
      if self.article === item {
        self.articleSelection.wrappedValue = nil
      }
    }
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
  NewsView(serverState: ServerState(selection: .news))
    .environment(HotlineState())
}
