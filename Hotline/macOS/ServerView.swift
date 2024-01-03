import SwiftUI
import UniformTypeIdentifiers

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
  
  let server: Server?
  
  static var menuItems = [
    MenuItem(name: "Chat", image: "bubble", type: .chat),
    MenuItem(name: "News", image: "newspaper", type: .news, serverVersion: 150),
    MenuItem(name: "Board", image: "note.text", type: .messageBoard),
    MenuItem(name: "Files", image: "folder", type: .files),
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
  
  var navigationList: some View {
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
        
        if model.transfers.count > 0 {
          self.transfersSection
        }
        
        if model.users.count > 0 {
          self.usersSection
        }
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
              .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
              .opacity(user.isIdle ? 0.5 : 1.0)
          }
          else {
            Text("")
              .frame(width: 18)
          }
          
          if user.isAdmin {
            if user.isIdle {
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
          else if user.isIdle {
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
  
  var body: some View {
    NavigationSplitView {
      self.navigationList
        .frame(maxWidth: .infinity)
        .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 500)
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
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .news:
          NewsView()
            .navigationTitle(self.model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .messageBoard:
          MessageBoardView()
            .navigationTitle(self.model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .files:
          FilesView()
            .navigationTitle(self.model.serverTitle)
            .navigationSplitViewColumnWidth(min: 250, ideal: 500)
        case .tasks:
          EmptyView()
        case .user:
          if let selectionUserID = selection.userID {
            MessageView(userID: selectionUserID)
              .navigationTitle(self.model.serverTitle)
              .navigationSplitViewColumnWidth(min: 250, ideal: 500)
          }
        }
      }
    }
    .navigationTitle("")
    .onAppear {
      if let s = self.server {
        self.model.login(server: s, login: "", password: "", username: preferences.username, iconID: preferences.userIconID) { success in
          if !success {
            print("FAILED LOGIN??")
          }
          else {
            print("GETTING USER LIST????!")
            self.sendPreferences()
            self.model.getUserList()
            self.model.downloadBanner()
          }
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
