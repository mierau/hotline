import SwiftUI
import UniformTypeIdentifiers

enum MenuItemType {
  case chat
  case news
  case messageBoard
  case files
  case tasks
  case user
}

struct MenuItem: Identifiable, Hashable {
  let id: UUID
  let name: String
  let image: String
  let type: MenuItemType
  let userID: UInt?
  let serverVersion: UInt?
  
  init(name: String, image: String, type: MenuItemType, userID: UInt? = nil, serverVersion: UInt? = nil) {
    self.id = UUID()
    self.name = name
    self.image = image
    self.type = type
    self.userID = userID
    self.serverVersion = serverVersion
  }
  
  static func == (lhs: MenuItem, rhs: MenuItem) -> Bool {
    if lhs.type == .user && rhs.type == .user {
      return lhs.userID == rhs.userID
    }
    return lhs.id == rhs.id
  }
}

struct ListItemView: View {
  let icon: String
  let title: String
  
  var body: some View {
      HStack {
        Image(systemName: icon)
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
        Text(title)
      }
  }
}

struct TransferItemView: View {
  let transfer: TransferInfo
  
  private func fileIcon(name: String) -> Image {
    let fileExtension = (name as NSString).pathExtension
    return Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? UTType.content))
  }
  
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
    HStack(alignment: .center) {
      HStack(spacing: 0) {
        Spacer()
        fileIcon(name: transfer.title)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
        Spacer()
      }
      .frame(width: 18)
      
      Text(transfer.title)
        .lineLimit(1)
        .truncationMode(.middle)
      
      Spacer()
      
      if self.hovered {
        Button {
          model.deleteTransfer(id: transfer.id)
        } label: {
          if transfer.completed {
            Image(systemName: self.buttonHovered ? "xmark.circle.fill" : "xmark.circle")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 16, height: 16)
              .opacity(self.buttonHovered ? 1.0 : 0.5)
          }
          else {
            Image(systemName: self.buttonHovered ? "trash.circle.fill" : "trash.circle")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 16, height: 16)
              .opacity(self.buttonHovered ? 1.0 : 0.5)
          }
        }
        .buttonStyle(.plain)
        .padding(0)
        .frame(width: 16, height: 16)
        .help(transfer.completed || transfer.failed ? "Remove" : "Cancel Transfer")
        .onHover { hovered in
          self.buttonHovered = hovered
        }
      }
      else if transfer.failed {
        Image(systemName: "exclamationmark.triangle")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
      }
      else if transfer.completed {
        Image(systemName: "checkmark.circle.fill")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
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
      self.hovered = hovered
    }
    .help(formattedProgressHelp())
  }
}

