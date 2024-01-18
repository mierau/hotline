import SwiftUI

struct TrackerView: View {
  @Environment(Bookmarks.self) private var bookmarks: Bookmarks
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openWindow) private var openWindow
  @Environment(\.controlActiveState) private var controlActiveState
  
  @MainActor
  func refresh() async {
    
    // When a tracker is selected, refresh only that tracker.
    if
      let selectedItem = selection,
      let bookmark = selectedItem.bookmark,
      bookmark.type == .tracker {
      if !selectedItem.expanded {
        selectedItem.expanded = true
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
          server.expanded = true
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
  @State private var selection: TrackerItem? = nil
  
  @State private var scrollOffset: CGFloat = CGFloat.zero
  @State private var initialLoadComplete = false
  @State private var refreshing = false
  @State private var topBarOpacity: Double = 1.0
  @State private var connectVisible = false
  @State private var connectDismissed = true
  @State private var serverVisible = false
  
  @State private var trackerSheetPresented: Bool = false
  @State private var trackerName: String = ""
  @State private var trackerAddress: String = ""
  
  var trackerBookmarkSheet: some View {
    VStack(alignment: .leading) {
      Text("Type the address and name of a Hotline Tracker:")
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
      Form {
        Group {
          TextField(text: $trackerAddress) {
            Text("Address:")
          }
          TextField(text: $trackerName, prompt: Text("Optional")) {
            Text("Name:")
          }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
      }
    }
    .frame(width: 300)
    .fixedSize(horizontal: true, vertical: true)
    .padding()
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Add Tracker") {
          var displayName = trackerName.trimmingCharacters(in: .whitespacesAndNewlines)
          let (host, port) = Tracker.parseTrackerAddressAndPort(trackerAddress)
          
          if displayName.isEmpty {
            displayName = host
          }
          
          if !displayName.isEmpty && !host.isEmpty {
            if !host.isEmpty {
              let _ = bookmarks.add(Bookmark(type: .tracker, name: displayName, address: host, port: port))
              trackerSheetPresented = false
              trackerName = ""
              trackerAddress = ""
            }
          }
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          trackerSheetPresented = false
          trackerName = ""
          trackerAddress = ""
        }
      }
    }
  }
  
  var body: some View {
    List($servers, id: \.self, editActions: [.move], selection: $selection) { $item in
      TrackerItemView(item: item, depth: 0)
        .deleteDisabled(!item.editable)
        .moveDisabled(!item.editable)
        .tag(item)
    }
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .onDeleteCommand {
      if let sel = selection, let bookmark = sel.bookmark {
        let _ = bookmarks.delete(bookmark)
        if let i = self.servers.firstIndex(where: { $0.id == sel.id }) {
          self.servers.remove(at: i)
        }
        selection = nil
      }
    }
    .contextMenu(forSelectionType: TrackerItem.self) { items in
      if let item = items.first {
        if let server = item.server {
          Button {
            let _ = bookmarks.add(Bookmark(type: .server, name: server.name ?? server.address, address: server.address, port: server.port))
          } label: {
            Label("Bookmark", systemImage: "bookmark")
          }
        }
        
        if let address = item.displayAddress {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
          } label: {
            Label("Copy Address", systemImage: "doc.on.doc")
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
        openWindow(id: "server", value: server)
      }
      else if let bookmark = clickedItem.bookmark, bookmark.type == .server {
        let server = Server(name: bookmark.name, description: nil, address: bookmark.address, port: HotlinePorts.DefaultServerPort)
        openWindow(id: "server", value: server)
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
    .sheet(isPresented: $trackerSheetPresented) {
      trackerBookmarkSheet
    }
    .navigationTitle("Servers")
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Image("Hotline")
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .foregroundColor(Color(hex: 0xE10000))
          .frame(width: 9)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
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
        .help("Refresh Trackers")
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          trackerSheetPresented = true
        } label: {
          Label("Add Tracker", systemImage: "point.3.filled.connected.trianglepath.dotted")
        }
        .help("Add Tracker")
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          openWindow(id: "server")
        } label: {
          Label("Connect to Server", systemImage: "globe.americas.fill")
        }
        .help("Connect to Server")
      }
    }
    .task {
      guard let bookmarks = bookmarks.bookmarks else {
        return
      }
      // Add initial items to tracker list.
      var items: [TrackerItem] = []
      for bookmark in bookmarks {
        items.append(TrackerItem(bookmark: bookmark))
      }
      self.servers = items
    }
    .onChange(of: servers) {
      Task {
        saveBookmarks()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSNotification.BookmarkAdded)) { notification in
      guard let bookmarks = bookmarks.bookmarks, let userInfo = notification.userInfo else {
        return
      }
      
      if let i = userInfo["index"] as? Int, bookmarks.count > i {
        self.servers.insert(TrackerItem(bookmark: bookmarks[i]), at: i)
      }
    }
    .onOpenURL(perform: { url in
      if let s = Server(url: url) {
        openWindow(id: "server", value: s)
      }
    })
  }
  
  private func saveBookmarks() {
    var newBookmarks: [Bookmark] = []
    for server in self.servers {
      if let b = server.bookmark {
        newBookmarks.append(b)
      }
    }
    
    bookmarks.apply(newBookmarks)
  }
}

struct TrackerItemView: View {
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
        TrackerItemView(item: serverItem, depth: self.depth + 1)
          .tag(serverItem)
          .deleteDisabled(!serverItem.editable)
          .moveDisabled(!serverItem.editable)
      }
    }
  }
}

@Observable
class TrackerItem: Identifiable, Hashable {
  let id: UUID = UUID()
  let bookmark: Bookmark?
  let server: Server?
  
  var editable: Bool = true
  
  var servers: [TrackerItem]?
  
  var expanded: Bool = false
  var loading: Bool = false
  
  var displayAddress: String? {
    if let s = server {
      if s.port == HotlinePorts.DefaultServerPort {
        return s.address
      }
      else {
        return "\(s.address):\(s.port)"
      }
    }
    else if let b = bookmark {
      if b.port == HotlinePorts.DefaultServerPort {
        return b.address
      }
      else {
        return "\(b.address):\(b.port)"
      }
    }
    
    return nil
  }
  
  init(bookmark: Bookmark) {
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

    if let fetchedServers: [HotlineServer] = try? await client.fetchServers(address: bookmark.address, port: HotlinePorts.DefaultTrackerPort) {
      var newItems: [TrackerItem] = []

      for s in fetchedServers {
        if let serverName = s.name {
          let server = Server(name: serverName, description: s.description, address: s.address, port: Int(s.port), users: Int(s.users))
          let item = TrackerItem(server: server)
          item.editable = false
          newItems.append(item)
        }
      }

      self.servers = newItems
    }
    
    self.loading = false
  }

}

#Preview {
  TrackerView()
}
