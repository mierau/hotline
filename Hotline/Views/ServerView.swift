import SwiftUI

struct ServerView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
    
  var body: some View {
    @Bindable var config = appState
    
    TabView {
      NavigationView {
        ChatView()
          .navigationTitle(hotline.server?.name ?? "Hotline")
          .navigationBarTitleDisplayMode(.inline)
          .navigationBarItems(
            leading: Button(action: {
              appState.presentTracker()
            }) {
              Image(systemName: "globe.americas.fill") // Hamburger icon or similar
                .imageScale(.large)
            }
          )
//          .toolbarBackground(.visible, for: .navigationBar)
//          .toolbarBackground(.red, for: .navigationBar)
      }
      .tabItem {
        Image(systemName: "message")
      }
      
      NavigationView {
        UserListView()
          .navigationTitle("User List")
          .navigationBarTitleDisplayMode(.inline)
      }
      .tabItem {
        Image(systemName: "person.fill")
      }
      
      Text("News")
        .tabItem {
          Image(systemName: "newspaper")
        }
      
      NavigationView {
        MessageBoardView()
          .navigationTitle("Message Board")
          .navigationBarTitleDisplayMode(.inline)
      }
      .tabItem {
        Image(systemName: "pin")
      }
      
      NavigationView {
        FilesView()
          .navigationTitle("Files")
          .navigationBarTitleDisplayMode(.inline)
      }
      .tabItem {
        Image(systemName: "folder")
      }
    }
//      .sheet(isPresented: Binding(get: { hotline.connectionStatus != .loggedIn }, set: { _ in })) {
//        TrackerView()
//      }
  }
}

#Preview {
  ServerView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
}
