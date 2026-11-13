import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import SecurityInterface

struct ServerMenuItem: Identifiable, Hashable {
  let id: UUID
  let type: ServerNavigationType
  let name: String
  let image: String
  
  init(type: ServerNavigationType, name: String, image: String) {
    self.id = UUID()
    self.type = type
    self.name = name
    self.image = image
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
  
  static func == (lhs: ServerMenuItem, rhs: ServerMenuItem) -> Bool {
    switch lhs.type {
    case .user(let lhsUID):
      switch rhs.type {
      case .user(let rhsUID):
        return lhsUID == rhsUID
      default:
        break
      }
    default:
      break
    }
    return lhs.id == rhs.id
  }
}

/// Someone's icon, as Hotline's are, beside their name: in a slot as wide as most icons are, 16
/// points, with one that's wider, as some are, centered on it, out past its edges, and under what's
/// beside it, as the chat's icon column has them, so it doesn't push what's beside it along. The
/// generic one, for an icon this copy of Hotline doesn't have.
struct UserIconView: View {
  let iconID: Int

  var body: some View {
    Color.clear
      .frame(width: 16, height: 16)
      .overlay {
        if let icon = HotlineState.getClassicIcon(self.iconID) ?? NSImage(named: "User") {
          Image(nsImage: icon)
            .fixedSize()
        }
      }
      .accessibilityHidden(true)
      // Under what's beside it, where it's wider than its slot.
      .zIndex(-1)
  }
}

struct ListItemView: View {
  @Environment(\.controlActiveState) private var controlActiveState
  
  let icon: String?
  let title: String
  /// How many unread there are, shown at its end, when there are any.
  var count: Int = 0
  
  var body: some View {
    HStack(spacing: 5) {
      if let i = icon {
        Image(i)
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
      
      Text(title)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer()
      if self.count > 0 {
        ServerUnreadCount(count: self.count)
          .padding(.leading, 8)
      }
    }
  }
}

/// A button on a sidebar row, like the Chat row's for a private chat: its symbol, flat, and with the
/// pointer over it, a circle of glass, which goes flat again once it's gone. Before macOS 26, with
/// no glass, a circle in the row's text color, which darkens when it's pressed.
struct SidebarRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    SidebarRowButton(configuration: configuration)
  }

  private struct SidebarRowButton: View {
    let configuration: Configuration

    @State private var hovered: Bool = false

    /// The circle, roomy around the symbol, and how much of it reaches past the space the button
    /// takes up in its row, so the row's no taller for it.
    private static let size: CGFloat = 28
    private static let overhang: CGFloat = 4

    var body: some View {
      let label = self.configuration.label
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .onHover { hovered in
          self.hovered = hovered
        }

      Group {
        if #available(macOS 26.0, *) {
          label
            .glassEffect(self.hovered ? .regular.interactive() : .identity, in: .circle)
            .animation(.easeOut(duration: 0.15), value: self.hovered)
        }
        else {
          label
            .background {
              Circle()
                .fill(.primary.opacity(self.configuration.isPressed ? 0.2 : self.hovered ? 0.1 : 0))
            }
            .animation(.easeOut(duration: 0.12), value: self.hovered)
        }
      }
      .padding(-Self.overhang)
    }
  }
}

extension FocusedValues {
  @Entry var activeHotlineModel: HotlineState?
  @Entry var activeServerState: ServerState?
  /// Whether the server in the window in front is in your bookmarks already.
  @Entry var activeServerIsBookmarked: Bool?
}

/// Says whether a server's in your bookmarks, by its address and port, for the Server menu, for the
/// window it's in.
private struct ServerBookmarkedReporter: View {
  let server: Server?
  @Query private var bookmarks: [Bookmark]

  var body: some View {
    Color.clear
      .focusedSceneValue(\.activeServerIsBookmarked, self.isBookmarked)
  }

  private var isBookmarked: Bool {
    guard let server = self.server else {
      return false
    }
    return self.bookmarks.contains {
      $0.type == .server && $0.address.caseInsensitiveCompare(server.address) == .orderedSame && $0.port == server.port
    }
  }
}

struct ServerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext
  
  @Binding var server: Server

  @State private var model: HotlineState = HotlineState()
  @State private var state: ServerState = ServerState(selection: .chat)
  @State private var connectAddress: String = ""
  @State private var connectLogin: String = ""
  @State private var connectPassword: String = ""
  @State private var connectionDisplayed: Bool = false
  @State private var connectTask: Task<Void, Never>? = nil
  /// Whether how the connection's encrypted shows, from the lock on the server's globe.
  @State private var encryptionShown: Bool = false
  /// Whether the pointer's over the Chat row, which shows a button for a private chat.
  @State private var chatRowHovered: Bool = false
  /// The private chats with who's in them folded away, and the one the pointer's over, which shows
  /// a button to leave it.
  @State private var foldedPrivateChats: Set<UInt32> = []
  @State private var hoveredPrivateChat: UInt32? = nil
  /// A private chat's new subject, as it's written, and the chat.
  @State private var privateChatSubject: String = ""
  @State private var privateChatSubjectID: UInt32? = nil
