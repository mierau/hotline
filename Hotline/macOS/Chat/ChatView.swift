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
        showsConnections: self.chatID != nil || Prefs.shared.showJoinLeaveMessages
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea(edges: .top)
      .modifier(SoftTopScrollEdge())
      .onChange(of: self.messages.count) {
        if !self.searchQuery.isEmpty {
          self.performSearch()
        }
        self.markAsRead()
      }
      .onAppear {
        self.markAsRead()
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
    // The public chat with its history, or what's been said in the private one.
    if self.chatID == nil {
      let showsConnections = Prefs.shared.showJoinLeaveMessages
      self.searchResults = self.model.searchChat { (showsConnections || !$0.isConnection) && search.matches($0, links: links) }
    }
    else {
      self.searchResults = self.messages.searched { search.matches($0, links: links) }
    }
    self.debouncedQuery = self.searchQuery
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
