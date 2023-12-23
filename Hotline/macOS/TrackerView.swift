import SwiftUI

enum TrackerBookmarkType: String {
  case tracker = "tracker"
  case server = "server"
}

struct TrackerBookmark {
  let type: TrackerBookmarkType
  let name: String
  let address: String
}

@Observable
class TrackerItem: Identifiable, Hashable {
  @ObservationIgnored let id: UUID = UUID()
  let bookmark: TrackerBookmark?
  let server: Server?
  
  var servers: [TrackerItem]?
  
  var expanded: Bool = false
  var loading: Bool = false
  
  init(bookmark: TrackerBookmark) {
    self.bookmark = bookmark
    self.server = nil
    self.servers = nil
    
    if bookmark.type == .tracker {
      self.servers = []
    }
  }
  
  init(server: Server) {
    self.server = server
    self.servers = nil
    self.bookmark = nil
  }
  
  static func == (lhs: TrackerItem, rhs: TrackerItem) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  @MainActor
  func loadServers() async {
    guard
      let bookmark = self.bookmark,
      bookmark.type == .tracker
    else {
      self.loading = false
      return
    }
    
    let client = HotlineTrackerClient()
    
    
    self.loading = true
//    self.servers = []

    let fetchedServers: [HotlineServer] = await client.fetchServers(address: bookmark.address, port: Tracker.defaultPort)
    
    client.disconnect()

    var newItems: [TrackerItem] = []

    for s in fetchedServers {
      if let serverName = s.name {
        
        let server = Server(name: serverName, description: s.description, address: s.address, port: Int(s.port), users: Int(s.users))
//        let item = TrackerItem(server: server)
        
        newItems.append(TrackerItem(server: server))
      }
    }

    self.servers = newItems
    
    self.loading = false
  }

}

struct TrackerItemView: View {
//  @Environment(Hotline.self) private var model: Hotline
  
  @State var expanded = false
  @State var loading = false
  
  var item: TrackerItem
  let depth: Int
  
  var body: some View {
    HStack {
      if
        let bookmark = item.bookmark,
        bookmark.type == .tracker {
        Button {
          item.expanded.toggle()
        } label: {
          Text(Image(systemName: item.expanded ? "chevron.down" : "chevron.right"))
            .bold()
            .font(.system(size: 10))
            .opacity(0.5)
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: 10)
        .padding(.leading, 4)
      }
      else {
        HStack {
          if let bookmark = item.bookmark, bookmark.type == .server {
            Image(systemName: "bookmark.fill")
              .resizable()
              .renderingMode(.template)
              .aspectRatio(contentMode: .fit)
              .frame(width: 11, height: 11, alignment: .center)
              .opacity(0.5)
          }
        }
        .frame(width: 10)
        .padding(.leading, 4)
      }
      
      HStack(alignment: .center) {
        if let bookmark = item.bookmark {
          switch bookmark.type {
          case .tracker:
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
          case .server:
            Image(systemName: "globe.americas.fill")
          }
        }
        else if let _ = item.server {
          Image(systemName: "globe.americas.fill")
        }
      }
      .frame(width: 15)
      
      if let bookmark = item.bookmark {
        switch bookmark.type {
        case .tracker:
          Text(bookmark.name).bold().lineLimit(1).truncationMode(.tail)
        case .server:
          Text(bookmark.name).lineLimit(1).truncationMode(.tail)
        }
      }
      else if let server = item.server {
        Text(server.name ?? server.address).lineLimit(1)
        
        if let description = server.description, !description.isEmpty {
          Text(description).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        }
      }
      
      if
        let server = item.server,
        server.users > 0 {
        Spacer()
        Text("\(server.users) \(Image(systemName: "person.fill"))")
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .padding([.leading, .trailing], 4)
          .padding([.top, .bottom], 2)
//          .background(Capsule(style: .circular).stroke(.secondary, lineWidth: 1))
//          .opacity(0.5)
      }
      else if
        let bookmark = item.bookmark,
        bookmark.type == .tracker {
        if item.loading {
          ProgressView()
            .padding([.leading, .trailing], 2)
            .controlSize(.small)
        }
        Spacer()
      }
      else {
        Spacer()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.leading, CGFloat(depth * (12 + 10)))
    .onChange(of: item.expanded) {
      loading = false
      
      if
        item.expanded,
        let bookmark = item.bookmark,
        bookmark.type == .tracker {
        Task {
          await item.loadServers()
        }
      }
    }
    
    if
      item.expanded,
      let servers = item.servers {
      ForEach(servers, id: \.self) { serverItem in
        TrackerItemView(item: serverItem, depth: self.depth + 1).tag(serverItem)
      }
    }
  }
}

struct TrackerView: View {
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.openWindow) private var openWindow
  
//  @AppStorage("servers", store: .standard)
  var bookmarks: [TrackerBookmark] = [
    TrackerBookmark(type: .server, name: "RetroMac", address: "82.32.130.173"),
    TrackerBookmark(type: .server, name: "System 7 Today", address: "158.174.146.146"),
    TrackerBookmark(type: .server, name: "Bob Kiwi's House", address: "73.132.92.104"),
    TrackerBookmark(type: .tracker, name: "Featured Servers", address: "hltracker.com"),
    TrackerBookmark(type: .tracker, name: "Agent79", address: "tracked.agent79.org"),
    TrackerBookmark(type: .tracker, name: "Preterhuman", address: "tracker.preterhuman.net"),
    
    //    "hltracker.com"
    //    "tracker.preterhuman.net"
    //    "hotline.ubersoft.org"
    //    "tracked.nailbat.com"
    //    "hotline.duckdns.org"
    //    "tracked.agent79.org"

  ]
  