//  @State private var accountsShown: Bool = false
  
  static var menuItems: [ServerMenuItem] = [
    ServerMenuItem(type: .chat, name: "Chat", image: "Section Chat"),
    ServerMenuItem(type: .board, name: "Board", image: "Section Board"),
    ServerMenuItem(type: .news, name: "News", image: "Section News"),
    ServerMenuItem(type: .files, name: "Files", image: "Section Files"),
//    ServerMenuItem(type: .accounts, name: "Accounts", image: "Section Users"),
  ]
  
  static var classicMenuItems: [ServerMenuItem] = [
    ServerMenuItem(type: .chat, name: "Chat", image: "Section Chat"),
    ServerMenuItem(type: .board, name: "Board", image: "Section Board"),
    ServerMenuItem(type: .files, name: "Files", image: "Section Files"),
  ]
  
  var body: some View {
    Group {
      if self.model.status == .disconnected || self.model.status.isLoggingIn {
        VStack(alignment: .center) {
          Spacer()
          self.connectForm
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .serverBackground(.connectForm)
        // In the colors of the server that's typed or chosen, from its banner, when there's one from
        // an earlier visit, as the banner is, and as the server's window will be.
        .serverTheme(self.themeColors, window: self.state.window)
        .presentedWindowToolbarStyle(.unified(showsTitle: false))
        // The gray, or the theme's color, all the way up, with nothing in the toolbar to set apart.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // The form, whether or not it was connected before, and while connecting, the server.
        .navigationTitle(self.model.status == .disconnected || self.model.serverTitle.isBlank ? "Connect" : self.model.serverTitle)
        .sheet(isPresented: Binding(
          get: { self.model.agreementText != nil },
          set: { if !$0 { self.model.agreementText = nil } }
        )) {
          ServerAgreementSheet()
            .environment(self.model)
            .presentationSizing(.fitted)
        }
      }
      else if self.model.status == .loggedIn {
        self.serverView
          .environment(self.model)
          .onChange(of: self.model.pendingNavigation?.section) { _, _ in
            if let nav = self.model.pendingNavigation {
              self.model.pendingNavigation = nil
              self.state.selection = nav.section
              if nav.section == .files, let filePath = nav.filePath {
                self.state.fileNavigationPath = filePath
              }
            }
          }
          .onChange(of: Prefs.shared.userIconID) {
            Task { try? await self.model.sendUserPreferences() }
          }
          .onChange(of: Prefs.shared.username) {
            Task { try? await self.model.sendUserPreferences() }
          }
          // Changed in Settings, changed here too, over what the Server menu set for this window.
          .onChange(of: Prefs.shared.refusePrivateMessages) { _, refuse in
            self.model.setOptions(refusePrivateMessages: refuse)
          }
          .onChange(of: Prefs.shared.refusePrivateChat) { _, refuse in
            self.model.setOptions(refusePrivateChat: refuse)
          }
          .onChange(of: Prefs.shared.enableAutomaticMessage) { _, on in
            self.model.setOptions(automaticResponseOn: on)
          }
          .onChange(of: Prefs.shared.automaticMessage) { _, response in
            self.model.setOptions(automaticResponse: response)
          }
          .sheet(isPresented: Binding(
            get: { self.model.agreementText != nil },
            set: { if !$0 { self.model.agreementText = nil } }
          )) {
            ServerAgreementSheet()
              .environment(self.model)
              .presentationSizing(.fitted)
          }
          // As tall as what's in it, as that changes, as the message's bubble grows with it, which
          // fitted sizing doesn't do, as it fits what's in it once, as it opens.
          .sheet(isPresented: self.$state.broadcastShown) {
            BroadcastMessageSheet()
              .environment(self.model)
          }
          .sheet(isPresented: self.$state.accountsShown) {
            AccountManagerView()
              .environment(self.model)
              .frame(width: 400, height: 450)
              .presentationSizing(.fitted)
          }
          .sheet(isPresented: self.$state.automaticResponseShown) {
            AutomaticResponseSheet()
              .environment(self.model)
              .presentationSizing(.fitted)
          }
          .sheet(isPresented: self.$state.addBookmarkShown) {
            // Filled in with the server as you're connected to it, to change before it's kept.
            if let server = self.model.server {
              let title = self.model.serverTitle
              ServerBookmarkSheet(
                name: title.isEmpty ? server.name ?? server.address : title,
                address: server.port == HotlinePorts.DefaultServerPort ? server.address : "\(server.address):\(server.port)",
                login: server.login,
                password: server.password,
                // Encrypted as it's connected, if it is.
                tlsPort: self.model.secureConnection?.port
              )
            }
          }
      }
    }
    // Something in the toolbar in every state, so the window's title bar is the same height from
    // the connect form to the server: the server's globe once it's connected, and before that, a
    // place kept on the right with nothing in it.
    .toolbar {
      if self.model.status == .loggedIn {
        if #available(macOS 26.0, *) {
          ToolbarItem(placement: .navigation) {
            self.serverIcon
          }
          .sharedBackgroundVisibility(.hidden)
        }
        else {
          ToolbarItem(placement: .navigation) {
            self.serverIcon
          }
        }
      }
      else {
        if #available(macOS 26.0, *) {
          ToolbarItem(placement: .primaryAction) {
            self.toolbarPlaceholder
          }
          .sharedBackgroundVisibility(.hidden)
        }
        else {
          ToolbarItem(placement: .primaryAction) {
            self.toolbarPlaceholder
          }
        }
      }
    }
    .onDisappear {
      AppState.shared.serverWindowClosed(state: self.state)

      // disconnect() only handles a finished connection, so also stop one still in progress.
      self.connectTask?.cancel()
      self.connectTask = nil
      Task {
        await self.model.disconnect()
      }
    }
    .onChange(of: self.model.status) { old, new in
      self.rememberServer()
      // Leaving it is the last time you were on it.
      if old == .loggedIn && new != .loggedIn {
        Prefs.shared.rememberServer(address: self.server.address, port: self.server.port)
        // There's nothing left to lose, so there's no disconnect to confirm.
        self.state.disconnectToConfirm = nil
      }
    }
    .onChange(of: self.model.serverTitle) {
      self.state.serverName = self.model.serverTitle
      self.rememberServer()
    }
    .onChange(of: AppState.shared.pendingLink) { _, _ in
      self.consumePendingLink()
    }
    .onChange(of: self.controlActiveState) { _, newValue in
      // When openWindow brings this window forward, check for pending
      // links. More reliable than onChange across window scenes.
      if newValue == .key {
        self.consumePendingLink()
      }
    }
    .onAppear {
      self.syncFieldsFromServer()

      // Connect to server automatically unless the option key is held down.
      if !NSEvent.modifierFlags.contains(.option) {
        self.connectToServer()
      }
      else {
        self.model.previewBanner(for: self.server)
      }
    }
    .onChange(of: self.server) {
      // During window restoration, the binding may update after the view
      // is created with the defaultValue. Sync once when the real value arrives.
      if !self.connectionDisplayed && !self.server.address.isEmpty {
        self.syncFieldsFromServer()
        self.connectionDisplayed = true
      }
      // The banner follows the server as it's typed or chosen.
      self.model.previewBanner(for: self.server)
    }
    .alert("Something Went Wrong", isPresented: self.$model.errorDisplayed) {
      Button("OK") {}
    } message: {
      if let message = self.model.errorMessage,
         !message.isBlank {
        Text(message)
      }
    }
    // A server that has to be connected to securely, which couldn't be now, or had another
    // certificate, which is up to you, rather than connecting without, or trusting it, unasked.
    .modifier(EncryptionProblemAlerts(
      problem: self.$model.encryptionProblem,
      serverName: self.server.name ?? self.server.address,
      connectAnyway: { stopRequiring in
        if stopRequiring {
          self.stopRequiringSecureConnection()
        }
        self.connectToServer(withoutEncryption: true)
      },
      trust: { certificate, port in
        ServerTrust.shared.trust(certificate, address: self.server.address, port: self.server.port, tlsPort: port)
        self.connectToServer()
      }
    ))
    .alert("Disconnected", isPresented: Binding(
      get: { self.model.disconnectMessage != nil },
      set: { if !$0 { self.model.disconnectMessage = nil } }
    )) {
      Button("OK") {
        self.model.disconnectMessage = nil
      }
    } message: {
      if let message = self.model.disconnectMessage {
        Text(message)
      }
    }
    // Disconnecting or closing the window, when that would lose something. Neither button is
    // red, as it's what was chosen.
    .alert(
      self.disconnectConfirmationTitle,
      isPresented: Binding(
        get: { self.state.disconnectToConfirm != nil },
        set: { if !$0 { self.state.disconnectToConfirm = nil } }
      ),
      presenting: self.state.disconnectToConfirm
    ) { confirmation in
      switch confirmation.action {
      case .disconnect:
        Button("Disconnect") {
          Task {
            await self.model.disconnect()
          }
        }
        .keyboardShortcut(.defaultAction)
      case .closeWindow:
        Button("Close") {
          // Closing it directly doesn't ask again.
          self.state.window?.close()
        }
        .keyboardShortcut(.defaultAction)
      }
      Button("Cancel", role: .cancel) {}
    } message: { confirmation in
      Text(confirmation.losses)
    }
    .focusedSceneValue(\.activeHotlineModel, model)
    .focusedSceneValue(\.activeServerState, state)
    .focusedSceneValue(\.focusedAppWindow, .server)
    // Whether it's in your bookmarks already, for the Server menu's Add Bookmark, from a view of
    // its own, so a change to the bookmarks doesn't go over this one again.
    .background {
      ServerBookmarkedReporter(server: self.model.server)
    }
    .background {
      NSWindowAccessor { window in
        // This also runs with nil as views leave the window, like when connecting replaces the
        // connect form, so only record a real window. It's weak, so it clears when the window closes.
        if let window {
          self.state.window = window

          // Closing the window disconnects, so it asks first when that would lose something.
          let model = self.model
          let state = self.state
          WindowCloseGuard.guardClosing(window) { [weak model, weak state] window in
            guard let model, let state, state.askBeforeDisconnecting(.closeWindow, from: model) else {
              return true
            }
            // A tab that isn't showing comes forward to ask.
            window.makeKeyAndOrderFront(nil)
            return false
          }
        }
      }
    }
  }
  
  private var connectForm: some View {
    ConnectView(
      address: self.$connectAddress,
      login: self.$connectLogin,
      password: self.$connectPassword,
      tlsPort: self.server.tlsRequired ? self.server.tlsPort ?? HotlinePorts.DefaultTLSPort : nil,
      isConnecting: self.model.status.isLoggingIn,
      status: self.connectionStatusToLabel(status: self.model.status),
      cancel: { self.cancelConnecting() }
    ) {
      self.connectToServer()
    }
    .focusSection()
    .onChange(of: self.connectAddress) { previous, _ in
      self.updateServerFromForm(previousAddress: previous)
    }
    .onChange(of: self.connectLogin) {
      self.updateServerFromForm()
    }
    .onChange(of: self.connectPassword) {
      self.updateServerFromForm()
    }
  }
  
  private var navigationList: some View {
    List(selection: $state.selection) {
      // Don't show news on older servers.
      ForEach(model.serverVersion < 151 ? ServerView.classicMenuItems : ServerView.menuItems) { menuItem in
        if menuItem.type == .chat {
          // A button to start a private chat, for those who can, over the row's end, in place of
          // its count.
          let startsChats = self.model.access?.contains(.canCreateChat) == true
          ListItemView(icon: menuItem.image, title: menuItem.name, count: startsChats && self.chatRowHovered ? 0 : model.unreadPublicChatCount).tag(menuItem.type)
            .overlay(alignment: .trailing) {
              if startsChats && self.chatRowHovered {
                Button {
                  self.state.privateChatInvite = PrivateChatInvite(chatID: nil)
                } label: {
                  // As big as the row's name, and its color, white on the selection, which a
                  // borderless button's accent color nearly is.
                  Image(systemName: "plus")
                    .imageScale(.large)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(SidebarRowButtonStyle())
                .help("New Private Chat")
                .padding(.trailing, 2)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
              }
            }
            // The button grows in with the pointer, and the count it takes the place of fades.
            .onHover { hovering in
              withAnimation(.easeOut(duration: 0.15)) {
                self.chatRowHovered = hovering
              }
            }
            .serverThemedRow(for: menuItem.type)

          // The private chats you're in, under the public one.
          ForEach(self.model.joinedPrivateChats) { chat in
            self.privateChatRow(chat)
          }
        }
//        else if menuItem.type == .board {
//          if self.model.access?.contains(.canReadMessageBoard) == true {
//            ListItemView(icon: menuItem.image, title: menuItem.name, unread: false).tag(menuItem.type)
//          }
//        }
//        else if menuItem.type == .accounts {
//          if model.access?.contains(.canOpenUsers) == true {
//            ListItemView(icon: menuItem.image, title: menuItem.name, unread: false).tag(menuItem.type)
//          }
//        }
        else if menuItem.type == .files {
          ListItemView(icon: menuItem.image, title: menuItem.name).tag(menuItem.type)
            .overlay(alignment: .trailing) {
              if case .searching(_, _) = model.fileSearchStatus {
                ProgressView()
                  .controlSize(.mini)
                  .padding(.trailing, 4)
              }
            }
            .serverThemedRow(for: menuItem.type)
        }
        else {
          ListItemView(icon: menuItem.image, title: menuItem.name, count: menuItem.type == .board ? model.unreadBoardPosts : 0).tag(menuItem.type)
            .serverThemedRow(for: menuItem.type)
        }
      }

      if model.transfers.count > 0 {
        Divider()
        
        self.transfersSection
      }
      
      if model.users.count > 0 {
        Divider()
        
        self.usersSection
      }
    }
    .onChange(of: state.selection) {
      switch(state.selection) {
      case .chat:
        model.markPublicChatAsRead()
      case .board:
        model.markBoardAsRead()
      case .user(let userID):
        model.markPrivateMessagesAsRead(userID: userID)
      default:
        break
      }
    }
  }
  
  var transfersSection: some View {
    ForEach(model.transfers) { transfer in
      ServerTransferRow(transfer: transfer)
    }
  }
  
  var usersSection: some View {
    ForEach(model.users) { user in
      let unread = self.model.unreadCount(from: user.id)
      HStack(spacing: 5) {
        // Fainter while they're idle, but not the count, since unread messages from them matter
        // whether they're there or not.
        HStack(spacing: 5) {
          UserIconView(iconID: Int(user.iconID))
            .padding(.horizontal, 2)

          Text(user.name)
            // Bolder with messages or an invitation from them you haven't seen, as the count beside
            // it shows.
            .fontWeight(unread > 0 ? .semibold : nil)
            .foregroundStyle(user.isAdmin ? AnyShapeStyle(.serverAdmin) : AnyShapeStyle(.primary))
        }
        .opacity(user.isIdle ? 0.5 : 1.0)

        Spacer()

        if unread > 0 {
          ServerUnreadCount(count: unread)
            .padding(.leading, 8)
        }
      }
      // A double click writes them a message, as Send Message does, when one can be sent to them,
      // and not to you. The click before it selects them, as one does, on its own.
      .contentShape(.rect)
      .simultaneousGesture(TapGesture(count: 2).onEnded {
        if user.id != self.model.ownUserID && self.model.access?.contains(.canSendMessages) == true && !user.refusesPrivateMessages {
          self.state.composeMessage = PrivateMessageCompose(userID: user.id, username: user.name)
        }
      })
      .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      .tag(ServerNavigationType.user(userID: user.id))
      .serverThemedRow(for: ServerNavigationType.user(userID: user.id))
      .contextMenu {
        self.userMenu(user)
      }
    }
  }

  /// What can be done for someone, from the user list or a private chat they're in.
  @ViewBuilder
  private func userMenu(_ user: User) -> some View {
    if self.model.access?.contains(.canGetClientInfo) == true {
      Button("Get Info", systemImage: "info.circle") {
        Task {
          if let info = try? await self.model.getClientInfoText(id: user.id) {
            self.state.userInfo = info
          }
        }
      }
    }

    Button("Send Message...", systemImage: "square.and.pencil") {
      self.state.composeMessage = PrivateMessageCompose(userID: user.id, username: user.name)
    }
    .disabled(self.model.access?.contains(.canSendMessages) != true || user.refusesPrivateMessages)

    if self.model.access?.contains(.canCreateChat) == true && user.id != self.model.ownUserID {
      self.privateChatInviteMenu(for: user)
    }

    if self.model.access?.contains(.canDisconnectUsers) == true {
      Divider()

      Button("Disconnect User", systemImage: "nosign", role: .destructive) {
        self.state.disconnectUserTarget = user
      }
    }
  }

  /// Asking someone into a private chat: a new one, with them chosen, for whoever else and what
  /// about, or one you're in, right away.
  @ViewBuilder
  private func privateChatInviteMenu(for user: User) -> some View {
    let chats = self.model.privateChats(toInvite: user.id)
    if chats.isEmpty {
      Button("Invite to Private Chat...", systemImage: "bubble.left.and.bubble.right") {
        self.state.privateChatInvite = PrivateChatInvite(chatID: nil, chosen: [user.id])
      }
      .disabled(user.refusesPrivateChat)
    }
    else {
      Menu("Invite to Private Chat", systemImage: "bubble.left.and.bubble.right") {
        Button("New Private Chat...") {
          self.state.privateChatInvite = PrivateChatInvite(chatID: nil, chosen: [user.id])
        }

        Divider()

        ForEach(chats) { chat in
          Button(self.model.title(of: chat)) {
            Task {
              try? await self.model.inviteToPrivateChat(chat.id, userIDs: [user.id])
            }
          }
        }
      }
      .disabled(user.refusesPrivateChat)
    }
  }

  /// A private chat you're in, under the public one, with who's in it under it, which can be folded
  /// away. With the pointer over it, a button in place of its count leaves it, once that's confirmed.
  @ViewBuilder
  private func privateChatRow(_ chat: PrivateChat) -> some View {
    let item = ServerNavigationType.privateChat(chatID: chat.id)
    let row = HStack(spacing: 5) {
      // The public chat's, for now.
      Image("Section Private Chat")
        .resizable()
        .scaledToFit()
        .frame(width: 20, height: 20)
        .opacity(self.controlActiveState == .inactive ? 0.5 : 1.0)

      Text(self.model.title(of: chat))
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer()

      if self.hoveredPrivateChat == chat.id {
        Button {
          self.state.privateChatToLeave = chat.id
        } label: {
          // In the row's text color, as the Chat row's button is.
          Image(systemName: "xmark")
            .fontWeight(.medium)
            .foregroundStyle(.primary)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .help("Leave Chat")
        .padding(.trailing, 2)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
      }
      else if chat.unreadCount > 0 {
        ServerUnreadCount(count: chat.unreadCount)
          .padding(.leading, 8)
      }
    }
    // As the Chat row's button does.
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.15)) {
        if hovering {
          self.hoveredPrivateChat = chat.id
        }
        else if self.hoveredPrivateChat == chat.id {
          self.hoveredPrivateChat = nil
        }
      }
    }
    .tag(item)
    .serverThemedRow(for: item)
    .contextMenu {
      self.privateChatMenu(chat)
    }

    DisclosureGroup(isExpanded: Binding(
      get: { !self.foldedPrivateChats.contains(chat.id) },
      set: { expanded in
        if expanded {
          self.foldedPrivateChats.remove(chat.id)
        }
        else {
          self.foldedPrivateChats.insert(chat.id)
        }
      }
    )) {
      ForEach(chat.users) { user in
        self.privateChatMemberRow(user)
      }
    } label: {
      row
    }
  }

  /// Someone in a private chat, as the user list has them, with its menu. They're not to be chosen,
  /// as the chat they're in is what's chosen.
  private func privateChatMemberRow(_ user: User) -> some View {
    HStack(spacing: 5) {
      UserIconView(iconID: Int(user.iconID))
        .padding(.horizontal, 2)

      Text(user.name)
        .lineLimit(1)
        .foregroundStyle(user.isAdmin ? AnyShapeStyle(.serverAdmin) : AnyShapeStyle(.primary))

      Spacer()
    }
    .opacity(user.isIdle ? 0.5 : 1.0)
    .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
    .contextMenu {
      self.userMenu(user)
    }
  }

  @ViewBuilder
  private func privateChatMenu(_ chat: PrivateChat) -> some View {
    if self.model.access?.contains(.canCreateChat) == true {
      Button("Invite People...", systemImage: "person.badge.plus") {
        self.state.privateChatInvite = PrivateChatInvite(chatID: chat.id)
      }
    }
    Button("Change Subject...", systemImage: "character.cursor.ibeam") {
      self.state.privateChatSubjectID = chat.id
    }

    Divider()

    Button("Leave Chat...", systemImage: "rectangle.portrait.and.arrow.right") {
      self.state.privateChatToLeave = chat.id
    }
  }
  
  var serverView: some View {
    NavigationSplitView(columnVisibility: self.$state.columnVisibility) {
      self.navigationList
        .serverThemedSidebar(selection: self.state.selection)
        .navigationSplitViewColumnWidth(200)
//        .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 400)
        .toolbar(removing: .sidebarToggle)
//        .toolbar {
//          if self.model.access?.contains(.canOpenUsers) == true {
//            ToolbarItem(placement: .primaryAction) {
//              Button {
//                self.state.accountsShown = true
//              } label: {
//                Label("Manage Accounts", systemImage: "gear")
//              }
//              .help("Manage Accounts")
//            }
//          }
//        }
    } detail: {
        switch state.selection {
        case .chat:
          ChatView(serverState: self.state)
        case .news:
          NewsView()
        case .board:
          MessageBoardView(serverState: self.state)
        case .files:
          FilesView(serverState: self.state)
        case .user(let userID):
          // Joining a private chat they invited you to goes to it.
          MessageView(userID: userID) { chatID in
            self.state.selection = .privateChat(chatID: chatID)
          }
          .id(userID)
        case .privateChat(let chatID):
          ChatView(serverState: self.state, chatID: chatID)
            .id(chatID)
        }
    }
    .serverTheme(self.themeColors, window: self.state.window)
    // Its pictures, from where they load by themselves, its server's own too.
    .environment(\.imageSources, ImagePreview.Sources(server: self.model.server?.address, anySite: Prefs.shared.imagePreviews == .anySite))
    .navigationTitle(self.model.serverTitle)
    .sheet(item: self.$state.composeMessage) { compose in
      ComposeMessageView(userID: compose.userID, username: compose.username)
        .environment(self.model)
    }
    .sheet(item: self.$state.userInfo) { info in
      UserClientInfoSheet(info: info)
    }
    .sheet(item: self.$state.privateChatInvite) { invite in
      PrivateChatInviteSheet(chatID: invite.chatID, chosen: invite.chosen) { chatID in
        self.state.selection = .privateChat(chatID: chatID)
      }
      .environment(self.model)
    }
    .alert(
      "Change Subject",
      isPresented: Binding(
        get: { self.state.privateChatSubjectID != nil },
        set: { if !$0 { self.state.privateChatSubjectID = nil } }
      )
    ) {
      TextField("Subject", text: self.$privateChatSubject)
      Button("Cancel", role: .cancel) {}
      Button("Change") {
        if let chatID = self.privateChatSubjectID {
          let subject = self.privateChatSubject.trimmingCharacters(in: .whitespacesAndNewlines)
          Task {
            try? await self.model.setPrivateChatSubject(subject, chatID: chatID)
          }
        }
      }
    } message: {
      Text("Everyone in the chat will see it.")
    }
    .alert(
      "Leave “\(self.state.privateChatToLeave.flatMap { self.model.privateChat($0) }.map { self.model.title(of: $0) } ?? "Private Chat")”?",
      isPresented: Binding(
        get: { self.state.privateChatToLeave != nil },
        set: { if !$0 { self.state.privateChatToLeave = nil } }
      )
    ) {
      Button("Leave", role: .destructive) {
        if let chatID = self.state.privateChatToLeave {
          Task {
            await self.model.leavePrivateChat(chatID)
          }
        }
      }
    } message: {
      Text("Private chats are not saved, so what has been said here will be forgotten.")
    }
    .onChange(of: self.state.privateChatSubjectID) { _, chatID in
      // The chat, and its subject as it is, to change, until it's asked about another.
      if let chatID {
        self.privateChatSubjectID = chatID
        self.privateChatSubject = self.model.privateChat(chatID)?.subject ?? ""
      }
    }
    .onChange(of: self.model.privateChats.map(\.id)) { _, chatIDs in
      // Once it's left or declined, back to the public chat.
      if case .privateChat(let chatID) = self.state.selection, !chatIDs.contains(chatID) {
        self.state.selection = .chat
      }
    }
    .alert(
      "Are you sure you want to disconnect \(self.state.disconnectUserTarget?.name ?? "this user")?",
      isPresented: Binding(
        get: { self.state.disconnectUserTarget != nil },
        set: { if !$0 { self.state.disconnectUserTarget = nil } }
      )
    ) {
      Button("Disconnect", role: .destructive) {
        if let user = self.state.disconnectUserTarget {
          Task {
            try? await self.model.disconnectUser(id: user.id, options: nil)
          }
        }
      }
    } message: {
      Text("They will be disconnected from the server, but may reconnect.")
    }
  }

  /// The server to connect to, from the form: its address, and a login and password typed with
  /// it, as in user:password@host, or else the ones in their own fields.
  ///
  /// A secure connection asked for by a hotlines:// link stays asked for while the address is the
  /// same server's, which the address shows without the hotlines://.
  ///
  /// - Parameter previousAddress: The address as it was before it changed, if it did.
  private func updateServerFromForm(previousAddress: String? = nil) {
    let typed = Server.parseServerAddress(self.connectAddress)
    // Another server than the one it was, so what was known of that one's TLS isn't this one's.
    if typed.host != self.server.address || typed.port != self.server.port {
      self.server.tlsPort = nil
      self.server.tlsRequired = false
    }
    // A secure connection, when it's asked for, as a hotlines:// address typed out does, and not
    // once the hotlines:// is taken off it.
    if let tlsPort = typed.tlsPort {
      self.server.tlsRequired = true
      self.server.tlsPort = tlsPort
    }
    else if let previousAddress, Server.parseServerAddress(previousAddress).tlsPort != nil {
      self.server.tlsRequired = false
      self.server.tlsPort = nil
    }
    self.server.address = typed.host
    self.server.port = typed.port
    if let login = typed.login {
      self.server.login = login
      self.server.password = typed.password ?? ""
    }
    else {
      self.server.login = self.connectLogin.trimmingCharacters(in: .whitespacesAndNewlines)
      self.server.password = self.connectPassword
    }
  }

  /// The server banner's colors, for the window's theme, on macOS 27 and later, when server themed
  /// colors are on, and the banner's colors could be read, and its background has a color, not white
  /// or a light gray, which wouldn't look like anything but the window's usual colors.
  private var themeColors: ColorArt? {
    guard #available(macOS 27, *), Prefs.shared.useServerThemedColors, let colors = self.model.bannerColors, !colors.hasPlainLightBackground else {
      return nil
    }
    return colors
  }

  /// The server's globe, with the lock on it while the connection is encrypted, which shows how in
  /// a click.
  @ViewBuilder
  private var serverIcon: some View {
    let icon = ServerIcon(name: "Server Large", isSecure: self.model.secureConnection != nil)
      .frame(width: 28)
      .opacity(self.controlActiveState == .inactive ? 0.4 : 1.0)

    if let connection = self.model.secureConnection {
      Button {
        self.encryptionShown.toggle()
      } label: {
        icon
      }
      .buttonStyle(.plain)
      .help("Secure Connection")
      .popover(isPresented: self.$encryptionShown, arrowEdge: .bottom) {
        EncryptedConnectionPopover(connection: connection, address: self.server.address)
      }
    }
    else {
      icon
        .accessibilityHidden(true)
    }
  }

  /// Nothing to see, but enough of something for the window to keep its toolbar.
  private var toolbarPlaceholder: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .accessibilityHidden(true)
  }

  // MARK: -


  private func consumePendingLink() {
    guard let pending = AppState.shared.pendingLink,
          pending.address == self.server.address && pending.port == self.server.port,
          let section = pending.initialSection,
          self.model.status == .loggedIn else {
      return
    }
    AppState.shared.pendingLink = nil
    self.state.selection = section
    if section == .files, let filePath = pending.initialFilePath {
      self.state.fileNavigationPath = filePath
    }
  }

  /// Puts the server first among the recent ones once it's logged in to, under the name it goes by,
  /// which can come a moment after.
  private func rememberServer() {
    guard self.model.status == .loggedIn else {
      return
    }
    Prefs.shared.rememberServer(address: self.server.address, port: self.server.port, name: self.model.serverTitle)
  }

  private func syncFieldsFromServer() {
    // Without the hotlines:// of one to connect to securely, which its globe shows instead.
    self.connectAddress = self.server.displayAddress
    self.connectLogin = self.server.login
    self.connectPassword = self.server.password
  }

  /// - Parameter withoutEncryption: Whether to connect without TLS this once, as you can choose to
  ///   when a server that's taken it before doesn't now.
  @MainActor func connectToServer(withoutEncryption: Bool = false) {
    guard !self.server.address.isEmpty else {
      return
    }

    // As its bookmark has it, if it's bookmarked, however it was typed or chosen.
    self.applyBookmarkedEncryption()

    // Set status here so it's immediate (not waiting to enter task).
    self.model.status = .connecting

    self.connectTask = Task { @MainActor in
      do {
        try await self.model.login(
          server: server,
          username: Prefs.shared.username,
          iconID: Prefs.shared.userIconID,
          withoutEncryption: withoutEncryption
        )
      } catch {
        print("ServerView: Login failed: \(error)")
      }
    }
  }

  /// Whether to connect to the server over TLS, and on which port, as its bookmark has it, for a
  /// server that's bookmarked: over TLS, if the bookmark's set to be, and otherwise as it would be
  /// if it weren't bookmarked.
  private func applyBookmarkedEncryption() {
    let bookmarks = (try? self.modelContext.fetch(FetchDescriptor<Bookmark>())) ?? []
    guard let bookmark = bookmarks.first(where: {
      $0.type == .server && $0.port == self.server.port && $0.address.caseInsensitiveCompare(self.server.address) == .orderedSame
    }) else {
      return
    }
    // Securely, if its bookmark's set to be, whatever was typed, and as typed otherwise.
    if let tlsPort = bookmark.tlsPort {
      self.server.tlsRequired = true
      self.server.tlsPort = tlsPort
    }
  }

  /// Stops requiring the server to be connected to securely, as you can choose to for one whose
  /// secure connection's gone: forgets it was connected to securely, and turns its bookmark's secure
  /// connection off, if it has one. A tracker that lists it with a TLS port still has it tried first.
  private func stopRequiringSecureConnection() {
    ServerTrust.shared.forget(address: self.server.address, port: self.server.port)
    let bookmarks = (try? self.modelContext.fetch(FetchDescriptor<Bookmark>())) ?? []
    for bookmark in bookmarks where bookmark.type == .server && bookmark.port == self.server.port && bookmark.address.caseInsensitiveCompare(self.server.address) == .orderedSame {
      bookmark.tlsPort = nil
    }
    self.server.tlsRequired = false
    self.server.tlsPort = nil
  }

  private func cancelConnecting() {
    self.connectTask?.cancel()
    self.connectTask = nil
    // Once connected, the server's agreement can still be waiting, so close the connection too.
    Task {
      await self.model.disconnect()
    }
  }

  /// The title for confirming a disconnect, from the Server menu or from closing the window.
  private var disconnectConfirmationTitle: String {
    let name = self.model.serverTitle.isBlank ? "the server" : self.model.serverTitle
    if self.state.disconnectToConfirm?.action == .closeWindow {
      return "Close and disconnect from \(name)?"
    }
    return "Disconnect from \(name)?"
  }

  private func connectionStatusToLabel(status: HotlineConnectionStatus) -> String {
    let n = server.name ?? server.address
    switch status {
    case .disconnected:
      return "Disconnected"
    case .connecting:
      return self.model.connectingSecurely ? "Connecting securely to \(n)…" : "Connecting to \(n)…"
    case .loggingIn:
      return "Logging in to \(n)…"
    case .connected:
      return "Joining \(n)…"
    case .loggedIn:
      return "Logged in to \(n)"
    case .failed(let error):
      return "Failed: \(error)"
    }
  }
  
}

