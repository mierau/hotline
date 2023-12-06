import SwiftUI

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  @Environment(\.colorScheme) var colorScheme
  
  @State private var selectedServer: HotlineServer?
  
  func shouldDisplayDescription(server: HotlineServer) -> Bool {
    guard let name = server.name, let desc = server.description else {
      return false
    }
    
    return desc.count > 0 && desc != name && !desc.contains(/^-+/)
  }
  
  func connectionStatusToProgress(status: HotlineClientStatus) -> Double {
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
  
  var body: some View {
    @Bindable var config = appState
    @Bindable var client = hotline
    
    ScrollView {
      LazyVStack(alignment: .leading) {
        ForEach(tracker.servers) { server in
          VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
              Image(systemName: "globe.americas.fill").font(.title3)
              VStack(alignment: .leading) {
                Text(server.name!).font(.title3).fontWeight(.medium)
                if shouldDisplayDescription(server: server) {
                  Spacer()
                  Text(server.description!).opacity(0.4).font(.system(size: 16))
                }
                Spacer()
                Text("\(server.address)").opacity(0.2).font(.system(size: 13))
              }
              Spacer()
              Text("\(server.users)").opacity(0.2).font(.system(size: 16)).fontWeight(.medium)
            }
            if server == selectedServer {
              Spacer(minLength: 16)
              
              if hotline.server == server && hotline.connectionStatus != .disconnected {
                ProgressView("", value: connectionStatusToProgress(status: hotline.connectionStatus))
              }
              else {
                Button("Connect") {
                  hotline.connect(to: server)
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
            }
          }
          .multilineTextAlignment(.leading)
          .padding()
          .background(colorScheme == .dark ? Color(white: 0.1) : .white)
          .cornerRadius(20)
          .shadow(color: Color(white: 0.0, opacity: 0.1), radius: 16, x: 0, y: 10)
          .onTapGesture {
            withAnimation(.bouncy(duration: 0.25, extraBounce: 0.2)) {
              selectedServer = server
            }
          }
        }
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      }
    }
    .fullScreenCover(isPresented: Binding(get: { return hotline.connectionStatus == .loggedIn }, set: { _ in }), onDismiss: {
      hotline.disconnect()
    }) {
      ServerView()
    }
    .background(colorScheme == .dark ? .black : Color(white: 0.95))
    .frame(maxWidth: .infinity)
    .task {
      tracker.fetch()
    }
    .refreshable {
      await withCheckedContinuation { continuation in
        tracker.fetch() {
          continuation.resume()
        }
      }
    }
    .navigationTitle("Tracker")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  TrackerView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
    .environment(HotlineState())
  //    .modelContainer(for: Item.self, inMemory: true)
}
