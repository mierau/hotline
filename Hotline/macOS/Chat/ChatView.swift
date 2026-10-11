import SwiftUI
import Kingfisher

enum FocusedField: Int, Hashable {
  case chatInput
}

struct ChatView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.dismiss) var dismiss
  @Environment(\.openWindow) private var openWindow
  @Bindable var serverState: ServerState
  /// The private chat this is, or nil for the server's public chat.
  var chatID: UInt32? = nil
  
  @State private var searchQuery: String = ""
  @State private var debouncedQuery: String = ""
  @State private var searchResults: [ChatMessage] = []
  /// Whether a search of what's saved might find more, from before what it's found.
  @State private var searchHasMore = false
  @State private var isSearchingMore = false
  /// Goes to the newest message each time it changes.
  @State private var scrollToNewest = 0
  @State private var isSearching: Bool = false
  @State private var searchTask: Task<Void, Never>?
  @State private var stableBannerFileURL: URL?
  @State private var stableBannerIsAnimated: Bool = false
  @State private var inputHeight: CGFloat = ChatInputField.defaultHeight
  @State private var fileDetails: FileDetails?
  @State private var linkIndex = ChatLinkIndex()

  /// The private chat this is, while you're in it.
  private var privateChat: PrivateChat? {
    self.chatID.flatMap { self.model.privateChat($0) }
  }

  /// What's been said here, in the public chat or the private one.
  private var messages: [ChatMessage] {
    self.chatID == nil ? self.model.chat : self.privateChat?.messages ?? []
  }

  var displayedMessages: [ChatMessage] {
    self.debouncedQuery.isEmpty ? self.messages : self.searchResults
  }

  private var bannerView: some View {
    ZStack {
      if self.stableBannerIsAnimated {
        KFAnimatedImage
          .url(self.stableBannerFileURL)
          .cacheMemoryOnly()
          .cacheOriginalImage()
          .scaledToFill()
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .id("animated banner \(self.stableBannerFileURL?.absoluteString ?? "")")
      }
      else if self.stableBannerFileURL != nil {
        KFImage
          .url(self.stableBannerFileURL)
          .resizable()
          .interpolation(.high)
          .cacheMemoryOnly()
          .cacheOriginalImage()
          .scaledToFill()
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .id("static banner \(self.stableBannerFileURL?.absoluteString ?? "")")
      }
    }
    .frame(maxWidth: 468.0, minHeight: 60, maxHeight: 60)
    .clipped()
  }
  
  var body: some View {
    @Bindable var bindModel = self.model
    
    NavigationStack {
      // MARK: Chat Text View
      ChatTranscriptView(
        messages: self.displayedMessages,
        searchQuery: self.debouncedQuery,
        watchWords: HighlightWord.chatWords,
        isFiltered: !self.debouncedQuery.isEmpty,
        // The public chat's text, which is long, is kept for when it's back. A private chat's
        // is short.
        cachedText: self.chatID == nil ? self.model.chatRenderedText : nil,
        cachedCount: self.chatID == nil ? self.model.chatRenderedCount : 0,
        onCacheUpdate: self.chatID == nil ? { text, count in
          self.model.chatRenderedText = text
          self.model.chatRenderedCount = count
        } : nil,
        openURL: { url in
          self.open(url)
        },
        describeHotlineLink: { url in
          // As openURL handles them.
          guard let linkServer = Server(url: url) else {
            return nil
          }
          guard let currentServer = self.model.server,
                linkServer.address == currentServer.address && linkServer.port == currentServer.port else {
            return "Connect to \(linkServer.displayAddress)"
          }
          switch linkServer.initialSection {
          case .files:
            return linkServer.initialFilePath?.last.map { "Show “\($0)” in Files" } ?? "Show Files"
          case .news:
            return "Show News"
          case .board:
            return url.fragment?.isEmpty == false ? "Show Post on Message Board" : "Show Message Board"
          default:
            return nil
          }
        },
        fileLinkMenu: { url in
          self.fileLinkMenu(for: url)
        },
        userMenu: { name, iconID in
          self.userMenu(name: name, iconID: iconID)
        },
        showsIcons: Prefs.shared.showChatIcons,
        previewsImages: Prefs.shared.previewChatImages,
        // A private chat's people coming and going are who's in it, so they're always shown.
        showsConnections: self.chatID != nil || Prefs.shared.showJoinLeaveMessages,
        // Older chat, or older results, as they're scrolled back to.
        onNearStart: self.chatID == nil ? {
          if self.debouncedQuery.isEmpty {
            Task {
              await self.model.loadOlderChat()
            }
          }
          else {
            self.searchMore()
          }
        } : nil,
        // Reading back through the chat, or at its newest again, rather than in search results.
        onAtBottomChange: self.chatID == nil ? { atBottom in
          guard self.debouncedQuery.isEmpty else {
            return
          }
          if atBottom {
            self.model.catchUpChat()
          }
          else {
            self.model.startReadingBack()
          }
        } : nil,
        scrollToNewest: self.scrollToNewest
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea(edges: .top)
      .modifier(SoftTopScrollEdge())
      .overlay(alignment: .bottom) {
        if self.chatID == nil, self.debouncedQuery.isEmpty, self.model.newWhileReadingBack > 0 {
          NewMessagesButton(count: self.model.newWhileReadingBack) {
            self.scrollToNewest += 1
          }
          .padding(.bottom, 12)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.easeOut(duration: 0.2), value: self.model.newWhileReadingBack > 0)
      .onChange(of: self.messages.count) {
        if !self.searchQuery.isEmpty {
          if self.searchesSaved {
            self.addNewResults()
          }
          else {
            self.performSearch()
          }
        }
        self.markAsRead()
      }
      .onAppear {
        self.markAsRead()
      }
      // Messages come in as usual while the chat isn't shown.
      .onDisappear {
        if self.chatID == nil {
          self.model.catchUpChat()
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 0) {
          Divider()
            .serverThemedDivider()
          self.inputBar
        }
      }
      .sheet(item: self.$fileDetails) { details in
        FileDetailsSheet(details: details)
      }
      .searchable(text: self.$searchQuery, isPresented: self.$isSearching, placement: .toolbar, prompt: "Search")
      .background(Button("", action: { self.isSearching = true }).keyboardShortcut("f").hidden())
      .navigationSubtitle(self.privateChat.map { self.model.title(of: $0) } ?? "")
      .toolbar {
        if let chatID = self.chatID {
          if self.model.access?.contains(.canCreateChat) == true {
            ToolbarItem(placement: .primaryAction) {
              Button {
                self.serverState.privateChatInvite = PrivateChatInvite(chatID: chatID)
              } label: {
                Label("Invite People", systemImage: "person.badge.plus")
              }
              .help("Invite People")
            }
          }
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("Change Subject...", systemImage: "character.cursor.ibeam") {
                self.serverState.privateChatSubjectID = chatID
              }
              Divider()
              Button("Leave Chat...", systemImage: "rectangle.portrait.and.arrow.right") {
                self.serverState.privateChatToLeave = chatID
              }
            } label: {
              Label("More", systemImage: "ellipsis")
            }
            .help("More")
          }
        }
        else if self.model.access?.contains(.canBroadcast) == true {
          ToolbarItem(placement: .primaryAction) {
            Button {
              self.serverState.broadcastShown = true
            } label: {
              Label("Broadcast Message", systemImage: "megaphone")
            }
            .help("Broadcast Message")
          }
        }
      }
      .onChange(of: self.searchQuery) {
        self.searchTask?.cancel()
        if self.searchQuery.isEmpty {
          self.debouncedQuery = ""
          self.searchResults = []
          self.searchHasMore = false
          // The chat comes back at its newest.
          if self.chatID == nil {
            self.model.catchUpChat()
          }
        } else {
          let delay: Int = 50
          self.searchTask = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self.performSearch()
          }
        }
      }
    }
    .onAppear {
      self.stableBannerFileURL = self.model.bannerFileURL
      self.stableBannerIsAnimated = self.model.bannerImageFormat == .gif
    }
    .onChange(of: self.model.bannerFileURL) { _, newValue in
      self.stableBannerFileURL = newValue
      self.stableBannerIsAnimated = self.model.bannerImageFormat == .gif
    }
    .serverBackground(.content)
  }
  
  private var inputBar: some View {
    let input = self.input
    return ChatInputField(
      text: input,
      height: self.$inputHeight,
      // Yours as the user list shows it, when the chat shows icons.
      iconID: Prefs.shared.showChatIcons ? self.model.ownIconID : nil,
      namesToComplete: { self.namesToComplete() },
      onSubmit: { announce in
        let message = input.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
          Task {
            if let chatID = self.chatID {
              try? await self.model.sendPrivateChat(message, chatID: chatID, announce: announce)
            }
            else {
              try? await self.model.sendChat(message, announce: announce)
            }
          }
        }
        input.wrappedValue = ""
      }
    )
    .frame(maxWidth: .infinity)
    .frame(height: self.inputHeight)
  }

  /// What you've typed and not sent, kept while you're elsewhere.
  private var input: Binding<String> {
    if let chatID = self.chatID {
      return Binding(
        get: { self.model.privateChatDrafts[chatID] ?? "" },
        set: { self.model.privateChatDrafts[chatID] = $0 }
      )
    }
    @Bindable var bindModel = self.model
    return $bindModel.chatInput
  }

  private func markAsRead() {
    if let chatID = self.chatID {
      self.model.markPrivateChatAsRead(chatID)
    }
    else {
      self.model.markPublicChatAsRead()
    }
  }
  
  /// The names Tab completes in the input: the people here, the ones who spoke last first, then
  /// the rest by name, and not you.
  private func namesToComplete() -> [String] {
    var here = Set((self.chatID == nil ? self.model.users : self.privateChat?.users ?? []).map(\.name))
    here.remove(Prefs.shared.username)
    var names: [String] = []
    for message in self.messages.reversed() where names.count < here.count {
      if let name = message.username, here.contains(name), !names.contains(name) {
        names.append(name)
      }
    }
    let rest = here.subtracting(names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return names + rest
  }

  /// Opens a link from the chat: hotline:// links go to that part of this server, or connect to
  /// another one, and anything else opens in its app.
  private func open(_ url: URL) {
    guard url.scheme?.lowercased() == "hotline", let linkServer = Server(url: url) else {
      NSWorkspace.shared.open(url)
      return
    }
    if self.isThisServer(linkServer) {
      if let section = linkServer.initialSection {
        self.serverState.selection = section
        if section == .files, let filePath = linkServer.initialFilePath {
          self.serverState.fileNavigationPath = filePath
        }
        // A link to a post, like the one on the line saying it was posted.
        if section == .board, let post = url.fragment, !post.isEmpty {
          self.model.boardPostToReveal = post
        }
      }
    }
    else {
      // Through AppState, so the app opens it in a window of its own rather than this one.
      AppState.shared.pendingServerOpen = linkServer
    }
  }

  private func isThisServer(_ server: Server) -> Bool {
    guard let currentServer = self.model.server else {
      return false
    }
    return server.address == currentServer.address && server.port == currentServer.port
  }

  /// What can be done with a file or folder a message links to. On this server, what the Files
  /// list offers for it, short of changing it: download it, look at it, get its info, or show it
  /// in Files. On another, connect to that server. Either way, copy the link.
  private func fileLinkMenu(for url: URL) -> NSMenu? {
    guard let linkServer = Server(url: url), let path = linkServer.initialFilePath, let name = path.last else {
      return nil
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    if self.isThisServer(linkServer) {
      let file = FileInfo(linkedName: name, path: path, isFolder: url.hasDirectoryPath)
      let actions = FileActions(model: self.model, openWindow: self.openWindow)
      menu.addItem(ChatMenuItem("Download", systemImage: "arrow.down", isEnabled: self.model.access?.contains(.canDownloadFiles) == true) {
        actions.downloadFile(file)
      })
      if !file.isFolder {
        menu.addItem(ChatMenuItem("Quick Look", systemImage: "eye", isEnabled: file.isPreviewable) {
          actions.previewFile(file)
        })
      }
      menu.addItem(ChatMenuItem("Get Info", systemImage: "info.circle") {
        Task {
          if let details = await actions.getFileInfo(file) {
            self.fileDetails = details
          }
        }
      })
      menu.addItem(ChatMenuItem("Show in Files", systemImage: "folder") {
        self.open(url)
      })
    }
    else {
      menu.addItem(ChatMenuItem("Connect to \(linkServer.displayAddress)", systemImage: "network") {
        self.open(url)
      })
    }
    menu.addItem(.separator())
    menu.addItem(ChatMenuItem("Copy Link", systemImage: "link") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
    })
    return menu
  }

  /// What can be done for whoever sent a message, from their name or icon: what the user list
  /// offers for them, while they're connected.
  private func userMenu(name: String, iconID: UInt?) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    // Names aren't accounts, so of more than one person with the name, the one with the same icon.
    let named = self.model.users.filter { $0.name == name }
    guard let user = named.first(where: { $0.iconID == iconID }) ?? named.first else {
      menu.addItem(ChatMenuItem("\(name) Isn’t Connected", isEnabled: false) {})
      return menu
    }
    if self.model.access?.contains(.canGetClientInfo) == true {
      menu.addItem(ChatMenuItem("Get Info", systemImage: "info.circle") {
        Task {
          if let info = try? await self.model.getClientInfoText(id: user.id) {
            self.serverState.userInfo = info
          }
        }
      })
    }
    menu.addItem(ChatMenuItem("Send Message...", systemImage: "square.and.pencil", isEnabled: self.model.access?.contains(.canSendMessages) == true && !user.refusesPrivateMessages) {
      self.serverState.composeMessageUser = user
    })
    // Asking them into a private chat, as the user list does: a new one, with them chosen, or one
    // you're in, right away.
    if self.model.access?.contains(.canCreateChat) == true && user.id != self.model.ownUserID {
      let newChat = { self.serverState.privateChatInvite = PrivateChatInvite(chatID: nil, chosen: [user.id]) }
      let chats = self.model.privateChats(toInvite: user.id)
      if chats.isEmpty {
        menu.addItem(ChatMenuItem("Invite to Private Chat...", systemImage: "bubble.left.and.bubble.right", isEnabled: !user.refusesPrivateChat, handler: newChat))
      }
      else {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(ChatMenuItem("New Private Chat...", handler: newChat))
        submenu.addItem(.separator())
        for chat in chats {
          submenu.addItem(ChatMenuItem(self.model.title(of: chat)) {
            Task {
              try? await self.model.inviteToPrivateChat(chat.id, userIDs: [user.id])
            }
          })
        }
        let item = NSMenuItem(title: "Invite to Private Chat", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil)
        item.isEnabled = !user.refusesPrivateChat
        item.submenu = submenu
        menu.addItem(item)
      }
    }
    if self.model.access?.contains(.canDisconnectUsers) == true {
      menu.addItem(.separator())
      menu.addItem(ChatMenuItem("Disconnect User", systemImage: "nosign") {
        self.serverState.disconnectUserTarget = user
      })
    }
    return menu
  }

  private func performSearch() {
    guard !self.searchQuery.isEmpty else {
      self.debouncedQuery = ""
      self.searchResults = []
      return
    }
    
    let search = ChatSearch(self.searchQuery)
    let links = self.linkIndex
    let showsConnections = Prefs.shared.showJoinLeaveMessages
    // All of the public chat that's saved, the newest first, and more as it's scrolled back.
    if self.searchesSaved, let key = self.model.chatSessionKey {
      let query = self.searchQuery
      self.searchTask = Task {
        let found = await search.savedResults(for: key, links: links, showsConnections: showsConnections)
        guard !Task.isCancelled, self.searchQuery == query else {
          return
        }
        self.searchResults = found.messages
        self.searchHasMore = found.more
        self.debouncedQuery = query
      }
      return
    }
    // The public chat as it is, when none of it's saved, or what's been said in the private one.
    if self.chatID == nil {
      self.searchResults = self.model.searchChat { (showsConnections || !$0.isConnection) && search.matches($0, links: links) }
    }
    else {
      self.searchResults = self.messages.searched { search.matches($0, links: links) }
    }
    self.searchHasMore = false
    self.debouncedQuery = self.searchQuery
  }

  /// Whether a search looks through all of the chat that's saved, rather than only what's here.
  private var searchesSaved: Bool {
    self.chatID == nil && Prefs.shared.chatHistoryRetention != .never && self.model.chatSessionKey != nil
  }

  /// More of what a search of what's saved finds, from before what it's found, as its results
  /// are scrolled back.
  private func searchMore() {
    guard self.searchHasMore, !self.isSearchingMore, self.searchesSaved, let key = self.model.chatSessionKey else {
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

  /// What a search of what's saved finds among the messages that come while it's shown, after
  /// what it's found, without starting it again, which would lose its place.
  private func addNewResults() {
    guard !self.debouncedQuery.isEmpty, let last = self.searchResults.last else {
      self.performSearch()
      return
    }
    let search = ChatSearch(self.debouncedQuery)
    let links = self.linkIndex
    let showsConnections = Prefs.shared.showJoinLeaveMessages
    let newer = self.messages.reversed().prefix { $0.date > last.date }.reversed().filter { message in
      (showsConnections || !message.isConnection) && search.matches(message, links: links)
    }
    if !newer.isEmpty {
      self.searchResults += newer
    }
  }
}

/// Says there are messages newer than what you're reading back through, and how many, and goes to
/// them.
private struct NewMessagesButton: View {
  let count: Int
  let action: () -> Void

  var body: some View {
    Button(action: self.action) {
      Label(self.count == 1 ? "1 New Message" : "\(self.count.formatted()) New Messages", systemImage: "arrow.down")
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .help("Show the Newest Messages")
  }
}

extension HighlightWord {
  /// The words chat highlights: the watch words, and your name, when mentions are highlighted.
  static var chatWords: [HighlightWord] {
    var words = Prefs.shared.watchWords
    if Prefs.shared.highlightMentions {
      let username = Prefs.shared.username
      if !username.isEmpty {
        words.insert(HighlightWord(word: username, color: Prefs.shared.mentionHighlightColor), at: 0)
      }
    }
    return words
  }
}

/// A menu item that does what it's given.
final class ChatMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(ChatMenuItem.choose), keyEquivalent: "")
    self.target = self
    self.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    self.isEnabled = isEnabled
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func choose() {
    self.handler()
  }
}

/// Text scrolling under the toolbar fades out, as it does in other apps.
struct SoftTopScrollEdge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      content
    }
  }
}

#Preview {
  ChatView(serverState: ServerState(selection: .chat))
    .environment(HotlineState())
}