struct ServerTransferRow: View {
  let transfer: TransferInfo

  /// Whether it's waiting its turn, after your other downloads, or in the server's line.
  private var waiting: Bool {
    self.transfer.waiting || self.transfer.queuePosition != nil
  }
    
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.serverTheme) private var theme
  @Environment(HotlineState.self) private var model: HotlineState
  @State private var hovered: Bool = false
  @State private var buttonHovered: Bool = false
  @State private var detailsShown: Bool = false
  
  var body: some View {
    HStack(alignment: .center, spacing: 5) {
      HStack(spacing: 0) {
        Spacer()
        if self.transfer.isFolder {
          Image("Folder")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
        }
        else {
          FileIconView(filename: transfer.title, fileType: nil)
            .frame(width: 16, height: 16)
            .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
        }
        Spacer()
      }
      .frame(width: 20)
      
      Text(self.transfer.folderName ?? self.transfer.title)
        .lineLimit(1)
        .truncationMode(.middle)
      
      Spacer(minLength: 0)
      
      if !self.transfer.done {
        // A clock while it waits its turn, after your other downloads, or in the server's line, and
        // its bar, growing in, once it's going.
        ZStack(alignment: .trailing) {
          if self.waiting {
            Image(systemName: "clock")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
              .help(self.transfer.queueDescription ?? "Waiting")
              .transition(.opacity)
          }
          else {
            ProgressView(value: min(max(self.transfer.progress, 0.0), 1.0), total: 1.0)
              .progressViewStyle(.linear)
              .controlSize(.extraLarge)
              // In the server's theme, in its accent, as it stands out on the sidebar.
              .tint(self.theme?.sidebarAccent.map { Color(nsColor: $0) })
              .frame(maxWidth: 40)
              .transition(.scale(scale: 0, anchor: .trailing).combined(with: .opacity))
          }
        }
        .animation(.snappy(duration: 0.35), value: self.waiting)
      }
      
      if self.hovered {
        Button {
          AppState.shared.cancelTransfer(id: transfer.id)
        } label: {
          Image(systemName: self.buttonHovered ? "xmark.circle.fill" : "xmark.circle")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .opacity(self.buttonHovered ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .padding(0)
        .frame(width: 16, height: 16)
        .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
        .help(transfer.completed || transfer.failed ? "Remove" : "Cancel Transfer")
        .onHover { hovered in
          self.buttonHovered = hovered
        }
      }
      else if transfer.failed {
        Image(systemName: "exclamationmark.triangle.fill")
          .resizable()
          .symbolRenderingMode(.multicolor)
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
      else if transfer.completed {
        Image(systemName: "checkmark.circle.fill")
          .resizable()
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .fileComplete)
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
    }
    .onHover { hovered in
      withAnimation(.snappy(duration: 0.25, extraBounce: 0.3)) {
        self.hovered = hovered
      }
//      self.detailsShown = hovered
    }
    .onTapGesture(count: 2) {
      guard transfer.completed, let url = transfer.fileURL else {
        return
      }

      NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    .contextMenu {
      if transfer.completed, let url = transfer.fileURL {
        Button("Show in Finder", systemImage: "finder") {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        Button("Open", systemImage: "arrow.up.right.square") {
          NSWorkspace.shared.open(url)
        }

        self.openWithMenu(for: url)

        Divider()

        Button("Move to Trash", systemImage: "trash") {
          AppState.shared.cancelTransfer(id: transfer.id)
          NSWorkspace.shared.recycle([url])
        }

        Button("Remove", systemImage: "xmark") {
          AppState.shared.cancelTransfer(id: transfer.id)
        }
      }
      else if !transfer.done {
        Button("Cancel Transfer", systemImage: "xmark") {
          AppState.shared.cancelTransfer(id: transfer.id)
        }
      }
      else {
        if let url = transfer.fileURL {
          Button("Move to Trash", systemImage: "trash") {
            AppState.shared.cancelTransfer(id: transfer.id)
            NSWorkspace.shared.recycle([url])
          }
        }

        Button("Remove", systemImage: "xmark") {
          AppState.shared.cancelTransfer(id: transfer.id)
        }
      }
    }
    .popover(isPresented: .constant(self.detailsShown && !self.transfer.done), arrowEdge: .trailing) {
      let rows: [(String, String)] = [
        ("document", self.transfer.title),
        ("info", self.transfer.displaySize),
        (self.transfer.isUpload ? "arrow.up" : "arrow.down", self.transfer.displaySpeed ?? "--"),
        ("clock", self.transfer.displayTimeRemaining ?? "--")
      ]
      
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
        ForEach(rows, id: \.0) { imageName, label in
          GridRow {
            Image(systemName: imageName)
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
              .gridColumnAlignment(.trailing)
            Text(label)
              .monospacedDigit()
              .gridColumnAlignment(.leading)
          }
        }
      }
      .frame(minWidth: 200, maxWidth: 350, alignment: .leading)
      .padding()
    }
  }
  
  private var formattedProgressHelp: String {
    if self.transfer.completed {
      return "File transfer complete"
    }
    else if self.transfer.failed {
      return "File transfer failed"
    }
    else if self.transfer.cancelled {
      return "File transfer cancelled"
    }
    else if self.transfer.progress > 0.0 {
      var parts: [String] = []
      
      if let speed = self.transfer.displaySpeed {
        parts.append(speed)
      }
      
      if let timeRemaining = self.transfer.displayTimeRemaining {
        parts.append(timeRemaining)
      }
      
      if parts.count > 0 {
        return parts.joined(separator: " • ")
      }
    }
    return ""
  }

  @ViewBuilder
  private func openWithMenu(for url: URL) -> some View {
    Menu("Open With") {
      let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: url)
      let allApps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        .filter { $0 != defaultAppURL }
        .sorted { FileManager.default.displayName(atPath: $0.path) < FileManager.default.displayName(atPath: $1.path) }

      if let defaultAppURL {
        Button {
          NSWorkspace.shared.open([url], withApplicationAt: defaultAppURL, configuration: NSWorkspace.OpenConfiguration())
        } label: {
          Label {
            Text(FileManager.default.displayName(atPath: defaultAppURL.path).replacing(".app", with: ""))
          } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: defaultAppURL.path))
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
          }
        }

        if !allApps.isEmpty {
          Divider()
        }
      }

      ForEach(allApps, id: \.self) { appURL in
        Button {
          NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } label: {
          Label {
            Text(FileManager.default.displayName(atPath: appURL.path).replacing(".app", with: ""))
          } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
          }
        }
      }
    }
  }
}