struct ServerView: View {
  @Environment(Prefs.self) private var preferences: Prefs
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.controlActiveState) private var controlActiveState
  
  @State private var model: Hotline = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  @State private var agreementShown: Bool = false
  @State private var selection: MenuItem? = ServerView.menuItems.first
  
  @State private var connectAddress: String = ""
  @State private var connectLogin: String = ""
  @State private var connectPassword: String = ""
  
  @Binding var server: Server
  
  static var menuItems = [
    MenuItem(name: "Chat", image: "bubble", type: .chat),
    MenuItem(name: "News", image: "newspaper", type: .news, serverVersion: 150),
    MenuItem(name: "Board", image: "note.text", type: .messageBoard),
    MenuItem(name: "Files", image: "folder", type: .files),
  ]
  
  var connectForm: some View {
    GroupBox {
      Form {
        Group {
          TextField(text: $connectAddress) {
            Text("Address:")
          }
          TextField(text: $connectLogin, prompt: Text("optional")) {
            Text("Login:")
          }
          SecureField(text: $connectPassword, prompt: Text("optional")) {
            Text("Password:")
          }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.regular)
        .onChange(of: connectAddress) {
          let (a, p) = Server.parseServerAddressAndPort(connectAddress)
          server.address = a
          server.port = p
          print("ADDRESS CHANGED: '\(connectAddress)' \(a) \(p)")
        }
        .onChange(of: connectLogin) {
          server.login = connectLogin.trimmingCharacters(in: .whitespacesAndNewlines)
          print("LOGIN CHANGED: '\(connectLogin)'" + $server.wrappedValue.login)
        }
        .onChange(of: connectPassword) {
          server.password = connectPassword
          print("PASS CHANGED: '\(connectPassword)'" + server.password)
        }
        
        HStack {
          Button {
            print("SAVE BOOKMARK... SOMEHOW")
          } label: {
            Text("Save...")
          }
          .controlSize(.regular)
          .buttonStyle(.automatic)
          .help("Save server as bookmark")
          
          Spacer()
          
          Button {
            dismiss()
          } label: {
            Text("Cancel")
          }
          .controlSize(.regular)
          .buttonStyle(.automatic)
          .keyboardShortcut(.cancelAction)
          
          Button {
            
//            if var s = server {
//              print("CHANGING EXISTING SERVER")
//              s.name = newServer.name
//              s.description = newServer.description
//              s.users = newServer.users
//              s.address = newServer.address
//              s.port = newServer.port
//              s.login = newServer.login
//              s.password = newServer.password
//            }
//            else {
//              server = newServer
//            }
            
            Task {
              await connectToServer()
            }
          } label: {
            Text("Connect")
          }
          .controlSize(.regular)
          .buttonStyle(.automatic)
          .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
        
      }
      .padding()
    }
    .frame(maxWidth: 350)
    .padding()
  }
  
  var navigationList: some View {
    List(selection: $selection) {
      ForEach(ServerView.menuItems) { menuItem in
        if let minServerVersion = menuItem.serverVersion {
          if let v = model.serverVersion, v >= minServerVersion {
            ListItemView(icon: menuItem.image, title: menuItem.name)
              .tag(menuItem)
          }
        }
        else {
          ListItemView(icon: menuItem.image, title: menuItem.name)
            .tag(menuItem)
        }
      }
      
      if model.transfers.count > 0 {
        self.transfersSection
      }
      
      if model.users.count > 0 {
        self.usersSection
      }
    }
  }
  
  var transfersSection: some View {
    Section("Transfers") {
      ForEach(model.transfers) { transfer in
        TransferItemView(transfer: transfer)
      }
    }
  }
  
  var usersSection: some View {
    Section("\(model.users.count) Online") {
      ForEach(model.users) { user in
        HStack {
          if let iconImage = Hotline.getClassicIcon(Int(user.iconID)) {
            Image(nsImage: iconImage)
              .frame(width: 18)
          }
          else {
            Text("")
              .frame(width: 18)
          }
          
          Text(user.name)
            .foregroundStyle(user.isAdmin ? Color(hex: 0xE10000) : .primary)
          
          Spacer()
        }
        .opacity(user.isIdle ? 0.6 : 1.0)
        .opacity(controlActiveState == .inactive ? 0.4 : 1.0)
        .tag(MenuItem(name: user.name, image: "", type: .user, userID: user.id))
      }
    }
  }
  
  var serverView: some View {
    NavigationSplitView {
      self.navigationList
        .frame(maxWidth: .infinity)
        .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 500)
    } detail: {
      if let selection = selection {
        switch selection.type {
        case .chat:
          ChatView()
            .navigationTitle(model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .news:
          NewsView()
            .navigationTitle(model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .messageBoard:
          MessageBoardView()
            .navigationTitle(model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .files:
          FilesView()
            .navigationTitle(model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .tasks:
          EmptyView()
        case .user:
          if let selectionUserID = selection.userID {
            MessageView(userID: selectionUserID)
              .navigationTitle(model.serverTitle)
              .navigationSplitViewColumnWidth(min: 250, ideal: 500)
          }
        }
      }
    }
  }
  
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
          .onChange(of: preferences.userIconID) { sendPreferences() }
          .onChange(of: preferences.username) { sendPreferences() }
          .onChange(of: preferences.refusePrivateMessages) { sendPreferences() }
          .onChange(of: preferences.refusePrivateChat) { sendPreferences() }
          .onChange(of: preferences.enableAutomaticMessage) { sendPreferences() }
          .onChange(of: preferences.automaticMessage) { sendPreferences() }
          .toolbar {
            ToolbarItem(placement: .navigation) {
              Image(systemName: "globe.americas.fill")
                .renderingMode(.template)
              
                .resizable()
                .scaledToFit()
                .frame(width: 18)
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
      connectToServer()
    }
  }
  
  // MARK: -
  
  @MainActor func connectToServer() {
    guard !server.address.isEmpty else {
      return
    }
    
    model.login(server: server, username: preferences.username, iconID: preferences.userIconID) { success in
      if !success {
        print("FAILED LOGIN??")
        model.disconnect()
      }
      else {
        print("GETTING USER LIST????!")
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
//    if let s = self.server {
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
//    }
//    else {
//      switch status {
//      case .disconnected:
//        return "Disconnected"
//      case .connecting:
//        return "Connecting..."
//      case .connected:
//        return "Connected"
//      case .loggingIn:
//        return "Logging in..."
//      case .loggedIn:
//        return "Logged in"
//      }
//    }
  }
  
  @MainActor func sendPreferences() {
    if self.model.status == .loggedIn {
      var options: HotlineUserOptions = HotlineUserOptions()
      
      if preferences.refusePrivateMessages {
        options.update(with: .refusePrivateMessages)
      }
      
      if preferences.refusePrivateChat {
        options.update(with: .refusePrivateChat)
      }
      
      if preferences.enableAutomaticMessage {
        options.update(with: .automaticResponse)
      }
      
      print("Updating preferences with server")
      
      self.model.sendUserInfo(username: preferences.username, iconID: preferences.userIconID, options: options, autoresponse: preferences.automaticMessage)
    }
  }
}

//#Preview {
//  ServerView(server: Server(name: "", description: "", address: "", port: 0))
//}
