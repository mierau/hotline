import SwiftUI

/// A server's saved chat, read-only, in a window of its own, opened from the chat settings. It's
/// shown in the chat's own transcript, and searched the way the chat is.
struct ChatLogView: View {
  let key: ChatStore.SessionKey?

  @State private var messages: [ChatMessage] = []
  @State private var serverName: String?
  @State private var isLoaded = false
  @State private var searchQuery = ""
  @State private var debouncedQuery = ""
  @State private var searchResults: [ChatMessage] = []
  /// How many lines are saved, of which a page at a time is shown, more as it's scrolled back.
  @State private var savedCount = 0
  @State private var hasOlder = true
  @State private var isLoadingOlder = false
  /// Whether a search might find more, from before what it's found.
  @State private var searchHasMore = false
  @State private var isSearchingMore = false
  @State private var isSearching = false
  @State private var searchTask: Task<Void, Never>?
  @State private var linkIndex = ChatLinkIndex()

  var body: some View {
    self.content
      .frame(minWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
      .background {
        if #available(macOS 26.0, *) {
          Color(.windowBackgroundColor)
            .ignoresSafeArea()
        } else {
          Color(nsColor: .textBackgroundColor)
            .ignoresSafeArea()
        }
      }
      .navigationTitle(self.serverName ?? self.key?.identifier ?? "Chat History")
      .navigationSubtitle(self.subtitle)
      .searchable(text: self.$searchQuery, isPresented: self.$isSearching, placement: .toolbar, prompt: "Search")
      .background(Button("", action: { self.isSearching = true }).keyboardShortcut("f").hidden())
      .onChange(of: self.searchQuery) {
        self.searchChanged()
      }
      .task(id: self.key) {
        await self.load()
      }
      .modifier(HistoryChanges(key: self.key) {
        self.clear()
      } pruned: {
        Task {
          await self.load()
        }
      })
  }

  @ViewBuilder
  private var content: some View {
    if self.isLoaded && !self.messages.contains(where: { Prefs.shared.showJoinLeaveMessages || !$0.isConnection }) {
      ContentUnavailableView("No Chat History", systemImage: "bubble.left.and.bubble.right")
    }
    else {
      self.transcript
    }
  }

  private var transcript: some View {
    ChatTranscriptView(
      messages: self.debouncedQuery.isEmpty ? self.messages : self.searchResults,
      searchQuery: self.debouncedQuery,
      watchWords: HighlightWord.chatWords,
      isFiltered: !self.debouncedQuery.isEmpty,
      openURL: { self.open($0) },
      describeHotlineLink: { url in
        // This window isn't connected, so links to servers connect to them.
        Server(url: url).map { "Connect to \($0.displayAddress)" }
      },
      fileLinkMenu: { self.fileLinkMenu(for: $0) },
      showsIcons: Prefs.shared.showChatIcons,
      previewsImages: Prefs.shared.previewChatImages,
      showsConnections: Prefs.shared.showJoinLeaveMessages,
      onNearStart: {
        if self.debouncedQuery.isEmpty {
          self.loadOlder()
        }
        else {
          self.searchMore()
        }
      }
    )
    .ignoresSafeArea(edges: .top)
    .modifier(SoftTopScrollEdge())
  }

  private func searchChanged() {
    self.searchTask?.cancel()
    if self.searchQuery.isEmpty {
      self.debouncedQuery = ""
      self.searchResults = []
      self.searchHasMore = false
    }
    else {
      self.searchTask = Task {
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        self.search()
      }
    }
  }

  /// The server's address, under its name, and how many messages there are, or how many a search
  /// has found so far.
  private var subtitle: String {
    let count = self.debouncedQuery.isEmpty ? self.savedCount : self.searchResults.filter { $0.type != .signOut }.count
    let more = !self.debouncedQuery.isEmpty && self.searchHasMore ? "+" : ""
    let messages = count == 1 ? "1 message" : "\(count.formatted())\(more) messages"
    guard self.serverName != nil, let address = self.key?.identifier else {
      return messages
    }
    return "\(address) · \(messages)"
  }