#Preview("Transfers in the sidebar") {
  let queued = TransferInfo(reference: 1, title: "Hotline.b27.zip", size: 6_900_000, serverID: UUID(), serverName: "The Mobius Strip")
  queued.queuePosition = 3
  let waiting = TransferInfo(reference: 0, title: "README.md", size: 1_000, serverID: UUID())
  waiting.waiting = true
  let going = TransferInfo(reference: 3, title: "MacPaint 3.0b1.zip", size: 3_800_000, serverID: UUID())
  going.progress = 0.4
  return List {
    ServerTransferRow(transfer: queued)
    ServerTransferRow(transfer: waiting)
    ServerTransferRow(transfer: going)
  }
  .listStyle(.sidebar)
  .frame(width: 240, height: 140)
  .environment(HotlineState())
}

/// How the connection to a server is encrypted, from the lock on its globe: with which version of
/// TLS, who the server's certificate is for, and how far that's checked, with the certificate itself
/// a click away.
private struct EncryptedConnectionPopover: View {
  let connection: ServerTrust.Connection
  /// The server's address, as it was connected to.
  let address: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Label("Secure Connection", systemImage: "lock.fill")
          .font(.headline)
        Text("Your connection to the server is encrypted.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
        GridRow(alignment: .firstTextBaseline) {
          Text("Protocol")
            .foregroundStyle(.secondary)
          Text(self.connection.version ?? "TLS")
        }
        GridRow(alignment: .firstTextBaseline) {
          Text("Certificate")
            .foregroundStyle(.secondary)
          Text(self.connection.certificate.name.isEmpty ? "No name" : self.connection.certificate.name)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
        GridRow(alignment: .firstTextBaseline) {
          Text("Identity")
            .foregroundStyle(.secondary)
          // Checked as a browser would, for the address, or else only that it's the certificate
          // the server had the first time. See `ServerTrust`.
          Text(self.connection.certificate.isVerified ? "Verified for \(self.address)" : "Trusted since you first connected")
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.callout)

      Button("Show Certificate") {
        self.showCertificate()
      }
    }
    .padding(16)
    .frame(width: 300, alignment: .leading)
  }

