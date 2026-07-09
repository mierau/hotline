import SwiftUI
import UniformTypeIdentifiers
import AppKit

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

struct ListItemView: View {
  @Environment(\.controlActiveState) private var controlActiveState
  
  let icon: String?
  let title: String
  let unread: Bool
  
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
      if unread {
        Circle()
          .frame(width: 6, height: 6)
          .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6))
          .opacity(0.75)
      }
    }
  }
}

extension FocusedValues {
  @Entry var activeHotlineModel: HotlineState?
  @Entry var activeServerState: ServerState?
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
  @State private var composeMessageUser: User? = nil
  @State private var contextMenuUserInfo: HotlineUserClientInfo? = nil
  @State private var disconnectUserTarget: User? = nil
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
      if self.model.status == .disconnected {
        VStack(alignment: .center) {
          Spacer()
          self.connectForm
          Spacer()
        }
        .presentedWindowToolbarStyle(.unified(showsTitle: false))
        .navigationTitle(self.model.serverTitle.isBlank ? "Hotline" : self.model.serverTitle)
      }
      else if self.model.status.isLoggingIn {
        HStack {
          Image("Hotline")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundColor(Color(hex: 0xE10000))
            .frame(width: 18)
            .opacity(self.controlActiveState == .inactive ? 0.5 : 1.0)
            .padding(.trailing, 4)

          ProgressView(value: connectionStatusToProgress(status: self.model.status)) {
            Text(connectionStatusToLabel(status: self.model.status))
          }
          .accentColor(self.colorScheme == .dark ? .white : .black)
        }
        .frame(maxWidth: 300)
        .padding()
        .navigationTitle(self.model.serverTitle.isBlank ? "Hotline" : self.model.serverTitle)
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
          .onChange(of: Prefs.shared.refusePrivateMessages) {
            Task { try? await self.model.sendUserPreferences() }
          }
          .onChange(of: Prefs.shared.refusePrivateChat) {
            Task { try? await self.model.sendUserPreferences() }
          }
          .onChange(of: Prefs.shared.enableAutomaticMessage) {
            Task { try? await self.model.sendUserPreferences() }
          }
          .onChange(of: Prefs.shared.automaticMessage) {
            Task { try? await self.model.sendUserPreferences() }
          }
          .sheet(isPresented: Binding(
            get: { self.model.agreementText != nil },
            set: { if !$0 { self.model.agreementText = nil } }
          )) {
            ServerAgreementSheet()
              .environment(self.model)
              .presentationSizing(.fitted)
          }
          .sheet(isPresented: self.$state.broadcastShown) {
            BroadcastMessageSheet()
              .environment(self.model)
              .presentationSizing(.fitted)
          }
          .sheet(isPresented: self.$state.accountsShown) {
            AccountManagerView()
              .environment(self.model)
              .frame(width: 400, height: 450)
              .presentationSizing(.fitted)
          }
          .toolbar {
            if #available(macOS 26.0, *) {
              ToolbarItem(placement: .navigation) {
                Image("Server Large")
                  .resizable()
                  .scaledToFit()
                  .frame(width: 28)
                  .opacity(self.controlActiveState == .inactive ? 0.4 : 1.0)
              }
              .sharedBackgroundVisibility(.hidden)
            }
            else {
              ToolbarItem(placement: .navigation) {
                Image("Server Large")
                  .resizable()
                  .scaledToFit()
                  .frame(width: 28)
                  .opacity(self.controlActiveState == .inactive ? 0.4 : 1.0)
              }
            }
          }
      }
    }
    .onDisappear {
      Task {
        await self.model.disconnect()
      }
    }
    .onChange(of: self.model.serverTitle) {
      self.state.serverName = self.model.serverTitle
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
    }
    .onChange(of: self.server) {
      // During window restoration, the binding may update after the view
      // is created with the defaultValue. Sync once when the real value arrives.
      if !self.connectionDisplayed && !self.server.address.isEmpty {
        self.syncFieldsFromServer()
        self.connectionDisplayed = true
      }
    }
    .alert("Something Went Wrong", isPresented: self.$model.errorDisplayed) {
      Button("OK") {}
    } message: {
      if let message = self.model.errorMessage,
         !message.isBlank {
        Text(message)
      }
    }
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
    .focusedSceneValue(\.activeHotlineModel, model)
    .focusedSceneValue(\.activeServerState, state)
  }
  
  private var connectForm: some View {
    ConnectView(address: self.$connectAddress, login: self.$connectLogin, password: self.$connectPassword) {
      self.connectToServer()
    }
    .focusSection()
    .onChange(of: self.connectAddress) {
      let (a, p) = Server.parseServerAddressAndPort(self.connectAddress)
      self.server.address = a
      self.server.port = p
    }
    .onChange(of: self.connectLogin) {
      self.server.login = self.connectLogin.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    .onChange(of: self.connectPassword) {
      self.server.password = self.connectPassword
    }
  }
  
  private var navigationList: some View {
    List(selection: $state.selection) {
      // Don't show news on older servers.
      ForEach(model.serverVersion < 151 ? ServerView.classicMenuItems : ServerView.menuItems) { menuItem in
        if menuItem.type == .chat {
          ListItemView(icon: menuItem.image, title: menuItem.name, unread: model.unreadPublicChat).tag(menuItem.type)
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
          ListItemView(icon: menuItem.image, title: menuItem.name, unread: false).tag(menuItem.type)
            .overlay(alignment: .trailing) {
              if case .searching(_, _) = model.fileSearchStatus {
                ProgressView()
                  .controlSize(.mini)
                  .padding(.trailing, 4)
              }
            }
        }
        else {
          ListItemView(icon: menuItem.image, title: menuItem.name, unread: false).tag(menuItem.type)
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
      HStack(spacing: 5) {
        if let iconImage = HotlineState.getClassicIcon(Int(user.iconID)) {
          Image(nsImage: iconImage)
            .frame(width: 16, height: 16)
            .padding(.leading, 2)
            .padding(.trailing, 2)
        }
        else {
          Image("User")
            .frame(width: 16, height: 16)
            .padding(.leading, 2)
            .padding(.trailing, 2)
        }
        
        Text(user.name)
          .foregroundStyle(user.isAdmin ? Color.hotlineRed : .primary)
        
        Spacer()
        
        if model.hasUnreadPrivateMessages(userID: user.id) {
          Circle()
            .frame(width: 6, height: 6)
            .foregroundStyle(user.isAdmin ? Color.hotlineRed : .primary.opacity(0.5))
            .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 2))
        }
      }
      .opacity(user.isIdle ? 0.5 : 1.0)
      .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      .tag(ServerNavigationType.user(userID: user.id))
      .contextMenu {
        if self.model.access?.contains(.canGetClientInfo) == true {
          Button("Get Info", systemImage: "info.circle") {
            Task {
              if let info = try await self.model.getClientInfoText(id: user.id) {
                self.contextMenuUserInfo = info
              }
            }
          }
        }

        Button("Send Message...", systemImage: "square.and.pencil") {
          self.composeMessageUser = user
        }
        .disabled(self.model.access?.contains(.canSendMessages) != true || user.refusesPrivateMessages)

        if self.model.access?.contains(.canDisconnectUsers) == true {
          Divider()

          Button("Disconnect User", systemImage: "nosign", role: .destructive) {
            self.disconnectUserTarget = user
          }
        }
      }
    }
  }
  
  var serverView: some View {
    NavigationSplitView(columnVisibility: self.$state.columnVisibility) {
      self.navigationList
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
          MessageBoardView()
        case .files:
          FilesView(serverState: self.state)
        case .user(let userID):
          MessageView(userID: userID)
            .id(userID)
        }
    }
    .navigationTitle(self.model.serverTitle)
    .sheet(item: self.$composeMessageUser) { user in
      ComposeMessageView(userID: user.id, username: user.name)
        .environment(self.model)
    }
    .sheet(item: self.$contextMenuUserInfo) { info in
      UserClientInfoSheet(info: info)
    }
    .alert(
      "Are you sure you want to disconnect \(self.disconnectUserTarget?.name ?? "this user")?",
      isPresented: Binding(
        get: { self.disconnectUserTarget != nil },
        set: { if !$0 { self.disconnectUserTarget = nil } }
      )
    ) {
      Button("Disconnect", role: .destructive) {
        if let user = self.disconnectUserTarget {
          Task {
            try await self.model.disconnectUser(id: user.id, options: nil)
          }
        }
      }
    } message: {
      Text("They will be disconnected from the server, but may reconnect.")
    }
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

  private func syncFieldsFromServer() {
    self.connectAddress = self.server.displayAddress
    self.connectLogin = self.server.login
    self.connectPassword = self.server.password
  }

  @MainActor func connectToServer() {
    guard !self.server.address.isEmpty else {
      return
    }
    
    // Set status here so it's immediate (not waiting to enter task).
    self.model.status = .connecting

    Task { @MainActor in
      do {
        try await self.model.login(
          server: server,
          username: Prefs.shared.username,
          iconID: Prefs.shared.userIconID
        )
      } catch {
        print("ServerView: Login failed: \(error)")
      }
    }
  }
  
  private func connectionStatusToProgress(status: HotlineConnectionStatus) -> Double {
    switch status {
    case .disconnected:
      return 0.0
    case .connecting:
      return 0.4
    case .connected:
      return 0.9
    case .loggedIn:
      return 1.0
    case .failed:
      return 0.0
    }
  }

  private func connectionStatusToLabel(status: HotlineConnectionStatus) -> String {
    let n = server.name ?? server.address
    switch status {
    case .disconnected:
      return "Disconnected"
    case .connecting:
      return "Connecting to \(n)..."
    case .connected:
      return "Logging in to \(n)..."
    case .loggedIn:
      return "Logged in to \(n)"
    case .failed(let error):
      return "Failed: \(error)"
    }
  }
  
}

struct ServerTransferRow: View {
  let transfer: TransferInfo
    
  @Environment(\.controlActiveState) private var controlActiveState
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
        if self.transfer.progress == 0.0 {
          ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.extraLarge)
            .frame(maxWidth: 40)
        }
        else {
          ProgressView(value: min(max(self.transfer.progress, 0.0), 1.0), total: 1.0)
            .progressViewStyle(.linear)
            .controlSize(.extraLarge)
            .frame(maxWidth: 40)
        }
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
