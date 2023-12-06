import SwiftUI

struct ServerView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  let server: HotlineServer
  
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
  
  var body: some View {
    @Bindable var config = appState
    
    NavigationStack {
      if hotline.connectionStatus != .loggedIn {
        VStack {
          Spacer()
          VStack(alignment: .center) {
            Text("🌎").font(.largeTitle)
            Text(server.name!).font(.title3).fontWeight(.medium)
            Text(server.description!).opacity(0.6).font(.title3)
            Text(server.address).opacity(0.6).font(.title3)
          }
          Spacer()
          HStack(alignment: .center) {
            if hotline.connectionStatus == .disconnected {
              ProgressView(connectionStatusTitle(status: hotline.connectionStatus), value: connectionProgress(status: hotline.connectionStatus))
              Button("Connect") {
                hotline.connect(to: server)
  //              config.dismissTracker()
              }
              .bold()
              .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
              .frame(maxWidth: .infinity)
              .foregroundColor(.black)
              .background(LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom))
              .overlay(
                RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(0.4)
              )
              .cornerRadius(10.0)
            }
            else {
              ProgressView("", value: Double(hotline.connectionStatus.rawValue / HotlineClientStatus.loggedIn.rawValue))
            }
          }
        }
        .padding()
      }
      else {
        TabView {
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
            .tabItem {
              Image(systemName: "message")
            }
          
          UserListView()
            .navigationTitle("User List")
            .navigationBarTitleDisplayMode(.inline)
            .tabItem {
              Image(systemName: "person.fill")
            }
          
          Text("News")
            .tabItem {
              Image(systemName: "newspaper")
            }
          
          MessageBoardView()
            .navigationTitle("Message Board")
            .navigationBarTitleDisplayMode(.inline)
            .tabItem {
              Image(systemName: "pin")
            }
          
          FilesView()
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .tabItem {
              Image(systemName: "folder").tint(.black)
            }
        }
        .accentColor(.black)
      }
      
      //      .sheet(isPresented: Binding(get: { hotline.connectionStatus != .loggedIn }, set: { _ in })) {
      //        TrackerView()
      //      }
    }
  }
}

#Preview {
  ServerView(server: HotlineServer(address: "192.168.1.1", port: 5050, users: 5, name: "Ye Olde Server", description: "This is a server"))
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
    .environment(HotlineState())
}