  private func showCertificate() {
    self.connection.certificate.show()
  }
}

extension ServerTrust.Certificate {
  /// Shows the certificate in the system's certificate panel, until it's closed.
  func show() {
    guard let certificate = SecCertificateCreateWithData(nil, self.data as CFData) else {
      return
    }
    _ = SFCertificatePanel.shared().runModal(forCertificates: [certificate], showGroup: false)
  }
}

/// The alerts for a server that has to be connected to securely, when it couldn't be, which ask
/// you what to do rather than connecting without, or trusting a new certificate, unasked:
///
/// - It didn't answer securely: connect without, this once, or always, with the checkbox, for a
///   server whose secure connection's gone for good, or cancel.
/// - Its certificate isn't the one it had: trust the new one, look at it first, or cancel.
struct EncryptionProblemAlerts: ViewModifier {
  @Binding var problem: ServerTrust.Problem?
  /// The server, as the alerts name it.
  let serverName: String
  /// Connects without a secure connection, and whether to from now on.
  let connectAnyway: (_ always: Bool) -> Void
  /// Trusts the new certificate, on the TLS port, and connects.
  let trust: (_ certificate: ServerTrust.Certificate, _ port: Int) -> Void

  @State private var stopRequiring = false

  private var unavailablePort: Int? {
    if case .unavailable(let port) = self.problem {
      return port
    }
    return nil
  }

