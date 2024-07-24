import SwiftUI
import UniformTypeIdentifiers

@Observable
class ServerState: Equatable {
  var id: UUID = UUID()
  var selection: ServerNavigationType
  
  init(selection: ServerNavigationType) {
    self.selection = selection
  }
  
  static func == (lhs: ServerState, rhs: ServerState) -> Bool {
    return lhs.id == rhs.id
  }
}

enum MenuItemType {
  case chat
  case news
  case messageBoard
  case files
  case tasks
  case user
}

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
        //            .renderingMode(.template)
          .scaledToFit()
          .frame(width: 20, height: 20)
//          .padding(.leading, 2)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
      
      Text(title)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer()
      if unread {
        Circle()
          .frame(width: 6, height: 6)
          .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 2))
          .opacity(0.5)
      }
    }
  }
}

struct ActiveHotlineModelFocusedValueKey: FocusedValueKey {
  typealias Value = Hotline
}

struct ActiveServerStateFocusedValueKey: FocusedValueKey {
  typealias Value = ServerState
}

extension FocusedValues {
  var activeHotlineModel: Hotline? {
    get { self[ActiveHotlineModelFocusedValueKey.self] }
    set { self[ActiveHotlineModelFocusedValueKey.self] = newValue }
  }
  
  var activeServerState: ServerState? {
    get { self[ActiveServerStateFocusedValueKey.self] }
    set { self[ActiveServerStateFocusedValueKey.self] = newValue }
  }
}

enum ServerNavigationType: Identifiable, Hashable, Equatable {
  var id: String {
    switch self {
    case .chat:
      return "Chat"
    case .news:
      return "News"
    case .board:
      return "Board"
    case .files:
      return "Files"
    case .accounts:
      return "Accounts"
    case .user(let userID):
      return String(userID)
    }
  }
  
  case chat
  case news
  case board
  case files
  case accounts
  case user(userID: UInt16)
}

