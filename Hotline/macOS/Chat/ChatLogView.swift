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
  @State private var isSearching = false
  @State private var searchTask: Task<Void, Never>?
  @State private var linkIndex = ChatLinkIndex()

  var body: some View {
    Group {
      if self.isLoaded && self.messages.isEmpty {
        ContentUnavailableView("No Chat History", systemImage: "bubble.left.and.bubble.right")
      }
      else {
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
          previewsImages: Prefs.shared.previewChatImages
        )
        .ignoresSafeArea(edges: .top)
        .modifier(SoftTopScrollEdge())
      }
    }
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
      self.searchTask?.cancel()
      if self.searchQuery.isEmpty {
        self.debouncedQuery = ""
        self.searchResults = []
      }
      else {
        self.searchTask = Task {
          try? await Task.sleep(for: .milliseconds(50))
          guard !Task.isCancelled else { return }
          self.search()
        }
      }
    }
    .task(id: self.key) {
      await self.load()
    }
    .onReceive(NotificationCenter.default.publisher(for: ChatStore.historyClearedNotification)) { _ in
      self.clear()
    }
    .onReceive(NotificationCenter.default.publisher(for: ChatStore.serverHistoryClearedNotification)) { notification in
      if notification.userInfo?["address"] as? String == self.key?.address,
         notification.userInfo?["port"] as? Int == self.key?.port {
        self.clear()
      }
    }
  }

  /// The server's address, under its name, and how many messages there are, or how many a search
  /// found.
  private var subtitle: String {
    let shown = self.debouncedQuery.isEmpty ? self.messages : self.searchResults
    let count = shown.filter { $0.type != .signOut }.count
    let messages = count == 1 ? "1 message" : "\(count.formatted()) messages"
    guard self.serverName != nil, let address = self.key?.identifier else {
      return messages
    }
    return "\(address) · \(messages)"
  }

  private func load() async {
    guard let key = self.key else {
      return
    }
    let result = await ChatStore.shared.loadHistory(for: key)
    let messages = result.entries.compactMap(ChatMessage.init(entry:))
    // A history of only disconnects has nothing in it to read.
    self.messages = messages.contains { $0.type != .signOut } ? messages : []
    self.serverName = result.metadata?.serverName
    self.isLoaded = true
    if !self.searchQuery.isEmpty {
      self.search()
    }
  }

  private func search() {
    let search = ChatSearch(self.searchQuery)
    let links = self.linkIndex
    self.searchResults = self.messages.searched { search.matches($0, links: links) }
    self.debouncedQuery = self.searchQuery
  }

  /// After the history is cleared in the settings.
  private func clear() {
    self.messages = []
    self.searchResults = []
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
