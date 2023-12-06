import SwiftUI

struct ServerView: View {
  @Environment(HotlineClient.self) private var hotline
  @Environment(\.colorScheme) var colorScheme
  
  func connectionStatusTitle(status: HotlineClientStatus) -> String {
    switch(status) {
    case .disconnected:
      return "Disconnected"
    case .connecting:
      return "Connecting"
    case .connected:
      return "Connected"
    case .loggingIn:
      return "Logging In"
    case .loggedIn:
      return "Logged In"
    }
  }
  
  func connectionProgress(status: HotlineClientStatus) -> Double {
    return Double(status.rawValue) / Double(HotlineClientStatus.loggedIn.rawValue)
  }
  
  enum Tab {
    case chat, users, news, messageBoard, files
  }
  
  var body: some View {
    TabView {
      ChatView()
        .tabItem {
          Image(systemName: "message")
        }
        .tag(Tab.chat)
      
      UserListView()
        .tabItem {
          Image(systemName: "person.fill")
        }
        .tag(Tab.users)
      
      NewsView()
        .tabItem {
          Image(systemName: "newspaper")
        }
        .tag(Tab.news)
      
      MessageBoardView()
        .tabItem {
          Image(systemName: "pin")
        }
        .tag(Tab.messageBoard)
      
      FilesView()
        .tabItem {
          Image(systemName: "folder").tint(.black)
        }
        .tag(Tab.files)
    }
    .accentColor(colorScheme == .dark ? .white : .black)
  }
}

#Preview {
  ServerView()
    .environment(HotlineClient())
}
