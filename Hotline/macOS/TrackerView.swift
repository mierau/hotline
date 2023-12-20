import SwiftUI

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
//  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.openWindow) private var openWindow
  
  private var client = HotlineTrackerClient()
  
  @MainActor
  func updateServers() async {
    let fetchedServers: [HotlineServer] = await self.client.fetchServers(address: "hltracker.com", port: Tracker.defaultPort)
    
    var newServers: [Server] = []
    
    for s in fetchedServers {
      if let serverName = s.name {
        newServers.append(Server(name: serverName, description: s.description, address: s.address, port: Int(s.port), users: Int(s.users)))
      }
    }
    
    self.servers = newServers
  }
  
//  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  
  //  @State private var tracker = Tracker(address: "hltracker.com", service: trackerService)
  
  @State private var servers: [Server] = []
//  @State private var selectedServer: Server?
  
  @State private var selection: Server.ID? = nil
  
  @State private var scrollOffset: CGFloat = CGFloat.zero
  @State private var initialLoadComplete = false
  @State private var refreshing = false
  @State private var topBarOpacity: Double = 1.0
  @State private var connectVisible = false
  @State private var connectDismissed = true
  @State private var serverVisible = false
  
  func shouldDisplayDescription(server: Server) -> Bool {
    guard let desc = server.description else {
      return false
    }
    
    return desc.count > 0 && desc != server.name
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
  
//  func updateServers() async {
    //    "hltracker.com"
    //    "tracker.preterhuman.net"
    //    "hotline.ubersoft.org"
    //    "tracked.nailbat.com"
    //    "hotline.duckdns.org"
    //    "tracked.agent79.org"
//    self.servers = await model.getServerList(tracker: "hltracker.com")
//  }
  
  var body: some View {
    //    ZStack(alignment: .center) {
    //      VStack(alignment: .center) {
    //        ZStack(alignment: .top) {
    //          HStack(alignment: .center) {
    //            Button {
    //              connectVisible = true
    //              connectDismissed = false
    //            } label: {
    //              Text(Image(systemName: "gearshape.fill"))
    //                .symbolRenderingMode(.hierarchical)
    //                .foregroundColor(.primary)
    //                .font(.title2)
    //                .padding(.leading, 16)
    //            }
    //            .sheet(isPresented: $connectVisible) {
    //              connectDismissed = true
    //            } content: {
    ////              TrackerConnectView()
    //            }
    //            Spacer()
    //          }
    //          .frame(height: 40.0)
    //          Image("Hotline")
    //            .resizable()
    //            .renderingMode(.template)
    //            .foregroundColor(Color(hex: 0xE10000))
    //            .scaledToFit()
    //            .frame(width: 40.0, height: 40.0)
    //          HStack(alignment: .center) {
    //            Spacer()
    //            Button {
    //              connectVisible = true
    //              connectDismissed = false
    //            } label: {
    //              Text(Image(systemName: "point.3.connected.trianglepath.dotted"))
    //                .symbolRenderingMode(.hierarchical)
    //                .foregroundColor(.primary)
    //                .font(.title2)
    //                .padding(.trailing, 16)
    //            }
    //            .sheet(isPresented: $connectVisible) {
    //              connectDismissed = true
    //            } content: {
    //              TrackerConnectView()
    //            }
    //          }
    //          .frame(height: 40.0)
    //        }
    //        .padding()
    //
    //        Spacer()
    //      }
    //      .opacity(inverseLerp(lower: -50, upper: 0, v: scrollOffset))
    //      .opacity(scrollOffset > 65 ? 0.0 : 1.0)
    //      .opacity(topBarOpacity)
    //      .zIndex(scrollOffset > 0 ? 1 : 3)
    Table(of: Server.self, selection: $selection) {
      TableColumn("Name") { server in
        HStack {
          Text(Image(systemName: "globe.americas.fill"))
          Text(server.name!)
        }
      }
      .width(min: 80, ideal: 150)
      
      TableColumn("Status") { server in
        if server.users > 0 {
          Text("\(server.users)")
        }
        else {
          Text("")
        }

      }
      .width(50)
      .alignment(.center)
      
      TableColumn("Description") { server in
        Text(server.description ?? "")
      }
    } rows: {
      ForEach(self.servers) { server in
        TableRow(server)
      }
    }
    .contextMenu(forSelectionType: Server.ID.self) { items in
        // ...
    } primaryAction: { items in
      guard
        let selectionID = items.first,
        let selectedServer = self.servers.first(where: { $0.id == selectionID })
      else {
        return
      }
      
      openWindow(value: selectedServer)
    }
    .navigationTitle("Servers")
    .task {
      await updateServers()
      initialLoadComplete = true
    }
  }
}

#Preview {
  TrackerView()
}