  private var changedCertificate: (certificate: ServerTrust.Certificate, port: Int)? {
    if case .certificateChanged(let certificate, let port) = self.problem {
      return (certificate, port)
    }
    return nil
  }

  func body(content: Content) -> some View {
    content
      // Each from a view of its own, so the checkbox is only on the one it's for.
      .background {
        Color.clear
          .alert("Couldn't connect securely to “\(self.serverName)”", isPresented: Binding(
            get: { self.unavailablePort != nil },
            set: { if !$0 { self.problem = nil } }
          ), presenting: self.unavailablePort) { _ in
            Button("Connect Insecurely") {
              self.connectAnyway(self.stopRequiring)
              self.stopRequiring = false
            }
            // What Return does, rather than connecting without a secure connection. The checkbox is
            // for connecting, so it's let go.
            Button("Cancel", role: .cancel) {
              self.stopRequiring = false
            }
            .keyboardShortcut(.defaultAction)
          } message: { _ in
            Text("The server didn't respond on its secure port. If you connect insecurely, others on the network may be able to see your password and messages.")
          }
          .dialogSuppressionToggle(Text("Don't ask again"), isSuppressed: self.$stopRequiring)
      }
      .background {
        Color.clear
          .alert("Hotline can't verify the identity of “\(self.serverName)”", isPresented: Binding(
            get: { self.changedCertificate != nil },
            set: { if !$0 { self.problem = nil } }
          ), presenting: self.changedCertificate) { changed in
            Button("Trust New Certificate") {
              self.trust(changed.certificate, changed.port)
            }
            // Shows it, and then asks again.
            Button("Show Certificate") {
              let problem = ServerTrust.Problem.certificateChanged(changed.certificate, port: changed.port)
              DispatchQueue.main.async {
                changed.certificate.show()
                self.problem = problem
              }
            }
            // What Return does, rather than trusting it.
            Button("Cancel", role: .cancel) {}
              .keyboardShortcut(.defaultAction)
          } message: { _ in
            Text("The server's certificate has changed since you last connected. Someone may be pretending to be this server.")
          }
          .dialogSeverity(.critical)
      }
  }
}
