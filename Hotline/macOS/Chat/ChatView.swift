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

  var displayedMessages: [ChatMessage] {
    self.debouncedQuery.isEmpty ? self.model.chat : self.searchResults
  }

  private var effectiveWatchWords: [HighlightWord] {
    var words = Prefs.shared.watchWords
    if Prefs.shared.highlightMentions {
      let username = Prefs.shared.username
      if !username.isEmpty {
        words.insert(HighlightWord(word: username, color: Prefs.shared.mentionHighlightColor), at: 0)
      }
    }
    return words
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
        watchWords: self.effectiveWatchWords,
        isFiltered: !self.debouncedQuery.isEmpty,
        cachedText: self.model.chatRenderedText,
        cachedCount: self.model.chatRenderedCount,
        onCacheUpdate: { text, count in
          self.model.chatRenderedText = text
          self.model.chatRenderedCount = count
        },
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
            return "Show Message Board"
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
        previewsImages: Prefs.shared.previewChatImages
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea(edges: .top)
      .modifier(SoftTopScrollEdge())
      .onChange(of: self.model.chat.count) {
        if !self.searchQuery.isEmpty {
          self.performSearch()
        }
        self.model.markPublicChatAsRead()
      }
      .onAppear {
        self.model.markPublicChatAsRead()
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 0) {
          Divider()
          self.inputBar
        }
      }
      .sheet(item: self.$fileDetails) { details in
        FileDetailsSheet(details: details)
      }
      .searchable(text: self.$searchQuery, isPresented: self.$isSearching, placement: .toolbar, prompt: "Search")
      .background(Button("", action: { self.isSearching = true }).keyboardShortcut("f").hidden())
      .toolbar {
        if self.model.access?.contains(.canBroadcast) == true {
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
    .background {
      if #available(macOS 26.0, *) {
        Color(.windowBackgroundColor)
          .ignoresSafeArea()
      } else {
        Color(nsColor: .textBackgroundColor)
          .ignoresSafeArea()
      }
    }
  }
  
  private var inputBar: some View {
    @Bindable var bindModel = self.model
    return ChatInputField(
      text: $bindModel.chatInput,
      height: self.$inputHeight,
      namesToComplete: { self.namesToComplete() },
      onSubmit: { announce in
        let message = self.model.chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
          Task {
            try? await self.model.sendChat(message, announce: announce)
          }
        }
        self.model.chatInput = ""
      }
    )
    .frame(maxWidth: .infinity)
    .frame(height: self.inputHeight)
  }
  
  /// The names Tab completes in the input: the people here, the ones who spoke last first, then
  /// the rest by name, and not you.
  private func namesToComplete() -> [String] {
    var here = Set(self.model.users.map(\.name))
    here.remove(Prefs.shared.username)
    var names: [String] = []
    for message in self.model.chat.reversed() where names.count < here.count {
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
          if let info = try await self.model.getClientInfoText(id: user.id) {
            self.serverState.userInfo = info
          }
        }
      })
    }
    menu.addItem(ChatMenuItem("Send Message...", systemImage: "square.and.pencil", isEnabled: self.model.access?.contains(.canSendMessages) == true && !user.refusesPrivateMessages) {
      self.serverState.composeMessageUser = user
    })
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
    self.searchResults = self.model.searchChat { search.matches($0, links: links) }
    self.debouncedQuery = self.searchQuery
  }
}

/// What a search of the chat finds: messages with some text in them, and for "links" or "files",
/// every message with a link, or a link to a file or folder on a Hotline server, too.
private struct ChatSearch {
  let text: String
  /// The links that bring a message into the results whatever its text.
  let kinds: ChatLinkIndex.Kinds

  init(_ query: String) {
    self.text = query
    switch query.trimmingCharacters(in: .whitespaces).lowercased() {
    case "links":
      self.kinds = .link
    case "files":
      self.kinds = .file
    default:
      self.kinds = []
    }
  }

  func matches(_ message: ChatMessage, links: ChatLinkIndex) -> Bool {
    if message.searchText.range(of: self.text, options: [.caseInsensitive, .literal]).location != NSNotFound {
      return true
    }
    return !self.kinds.isEmpty && !links.kinds(in: message).isDisjoint(with: self.kinds)
  }
}

/// Which messages have links, and links to files, worked out once for each, since finding links
/// in a long chat takes a moment.
private final class ChatLinkIndex {
  struct Kinds: OptionSet {
    let rawValue: UInt8
    static let link = Kinds(rawValue: 1 << 0)
    static let file = Kinds(rawValue: 1 << 1)
  }

  private var known: [UUID: Kinds] = [:]

  func kinds(in message: ChatMessage) -> Kinds {
    if let kinds = self.known[message.id] {
      return kinds
    }
    var kinds: Kinds = []
    for url in ChatMessageRenderer.links(in: message.text) {
      kinds.insert(.link)
      if ChatMessageRenderer.fileName(ofHotlineLink: url) != nil {
        kinds.insert(.file)
        break
      }
    }
    self.known[message.id] = kinds
    return kinds
  }
}

/// A menu item that does what it's given.
private final class ChatMenuItem: NSMenuItem {
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

private struct SoftTopScrollEdge: ViewModifier {
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
