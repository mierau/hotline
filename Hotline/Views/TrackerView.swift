import SwiftUI

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  @Environment(\.colorScheme) var colorScheme
  
  @State private var selectedServer: HotlineServer?
  @State var scrollOffset: CGFloat = CGFloat.zero
  
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
  
  func inverseLerp(lower: Double, upper: Double, v: Double) -> Double {
    return (v - lower) / (upper - lower)
  }
  
  var body: some View {
    @Bindable var config = appState
    @Bindable var client = hotline
    
    ZStack(alignment: .center) {
      VStack(alignment: .center) {
        ZStack(alignment: .top) {
          Image("Hotline")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(Color(hex: 0xE10000))
            .scaledToFit()
            .frame(width: 40.0, height: 40.0)
          HStack(alignment: .center) {
            Spacer()
            Button {
    //          hotline.disconnect()
            } label: {
              Text(Image(systemName: "point.3.connected.trianglepath.dotted"))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.primary)
                .font(.title2)
                .padding(.trailing, 16)
            }
          }
          .frame(height: 40.0)
        }
        .padding()
        .opacity(scrollOffset > 80 ? 0 : 1.0)
//        .padding(.top, 5)
        .opacity(inverseLerp(lower: -80, upper: 0, v: scrollOffset))
//        .opacity(inverseLerp(lower: 20, upper: 0, v: scrollOffset))
        
        Spacer()
      }
      ObservableScrollView(scrollOffset: $scrollOffset) {
        LazyVStack(alignment: .leading) {
          ForEach(tracker.servers) { server in
            VStack(alignment: .leading) {
              HStack(alignment: .firstTextBaseline) {
                Image(systemName: "globe.americas.fill").font(.title3)
                VStack(alignment: .leading) {
                  Text(server.name!).font(.title3).fontWeight(.medium)
                  if shouldDisplayDescription(server: server) {
                    Spacer()
                    Text(server.description!).opacity(0.5).font(.system(size: 16))
                  }
                  Spacer()
                  Text("\(server.address)").opacity(0.3).font(.system(size: 13))
                }
                Spacer()
                Text("\(server.users)").opacity(0.3).font(.system(size: 16)).fontWeight(.medium)
              }
              if server == selectedServer {
                Spacer(minLength: 16)
                
                if hotline.server == server && hotline.connectionStatus != .disconnected {
                  ProgressView(value: connectionStatusToProgress(status: hotline.connectionStatus))
                    .frame(minHeight: 10)
                    .accentColor(colorScheme == .dark ? .white : .black)
                }
                else {
                  Button("Connect") {
                    hotline.connect(to: server)
                  }
                  .bold()
                  .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
                  .frame(maxWidth: .infinity)
                  .foregroundColor(colorScheme == .dark ? .white : .black)
                  .background(
                    colorScheme == .dark ?
                    LinearGradient(gradient: Gradient(colors: [Color(white: 0.4), Color(white: 0.3)]), startPoint: .top, endPoint: .bottom)
                    :
                    LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(colorScheme == .dark ? 0.0 : 0.2)
                  )
                  .cornerRadius(10.0)
                }
              }
            }
            .multilineTextAlignment(.leading)
            .padding()
            .background(colorScheme == .dark ? Color(white: 0.12) : .white)
            .cornerRadius(16)
            .shadow(color: Color(white: 0.0, opacity: 0.1), radius: 16, x: 0, y: 10)
            .onTapGesture {
              withAnimation(.bouncy(duration: 0.25, extraBounce: 0.2)) {
                selectedServer = server
              }
            }
          }
          .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .padding(EdgeInsets(top: 75, leading: 0, bottom: 0, trailing: 0))
      }
      .refreshable {
        await withCheckedContinuation { continuation in
          tracker.fetch() {
            continuation.resume()
          }
        }
      }
      
    }
    .fullScreenCover(isPresented: Binding(get: { return hotline.connectionStatus == .loggedIn }, set: { _ in }), onDismiss: {
      hotline.disconnect()
    }) {
      ServerView()
    }
    .background(Color(uiColor: UIColor.systemGroupedBackground))
    .frame(maxWidth: .infinity)
    .task {
      tracker.fetch()
    }
  }
}

#Preview {
  TrackerView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
    .environment(HotlineState())
  //    .modelContainer(for: Item.self, inMemory: true)
}