  private func load() async {
    guard let key = self.key else {
      return
    }
    // The newest of it, and more as it's scrolled back.
    let summary = await ChatStore.shared.summary(for: key)
    let messages = await ChatStore.shared.loadPage(for: key, count: HotlineState.maxChatMessages).compactMap(ChatMessage.init(entry:))
    // A history of only disconnects has nothing in it to read.
    self.messages = messages.contains { $0.type != .signOut } ? messages : []
    self.serverName = summary.metadata?.serverName
    self.savedCount = summary.count
    self.hasOlder = true
    self.isLoaded = true
    if !self.searchQuery.isEmpty {
      self.search()
    }
  }

  /// A page of what's saved from before what's shown, as it's scrolled back to.
  private func loadOlder() {
    guard self.hasOlder, !self.isLoadingOlder, let key = self.key, let oldest = self.messages.first else {
      return
    }
    self.isLoadingOlder = true
    Task {
      // One more, for the oldest that's here, which comes again.
      let entries = await ChatStore.shared.loadPage(for: key, through: oldest.date, count: HotlineState.chatPageSize + 1)
      self.isLoadingOlder = false
      guard self.messages.first?.id == oldest.id else {
        return
      }
      // Without the lines that are here already, from the same moment as the oldest.
      let here = Set(self.messages.prefix { $0.date <= oldest.date }.map(\.id))
      let older = entries.compactMap(ChatMessage.init(entry:)).filter { !here.contains($0.id) }
      if older.isEmpty {
        self.hasOlder = false
      }
      else {
        self.messages.insert(contentsOf: older, at: 0)
      }
    }
  }

  private func search() {
    guard let key = self.key else {
      return
    }
    let search = ChatSearch(self.searchQuery)
    let query = self.searchQuery
    let links = self.linkIndex
    self.searchTask = Task {
      let found = await search.savedResults(for: key, links: links, showsConnections: Prefs.shared.showJoinLeaveMessages)
      guard !Task.isCancelled, self.searchQuery == query else {
        return
      }
      self.searchResults = found.messages
      self.searchHasMore = found.more
      self.debouncedQuery = query
    }
  }

  /// More of what a search finds, from before what it's found, as its results are scrolled back.
  private func searchMore() {
    guard self.searchHasMore, !self.isSearchingMore, let key = self.key else {
      return
    }
    let query = self.debouncedQuery
    let results = self.searchResults
    let links = self.linkIndex
    self.isSearchingMore = true
    Task {
      let found = await ChatSearch(query).savedResults(for: key, before: results, links: links, showsConnections: Prefs.shared.showJoinLeaveMessages)
      self.isSearchingMore = false
      guard self.debouncedQuery == query, self.searchResults.first?.id == results.first?.id else {
        return
      }
      self.searchResults = found.messages
      self.searchHasMore = found.more
    }
  }

  /// After the history is cleared in the settings.
  private func clear() {
    self.messages = []
    self.searchResults = []
    self.savedCount = 0
    self.isLoaded = true
  }

  /// Links to Hotline servers connect to them, in a window of their own, and anything else opens
  /// in its app.
  private func open(_ url: URL) {
    if url.scheme?.lowercased() == "hotline", let server = Server(url: url) {
      AppState.shared.pendingServerOpen = server
    }
    else {
      NSWorkspace.shared.open(url)
    }
  }

  /// What can be done with a file or folder a message links to, without being connected: connect
  /// to its server, or copy the link.
  private func fileLinkMenu(for url: URL) -> NSMenu? {
    guard let server = Server(url: url) else {
      return nil
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(ChatMenuItem("Connect to \(server.displayAddress)", systemImage: "network") {
      self.open(url)
    })
    menu.addItem(.separator())
    menu.addItem(ChatMenuItem("Copy Link", systemImage: "link") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
    })
    return menu
  }
}

/// What's saved changing under the window: all of it, or the server's, cleared, or what's older
/// than it's kept for deleted.
private struct HistoryChanges: ViewModifier {
  let key: ChatStore.SessionKey?
  let cleared: () -> Void
  let pruned: () -> Void

  func body(content: Content) -> some View {
    content
      .onReceive(NotificationCenter.default.publisher(for: ChatStore.historyClearedNotification)) { _ in
        self.cleared()
      }
      .onReceive(NotificationCenter.default.publisher(for: ChatStore.historyPrunedNotification)) { _ in
        self.pruned()
      }
      .onReceive(NotificationCenter.default.publisher(for: ChatStore.serverHistoryClearedNotification)) { notification in
        if notification.userInfo?["address"] as? String == self.key?.address,
           notification.userInfo?["port"] as? Int == self.key?.port {
          self.cleared()
        }
      }
  }
}
