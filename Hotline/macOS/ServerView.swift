import SwiftUI

enum MenuItemType {
  case banner
  case progress
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

struct AgreementView: View {
  @Environment(\.dismiss) var dismiss
  
  let text: String
  let disagree: (() -> Void)?
  let agree: (() -> Void)?
  
  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical) {
        Text(text)
          .padding()
          .font(.system(size: 13))
          .fontDesign(.monospaced)
          .textSelection(.enabled)
          .lineSpacing(3)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
      Divider()
      HStack(spacing: 8) {
        Button("Disagree", action: {
          dismiss()
          disagree?()
        })
        .controlSize(.large)
        .frame(width: 80)
        .keyboardShortcut(.cancelAction)
        
        Button("Agree", action: {
          dismiss()
          agree?()
        })
        .controlSize(.large)
        .frame(width: 80)
        .keyboardShortcut(.defaultAction)
      }
      .frame(maxWidth: .infinity)
      .padding(16)
    }
    .frame(width: 500, height: 500)
  }
}

private func connectionStatusToProgress(status: HotlineClientStatus) -> Double {
  switch status {
  case .disconnected:
    return 0.0
  case .connecting:
    return 0.1
  case .connected:
    return 0.25
  case .loggingIn:
    return 0.5
  case .loggedIn:
    return 1.0
  }
}

struct ServerView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(Prefs.self) private var preferences: Prefs
  @Environment(\.dismiss) var dismiss
  @Environment(\.controlActiveState) private var controlActiveState
  
  @State private var agreementShown: Bool = false
  @State private var selection: MenuItem? = ServerView.menuItems.first
  
  let server: Server
  
  static var menuItems = [
    MenuItem(name: "Chat", image: "bubble", type: .chat),
    MenuItem(name: "News", image: "newspaper", type: .news, serverVersion: 150),
    MenuItem(name: "Board", image: "note.text", type: .messageBoard),
    MenuItem(name: "Files", image: "folder", type: .files),
//    MenuItem(name: "Tasks", image: "arrow.up.circle", type: .tasks),
  ]
  
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
  
  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        
        if model.status != .loggedIn {
          HStack {
            ProgressView(value: connectionStatusToProgress(status: model.status))
              .padding()
          }
          .tag(MenuItem(name: "progress", image: "", type: .progress))
          .frame(maxWidth: .infinity, minHeight: 60)
          .selectionDisabled()
        }
        
        if model.status == .loggedIn {
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
          
          if model.users.count > 0 {
            Section("Users") {
              ForEach(model.users) { user in
                HStack {
                  if let iconString = Hotline.defaultIconSet[Int(user.iconID)] {
                    Text(iconString)
                      .font(.headline)
                      .frame(width: 18)
                      .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
                  }
                  else {
                    Text("")
                      .frame(width: 18)
                  }
                  
                  if user.status.contains(.admin) {
                    if user.status.contains(.idle) {
                      Text(user.name)
                        .foregroundStyle(.red)
                        .opacity(controlActiveState == .inactive ? 0.3 : 0.5)
                    }
                    else {
                      Text(user.name)
                        .foregroundStyle(.red)
                        .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
                    }
                  }
                  else if user.status.contains(.idle) {
                    Text(user.name)
                      .opacity(controlActiveState == .inactive ? 0.3 : 0.5)
                  }
                  else {
                    Text(user.name)
//                      .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
                  }
                  Spacer()
                }
                .tag(MenuItem(name: user.name, image: "", type: .user, userID: user.id))
              }
            }
          }
        }
      }
      .frame(minWidth: 200, idealWidth: 200)
    } detail: {
      if let selection = self.selection {
        switch selection.type {
        case .banner:
          EmptyView()
        case .progress:
          EmptyView()
        case .chat:
          ChatView()
            .navigationTitle(self.model.serverTitle)
            .navigationSubtitle(self.model.users.count > 0 ? "^[\(self.model.users.count) user](inflect: true) online" : "")
        case .news:
          NewsView()
            .navigationTitle(self.model.serverTitle)
            .navigationSubtitle(self.model.users.count > 0 ? "^[\(self.model.users.count) user](inflect: true) online" : "")
        case .messageBoard:
          MessageBoardView()
            .navigationTitle(self.model.serverTitle)
            .navigationSubtitle(self.model.users.count > 0 ? "^[\(self.model.users.count) user](inflect: true) online" : "")
        case .files:
          FilesView()
            .navigationTitle(self.model.serverTitle)
            .navigationSubtitle(self.model.users.count > 0 ? "^[\(self.model.users.count) user](inflect: true) online" : "")
        case .tasks:
          EmptyView()
        case .user:
          if let selectionUserID = selection.userID {
            MessageView(userID: selectionUserID)
              .navigationTitle(self.model.serverTitle)
              .navigationSubtitle(self.model.users.count > 0 ? "^[\(self.model.users.count) user](inflect: true) online" : "")
          }
        }
      }
    }
    .navigationTitle("")
    .onAppear {
      print(" YAYY")
      self.model.login(server: self.server, login: "", password: "", username: preferences.username, iconID: preferences.userIconID) { success in
        if !success {
          print("FAILED LOGIN??")
        }
        else {
          print("GETTING USER LIST????!")
          self.sendPreferences()
          self.model.getUserList()
        }
      }
    }
    .onDisappear {
      self.model.disconnect()
    }
    .onChange(of: model.status) {
      if model.status == .disconnected {
        dismiss()
      }
    }
    .onChange(of: preferences.userIconID) { self.sendPreferences() }
    .onChange(of: preferences.username) { self.sendPreferences() }
    .onChange(of: preferences.refusePrivateMessages) { self.sendPreferences() }
    .onChange(of: preferences.refusePrivateChat) { self.sendPreferences() }
    .onChange(of: preferences.enableAutomaticMessage) { self.sendPreferences() }
    .onChange(of: preferences.automaticMessage) { self.sendPreferences() }
  }
}

//#Preview {
//  ServerView(server: Server(name: "", description: "", address: "", port: 0))
//}
