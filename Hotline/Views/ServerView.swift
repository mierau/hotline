import SwiftUI

struct ServerView: View {
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  @State private var isTrackerVisible = false
  
  var body: some View {
    TabView {
      NavigationView {
        ChatView()
          .navigationTitle("Badmoon")
          .navigationBarItems(
            leading: Button(action: {
              withAnimation {
                isTrackerVisible.toggle()
              }
            }) {
              Image(systemName: "line.horizontal.3") // Hamburger icon or similar
                .imageScale(.large)
            }
          )
          .toolbarBackground(.visible, for: .navigationBar)
          .toolbarBackground(.red, for: .navigationBar)
      }
      .navigationBarTitleDisplayMode(.inline)
      .tabItem {
        Image(systemName: "message")
      }
      
      Text("Users")
        .tabItem {
          Image(systemName: "person.fill")
        }
      
      Text("News")
        .tabItem {
          Image(systemName: "newspaper")
        }
      
      Text("Files")
        .tabItem {
          Image(systemName: "folder")
        }
      
      Text("Transfers")
        .tabItem {
          Image(systemName: "network")
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
