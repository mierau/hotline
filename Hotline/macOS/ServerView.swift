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
//        Spacer()
      }
      //.tag(item.tag)
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
  @State private var selectedCategoryId: MenuItem.ID?
  @Environment(\.dismiss) var dismiss
  
  let server: Server
  
  @State private var selection: MenuItem? = ServerView.menuItems.first
  
  static var menuItems = [
    MenuItem(name: "Chat", image: "bubble", type: .chat),
    MenuItem(name: "News", image: "newspaper", type: .news, serverVersion: 150),
    MenuItem(name: "Board", image: "note.text", type: .messageBoard),
    MenuItem(name: "Files", image: "folder", type: .files),
    MenuItem(name: "Tasks", image: "arrow.up.circle", type: .tasks),
  ]
  
  
  
//  @State private var selection: String?
  
  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        
        HStack {
          Text(server.name ?? "")
            .fontWeight(.medium)
            .lineLimit(2)
            .font(.title3)
            .multilineTextAlignment(.center)
            .padding()
        }
        .selectionDisabled()
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow).cornerRadius(16))
//        .background(.white.opacity(0.2))
        .cornerRadius(10)
//        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
        .tag(MenuItem(name: "title", image: "", type: .banner))
        .padding(.bottom, 16)
        
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
                  Text("🙂")
                    .font(.headline)
                  if user.status.contains(.admin) {
                    if user.status.contains(.idle) {
                      Text(user.name)
                        .foregroundStyle(.red.opacity(0.5))
                    }
                    else {
                      Text(user.name)
                        .foregroundStyle(.red)
                    }
                  }
                  else if user.status.contains(.idle) {
                    Text(user.name)
                      .opacity(0.5)
                  }
                  else {
                    Text(user.name)
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
        case .progress
          :
          EmptyView()
        case .chat:
          ChatView()
        case .news:
          NewsView()
        case .messageBoard:
          MessageBoardView()
        case .files:
          FilesView()
        case .tasks:
          EmptyView()
        case .user:
          if let selectionUserID = selection.userID {
            MessageView(userID: selectionUserID)
          }
        }
      }
    }
    .navigationTitle("")
    .onAppear {
      Task {
        await model.login(server: self.server, login: "", password: "", username: "bolt", iconID: 128)
      }
    }
    .onDisappear {
      Task {
        model.disconnect()
      }
    }
    .onChange(of: model.status) {
      if model.status == .disconnected {
        dismiss()
      }
    }
  }
}

//#Preview {
//  ServerView(server: Server(name: "", description: "", address: "", port: 0))
//}