  @MainActor
  func refresh() async {
    
    // When a tracker is selected, refresh only that tracker.
    if
      let selectedItem = selection,
      let bookmark = selectedItem.bookmark,
      bookmark.type == .tracker {
      if !selectedItem.expanded {
        selectedItem.expanded.toggle()
      }
      else {
        await selectedItem.loadServers()
      }
      return
    }
    
    // Otherwise refresh/expand all trackers.
    for server in self.servers {
      if
        let bookmark = server.bookmark,
        bookmark.type == .tracker {
        if !server.expanded {
          server.expanded.toggle()
        }
        else {
          Task {
            await server.loadServers()
          }
        }
      }
    }
  }
  
  @State private var servers: [TrackerItem] = []
//  @State private var selectedServer: Server?
  
  @State private var selection: TrackerItem? = nil
  
  @State private var scrollOffset: CGFloat = CGFloat.zero
  @State private var initialLoadComplete = false
  @State private var refreshing = false
  @State private var topBarOpacity: Double = 1.0
  @State private var connectVisible = false
  @State private var connectDismissed = true
  @State private var serverVisible = false
  
  var body: some View {
    List(self.servers, id: \.self, selection: $selection) { item in
      TrackerItemView(item: item, depth: 0)
        .tag(item)
    }
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .contextMenu(forSelectionType: TrackerItem.self) { items in
      if let item = items.first {
        if let server = item.server {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(server.address, forType: .string)
          } label: {
            Label("Copy Server Address", systemImage: "doc.on.doc")
          }
        }
      }
    } primaryAction: { items in
      guard let clickedItem = items.first else {
        return
      }
      
      if
        let bookmark = clickedItem.bookmark,
        bookmark.type == .tracker {
        clickedItem.expanded.toggle()
      }
      else if let server = clickedItem.server {
        openWindow(value: server)
      }
      else if
        let bookmark = clickedItem.bookmark,
        bookmark.type == .server {
        let server = Server(name: bookmark.name, description: nil, address: bookmark.address, port: Server.defaultPort)
        openWindow(value: server)
      }
    }
    .onKeyPress(.rightArrow) {
      if
        let selectedItem = selection,
        let bookmark = selectedItem.bookmark,
        bookmark.type == .tracker {
        selectedItem.expanded = true
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.leftArrow) {
      if
        let selectedItem = selection,
        let bookmark = selectedItem.bookmark,
        bookmark.type == .tracker {
        selectedItem.expanded = false
        return .handled
      }
      return .ignored
    }
    .navigationTitle("Servers")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task {
            initialLoadComplete = false
            await refresh()
            initialLoadComplete = true
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help("Refresh")
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
        } label: {
          Label("Add Tracker", systemImage: "point.3.filled.connected.trianglepath.dotted")
        }
        .help("Add Tracker")
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
        } label: {
          Label("Add Server", systemImage: "plus")
        }
        .help("Add Server")
      }
    }
    .onAppear {
      // Add initial items to tracker list.
      var items: [TrackerItem] = []
      for bookmark in self.bookmarks {
        items.append(TrackerItem(bookmark: bookmark))
      }
      self.servers = items
    }
  }
}

#Preview {
  TrackerView()
}