struct ServerView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext
  
  @State private var model: Hotline = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  @State private var state: ServerState = ServerState(selection: .chat)
  @State private var agreementShown: Bool = false
  @State private var connectAddress: String = ""
  @State private var connectLogin: String = ""
  @State private var connectPassword: String = ""
  @State private var connectNameSheetPresented: Bool = false
  @State private var connectName: String = ""

  @Binding var server: Server
  
  static var menuItems: [ServerMenuItem] = [
    ServerMenuItem(type: .chat, name: "Chat", image: "Section Chat"),
    ServerMenuItem(type: .board, name: "Board", image: "Section Board"),
    ServerMenuItem(type: .news, name: "News", image: "Section News"),
    ServerMenuItem(type: .files, name: "Files", image: "Section Files"),
    ServerMenuItem(type: .accounts, name: "Accounts", image: "Section Users"),
  ]
  
  static var classicMenuItems: [ServerMenuItem] = [
    ServerMenuItem(type: .chat, name: "Chat", image: "Section Chat"),
    ServerMenuItem(type: .board, name: "Board", image: "Section Board"),
    ServerMenuItem(type: .files, name: "Files", image: "Section Files"),
  ]
  
  enum FocusFields {
    case address
    case login
    case password
  }
  
  @FocusState private var focusedField: FocusFields?
  
  var body: some View {
    Group {
      if model.status == .disconnected {
        connectForm
          .navigationTitle("Connect to Server")
      }
      else if model.status != .loggedIn {
        HStack {
          Image("Hotline")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundColor(Color(hex: 0xE10000))
            .frame(width: 18)
            .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
            .padding(.trailing, 4)
          
          ProgressView(value: connectionStatusToProgress(status: model.status)) {
            Text(connectionStatusToLabel(status: model.status))
          }
          .accentColor(colorScheme == .dark ? .white : .black)
        }
        .frame(maxWidth: 300)
        .padding()
        .navigationTitle("Connecting to Server")
      }
      else {
        serverView
          .environment(model)
          .onChange(of: Prefs.shared.userIconID) { sendPreferences() }
          .onChange(of: Prefs.shared.username) { sendPreferences() }
          .onChange(of: Prefs.shared.refusePrivateMessages) { sendPreferences() }
          .onChange(of: Prefs.shared.refusePrivateChat) { sendPreferences() }
          .onChange(of: Prefs.shared.enableAutomaticMessage) { sendPreferences() }
          .onChange(of: Prefs.shared.automaticMessage) { sendPreferences() }
          .toolbar {
            ToolbarItem(placement: .navigation) {
              Image("Server Large")
//                .renderingMode(.template)
              
                .resizable()
                .scaledToFit()
                .frame(width: 28)
                .opacity(controlActiveState == .inactive ? 0.4 : 1.0)
            }
          }
      }
    }
    .onDisappear {
      model.disconnect()
    }
    .task {
      var address = server.address
      if server.port != HotlinePorts.DefaultServerPort {
        address += ":\(server.port)"
      }
      connectAddress = server.address
      connectLogin = server.login
      connectPassword = server.password
      
      // Connect to server automatically unless the option key is held down.
      if !NSEvent.modifierFlags.contains(.option) {
        connectToServer()
      }
    }
    .focusedSceneValue(\.activeHotlineModel, model)
    .focusedSceneValue(\.activeServerState, state)
  }
  
  var connectForm: some View {
    VStack(alignment: .center) {
      GroupBox {
        Form {
          Group {
            TextField(text: $connectAddress) {
              Text("Address:")
            }
            .focused($focusedField, equals: .address)
            
            Text("Type the address of the Hotline server you would like to connect to. If you have an account on that server, type your login and password too.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.bottom, 4)
            
            TextField(text: $connectLogin, prompt: Text("Optional")) {
              Text("Login:")
            }
            .focused($focusedField, equals: .login)
            SecureField(text: $connectPassword, prompt: Text("Optional")) {
              Text("Password:")
            }
            .focused($focusedField, equals: .password)
          }
          .textFieldStyle(.roundedBorder)
          .controlSize(.large)
          
          HStack {
            Button("Save...") {
              if !connectAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                connectNameSheetPresented = true
              }
            }
            .disabled(connectAddress.isEmpty)
            .controlSize(.regular)
            .buttonStyle(.automatic)
            .help("Bookmark server")
            
            Spacer()
            
            Button("Cancel") {
              dismiss()
            }
            .controlSize(.regular)
            .buttonStyle(.automatic)
            .keyboardShortcut(.cancelAction)
            
            Button("Connect") {
              Task {
                await connectToServer()
              }
            }
            
            .controlSize(.regular)
            .buttonStyle(.automatic)
            .keyboardShortcut(.defaultAction)
          }
          .padding(.top, 8)
          
        }
        .padding()
        .onChange(of: connectAddress) {
          let (a, p) = Server.parseServerAddressAndPort(connectAddress)
          server.address = a
          server.port = p
        }
        .onChange(of: connectLogin) {
          server.login = connectLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onChange(of: connectPassword) {
          server.password = connectPassword
        }
      }
      .onAppear {
        focusedField = .address
      }
    }
    .frame(maxWidth: 380)
    .padding()
    .sheet(isPresented: $connectNameSheetPresented) {
      VStack(alignment: .leading) {
        Text("Name this server bookmark:")
          .foregroundStyle(.secondary)
          .padding(.bottom, 4)
        TextField("Bookmark Name", text: $connectName)
          .textFieldStyle(.roundedBorder)
          .controlSize(.large)
      }
      .frame(width: 250)
      .padding()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            connectNameSheetPresented = false
            connectName = ""
          }
        }
        
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let name = String(connectName.trimmingCharacters(in: .whitespacesAndNewlines))
            if !name.isEmpty {
              connectNameSheetPresented = false
              connectName = ""
              Task.detached {
                let (host, port) = Server.parseServerAddressAndPort(connectAddress)
                let login: String? = connectLogin.isEmpty ? nil : connectLogin
                let password: String? = connectPassword.isEmpty ? nil : connectPassword
                
                if !host.isEmpty {
                  let newBookmark = Bookmark(type: .server, name: name, address: host, port: port, login: login, password: password)
                  Bookmark.add(newBookmark, context: modelContext)
                }
              }
            }
          }
        }
      }
    }
  }
  
  var navigationList: some View {
    List(selection: $state.selection) {
      // Don't show news on older servers.
      ForEach(model.serverVersion < 151 ? ServerView.classicMenuItems : ServerView.menuItems) { menuItem in
        if menuItem.type == .chat {
          ListItemView(icon: menuItem.image, title: menuItem.name, unread: model.unreadPublicChat).tag(menuItem.type)
        }
        else if menuItem.type == .accounts {
          if model.access?.contains(.canOpenUsers) == true {
            ListItemView(icon: menuItem.image, title: menuItem.name, unread: false).tag(menuItem.type)
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
        model.markInstantMessagesAsRead(userID: userID)
      default:
        break
      }
    }
  }
  
  var transfersSection: some View {
//    Section("Transfers") {
      ForEach(model.transfers) { transfer in
        TransferItemView(transfer: transfer)
      }
//    }
  }
  
  var usersSection: some View {
//    Section("\(model.users.count) Online") {
      ForEach(model.users) { user in
        HStack(spacing: 5) {
          if let iconImage = Hotline.getClassicIcon(Int(user.iconID)) {
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
          
          if model.hasUnreadInstantMessages(userID: user.id) {
            Circle()
              .frame(width: 6, height: 6)
              .foregroundStyle(user.isAdmin ? Color.hotlineRed : .primary.opacity(0.5))
              .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 2))
          }
        }
        .opacity(user.isIdle ? 0.5 : 1.0)
        .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
        .tag(ServerNavigationType.user(userID: user.id))
      }
//    }
  }
  
  var serverView: some View {
    NavigationSplitView {
      self.navigationList
        .frame(maxWidth: .infinity)
        .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 500)
    } detail: {
        switch state.selection {
        case .chat:
          ChatView()
            .navigationTitle(model.serverTitle)
            .navigationSubtitle("Public Chat")
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .news:
          NewsView()
            .navigationTitle(model.serverTitle)
            .navigationSubtitle("News")
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .board:
          MessageBoardView()
            .navigationTitle(model.serverTitle)
            .navigationSubtitle("Message Board")
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .files:
          FilesView()
            .navigationTitle(model.serverTitle)
            .navigationSubtitle("Shared Files")
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .accounts:
            AccountManagerView()
              .navigationTitle(model.serverTitle)
              .navigationSubtitle("Accounts")
              .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .user(let userID):
          let user = model.users.first(where: { $0.id == userID })
          MessageView(userID: userID)
            .navigationTitle(model.serverTitle)
            .navigationSubtitle(user?.name ?? "Private Message")
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
            .onAppear {
              model.markInstantMessagesAsRead(userID: userID)
            }
        }
    }
    .toolbar(removing: .sidebarToggle)

  }
  
  
  // MARK: -
  
  @MainActor func connectToServer() {
    guard !server.address.isEmpty else {
      return
    }
    model.login(server: server, username: Prefs.shared.username, iconID: Prefs.shared.userIconID) { success in
      if !success {
        print("FAILED LOGIN??")
        model.disconnect()
      }
      else {
        sendPreferences()
        model.getUserList()
        model.downloadBanner()
      }
    }
  }
  
  private func connectionStatusToProgress(status: HotlineClientStatus) -> Double {
    switch status {
    case .disconnected:
      return 0.0
    case .connecting:
      return 0.4
    case .connected:
      return 0.75
    case .loggingIn:
      return 0.9
    case .loggedIn:
      return 1.0
    }
  }
  
  private func connectionStatusToLabel(status: HotlineClientStatus) -> String {
    let n = server.name ?? server.address
    switch status {
    case .disconnected:
      return "Disconnected"
    case .connecting:
      return "Connecting to \(n)..."
    case .connected:
      return "Connected to \(n)"
    case .loggingIn:
      return "Logging in to \(n)..."
    case .loggedIn:
      return "Logged in to \(n)"
    }
  }
  
  @MainActor func sendPreferences() {
    if self.model.status == .loggedIn {
      var options: HotlineUserOptions = HotlineUserOptions()
      
      if Prefs.shared.refusePrivateMessages {
        options.update(with: .refusePrivateMessages)
      }
      
      if Prefs.shared.refusePrivateChat {
        options.update(with: .refusePrivateChat)
      }
      
      if Prefs.shared.enableAutomaticMessage {
        options.update(with: .automaticResponse)
      }
      
      print("Updating preferences with server")
      
      self.model.sendUserInfo(username: Prefs.shared.username, iconID: Prefs.shared.userIconID, options: options, autoresponse: Prefs.shared.automaticMessage)
    }
  }
}

