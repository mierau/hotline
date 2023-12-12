import SwiftUI

struct ServerView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  
  enum Tab {
    case chat, users, news, messageBoard, files
  }
  
  var body: some View {
    TabView {
      ChatView()
        .tabItem {
          Image(systemName: "bubble")
        }
        .tag(Tab.chat)
      
      UsersView()
        .tabItem {
          Image(systemName: "person.2")
        }
        .tag(Tab.users)
      
      if let v = model.serverVersion, v >= 150 {
        NewsView()
          .tabItem {
            Image(systemName: "newspaper")
          }
          .tag(Tab.news)
      }
      
      MessageBoardView()
        .tabItem {
          Image(systemName: "book.closed")
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
}