//#Preview {
//  ServerView(server: Server(name: "", description: "", address: "", port: 0))
//}

struct TransferItemView: View {
  let transfer: TransferInfo
    
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(Hotline.self) private var model: Hotline
  @State private var hovered: Bool = false
  @State private var buttonHovered: Bool = false
  
  private func formattedProgressHelp() -> String {
    if self.transfer.completed {
      return "File transfer complete"
    }
    else if self.transfer.failed {
      return "File transfer failed"
    }
    else if self.transfer.progress > 0.0 {
      if self.transfer.timeRemaining > 0.0 {
        return "\(round(self.transfer.progress * 100.0))% – \(self.transfer.timeRemaining) seconds left"
      }
      else {
        return "\(round(self.transfer.progress * 100.0))% complete"
      }
    }
    return ""
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 5) {
      HStack(spacing: 0) {
        Spacer()
        FileIconView(filename: transfer.title)
          .frame(width: 16, height: 16)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
//          .padding(.leading, 2)
        Spacer()
      }
      .frame(width: 20)
      
      Text(transfer.title)
        .lineLimit(1)
        .truncationMode(.middle)
      
      Spacer()
      
      if self.hovered {
        Button {
          model.deleteTransfer(id: transfer.id)
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
          .foregroundStyle(Color.fileComplete)
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
      else if transfer.progress == 0.0 {
        ProgressView()
          .progressViewStyle(.circular)
          .controlSize(.small)
      }
      else {
        ProgressView(value: transfer.progress, total: 1.0)
          .progressViewStyle(.circular)
          .controlSize(.small)
      }
    }
    .onHover { hovered in
      withAnimation(.easeOut(duration: 0.25)) {
        self.hovered = hovered
      }
    }
    .help(formattedProgressHelp())
  }
}
