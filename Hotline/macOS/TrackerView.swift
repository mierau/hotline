import SwiftUI
import SwiftData
import Foundation
import UniformTypeIdentifiers

enum TrackerSelection: Hashable {
  case bookmark(Bookmark)
  case bookmarkServer(BookmarkServer)
  
  var server: Server? {
    switch self {
    case .bookmark(let b): return b.server
    case .bookmarkServer(let t): return t.server
    }
  }
}

struct TrackerView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openWindow) private var openWindow
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.modelContext) private var modelContext
  
  @State private var refreshing = false
  @State private var trackerSheetPresented: Bool = false
  @State private var trackerSheetBookmark: Bookmark? = nil
  @State private var serverSheetBookmark: Bookmark? = nil
  @State private var attemptedPrepopulate: Bool = false
  @State private var fileDropActive = false
  @State private var bookmarkExportActive = false
  @State private var bookmarkExport: BookmarkDocument? = nil
  @State private var expandedTrackers: Set<Bookmark> = []
  @State private var trackerServers: [Bookmark: [BookmarkServer]] = [:]
  @State private var loadingTrackers: Set<Bookmark> = []
  @State private var fetchTasks: [Bookmark: Task<Void, Never>] = [:]
  @State private var searchText: String = ""
  @State private var isSearching = false

  @Query(sort: \Bookmark.order) private var bookmarks: [Bookmark]
  @Binding var selection: TrackerSelection?

  private var filteredBookmarks: [Bookmark] {
    guard !self.searchText.isEmpty else {
      return self.bookmarks
    }

    let searchWords = self.searchText.lowercased().split(separator: " ").map(String.init)

    return self.bookmarks.filter { bookmark in
      // Always show tracker bookmarks (filter only their servers)
      if bookmark.type == .tracker {
        return true
      }

      // Filter server bookmarks by search text
      return self.bookmarkMatchesSearch(bookmark, searchWords: searchWords)
    }
  }

  private func bookmarkMatchesSearch(_ bookmark: Bookmark, searchWords: [String]) -> Bool {
    let searchableText = "\(bookmark.name) \(bookmark.address)".lowercased()

    // All search words must match
    return searchWords.allSatisfy { word in
      searchableText.contains(word)
    }
  }

  private func filteredServers(for bookmark: Bookmark) -> [BookmarkServer] {
    let servers = self.trackerServers[bookmark] ?? []
    print("TrackerView.filteredServers: Looking up servers for \(bookmark.name), found \(servers.count) servers")

    guard !self.searchText.isEmpty else {
      return servers
    }

    let searchWords = self.searchText.lowercased().split(separator: " ").map(String.init)

    return servers.filter { server in
      let searchableText = "\(server.name ?? "") \(server.address) \(server.description ?? "")".lowercased()

      // All search words must match
      return searchWords.allSatisfy { word in
        searchableText.contains(word)
      }
    }
  }

  var body: some View {
    List(selection: $selection) {
      ForEach(filteredBookmarks, id: \.self) { bookmark in
        TrackerItemView(
          bookmark: bookmark,
          isExpanded: self.expandedTrackers.contains(bookmark),
          isLoading: self.loadingTrackers.contains(bookmark),
          count: self.trackerServers[bookmark]?.count ?? 0
        ) {
          self.toggleExpanded(for: bookmark)
        }
        .tag(TrackerSelection.bookmark(bookmark))

        if bookmark.type == .tracker && self.expandedTrackers.contains(bookmark) {
          ForEach(self.filteredServers(for: bookmark), id: \.self) { trackedServer in
            TrackerBookmarkServerView(server: trackedServer)
              .moveDisabled(true)
              .deleteDisabled(true)
              .tag(TrackerSelection.bookmarkServer(trackedServer))
          }
        }
      }
      .onMove { movedIndexes, destinationIndex in
        Bookmark.move(movedIndexes, to: destinationIndex, context: modelContext)
      }
      .onDelete { deletedIndexes in
        Bookmark.delete(at: deletedIndexes, context: modelContext)
      }
    }
    .onDeleteCommand {
      switch self.selection {
      case .bookmark(let bookmark):
        Bookmark.delete(bookmark, context: modelContext)
      default:
        break
      }
      
//      if let bookmark = selection,
//         bookmark.type != .temporary {
//        Bookmark.delete(bookmark, context: modelContext)
//      }
    }
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .onChange(of: AppState.shared.cloudKitReady) {
      if attemptedPrepopulate {
        print("Tracker: Already attempted to prepopulate bookmarks")
        return
      }
      
      print("Tracker: Prepopulating bookmarks")
      
      attemptedPrepopulate = true
      
      // Make sure default bookmarks are there when empty.
      Bookmark.populateDefaults(context: modelContext)
    }
    .onAppear {
//      Bookmark.deleteAll(context: modelContext)
    }
    .contextMenu(forSelectionType: TrackerSelection.self) { items in
      if let item = items.first {
        switch item {
        case .bookmark(let bookmark):
          self.bookmarkContextMenu(bookmark)
        case .bookmarkServer(let server):
          self.bookmarkServerContextMenu(server)
        }
      }
    } primaryAction: { items in
      guard let clickedItem = items.first else {
        return
      }
      
      switch clickedItem {
      case .bookmark(let bookmark):
        if bookmark.type == .server {
          if let s = bookmark.server {
            openWindow(id: "server", value: s)
          }
        }
        else if bookmark.type == .tracker {
          if NSEvent.modifierFlags.contains(.option) {
            trackerSheetBookmark = bookmark
          }
          else {
            self.toggleExpanded(for: bookmark)
          }
        }
        
      case .bookmarkServer(let bookmarkServer):
        openWindow(id: "server", value: bookmarkServer.server)
      }
      
//      if clickedItem.type == .tracker {
//        if NSEvent.modifierFlags.contains(.option) {
//          trackerSheetBookmark = clickedItem
//        }
//        else {
//          clickedItem.expanded.toggle()
//        }
//      }
//      else if let server = clickedItem.server {
//        openWindow(id: "server", value: server)
//      }
    }
    .fileExporter(isPresented: $bookmarkExportActive, document: bookmarkExport, contentTypes: [.data], defaultFilename: "\(bookmarkExport?.bookmark.name ?? "Hotline Bookmark").hlbm", onCompletion: { result in
      switch result {
      case .success(let fileURL):
        print("Hotline Bookmark: Successfully exported:", fileURL)
      case .failure(let err):
        print("Hotline Bookmark: Failed to export:", err)
      }
      
      bookmarkExport = nil
      bookmarkExportActive = false
    }, onCancellation: {})
    .onKeyPress(.rightArrow) {
      switch self.selection {
      case .bookmark(let bookmark):
        if bookmark.type == .tracker {
          self.expandedTrackers.insert(bookmark)
          return .handled
        }
      default:
        break
      }
      
//      if
//        let bookmark = selection,
//        bookmark.type == .tracker {
//        bookmark.expanded = true
//        return .handled
//      }
      return .ignored
    }
    .onKeyPress(.leftArrow) {
      switch self.selection {
      case .bookmark(let bookmark):
        if bookmark.type == .tracker {
          self.expandedTrackers.remove(bookmark)
          return .handled
        }
      default:
        break
      }
      
//      if
//        let bookmark = selection,
//        bookmark.type == .tracker {
//        bookmark.expanded = false
//        return .handled
//      }
      return .ignored
    }
    .onDrop(of: [UTType.fileURL], isTargeted: $fileDropActive) { providers, dropPoint in
      for provider in providers {
        let _ = provider.loadDataRepresentation(for: UTType.fileURL) { dataRepresentation, err in
          // HOTLINE CREATOR CODE: 1213484099
          // HOTLINE BOOKMARK TYPE CODE: 1213489773
          
          if let filePathData = dataRepresentation,
             let filePath = String(data: filePathData, encoding: .utf8),
             let fileURL = URL(string: filePath) {
            
            print("Hotline Bookmark: Dropped from ", fileURL.path(percentEncoded: false))
            
            DispatchQueue.main.async {
              if let newBookmark = Bookmark(fileURL: fileURL) {
                print("Hotline Bookmark: Added bookmark.")
                Bookmark.add(newBookmark, context: modelContext)
              }
              else {
                print("Hotline Bookmark: Failed to parse.")
              }
            }
          }
        }
      }
      
      return true
    }
    .sheet(item: $trackerSheetBookmark) { item in
      TrackerBookmarkSheet(item)
    }
    .sheet(isPresented: $trackerSheetPresented) {
      TrackerBookmarkSheet()
    }
    .sheet(item: $serverSheetBookmark) { item in
      ServerBookmarkSheet(item)
    }
    .navigationTitle("Servers")
    .toolbar {
      if #available(macOS 26.0, *) {
        ToolbarItem(placement: .navigation) {
          self.hotlineLogoImage
        }
        .sharedBackgroundVisibility(.hidden)
      }
      else {
        ToolbarItem(placement: .navigation) {
          self.hotlineLogoImage
        }
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          self.refreshing = true
          self.refresh()
          self.refreshing = false
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(refreshing)
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
    .onOpenURL(perform: { url in
      if let s = Server(url: url) {
        openWindow(id: "server", value: s)
      }
    })
    .searchable(text: $searchText, isPresented: $isSearching, placement: .automatic, prompt: "Search")
    .background(Button("", action: { isSearching = true }).keyboardShortcut("f").hidden())
  }
  
  private var hotlineLogoImage: some View {
    Image("Hotline")
      .resizable()
      .renderingMode(.template)
      .scaledToFit()
      .foregroundColor(Color(hex: 0xE10000))
      .frame(width: 9)
      .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
  }
  
  @ViewBuilder
  func bookmarkServerContextMenu(_ server: BookmarkServer) -> some View {
    Button {
      let newBookmark = Bookmark(type: .server, name: server.name ?? server.address, address: server.address, port: server.port, login: nil, password: nil)
      Bookmark.add(newBookmark, context: modelContext)
    } label: {
      Label("Bookmark", systemImage: "bookmark")
    }
    
    Divider()
    
    Button {
      NSPasteboard.general.clearContents()
      let displayAddress = server.port == HotlinePorts.DefaultServerPort ?
      server.address : "\(server.address):\(server.port)"
      NSPasteboard.general.setString(displayAddress, forType: .string)
    } label: {
      Label("Copy Address", systemImage: "doc.on.doc")
    }
  }
  
  @ViewBuilder
  func bookmarkContextMenu(_ bookmark: Bookmark) -> some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(bookmark.displayAddress, forType: .string)
    } label: {
      Label("Copy Address", systemImage: "doc.on.doc")
    }

    Divider()

    if bookmark.type == .tracker {
      Button {
        trackerSheetBookmark = bookmark
      } label: {
        Label("Edit Tracker...", systemImage: "pencil")
      }
    }

    if bookmark.type == .server {
      Button {
        serverSheetBookmark = bookmark
      } label: {
        Label("Edit Bookmark...", systemImage: "pencil")
      }

      Button {
        bookmarkExport = BookmarkDocument(bookmark: bookmark)
        bookmarkExportActive = true
      } label: {
        Label("Export Bookmark...", systemImage: "square.and.arrow.down")
      }
    }

    Divider()

    Button {
      Bookmark.delete(bookmark, context: modelContext)
    } label: {
      Label(bookmark.type == .tracker ? "Delete Tracker" : "Delete Bookmark", systemImage: "trash")
    }
  }

  
  func refresh() {
    // When a tracker is selected, refresh only that tracker.
    if let trackerSelection = self.selection {
      switch trackerSelection {
      case .bookmark(let bookmark):
        if bookmark.type == .tracker {
          if self.expandedTrackers.contains(bookmark) {
            // Already expanded, cancel old fetch and start new one
            self.fetchTasks[bookmark]?.cancel()
            let task = Task {
              await self.fetchServers(for: bookmark)
            }
            self.fetchTasks[bookmark] = task
          } else {
            // Not expanded, expand it (which also fetches)
            self.setExpanded(true, for: bookmark)
          }
          return
        }
        break
      default:
        break
      }
    }

    // Otherwise refresh/expand all trackers.
    for bookmark in self.bookmarks {
      if bookmark.type == .tracker {
        if self.expandedTrackers.contains(bookmark) {
          // Already expanded, cancel old fetch and start new one
          self.fetchTasks[bookmark]?.cancel()
          let task = Task {
            await self.fetchServers(for: bookmark)
          }
          self.fetchTasks[bookmark] = task
        } else {
          // Not expanded, expand it (which also fetches)
          self.setExpanded(true, for: bookmark)
        }
      }
    }
  }
  
  func toggleExpanded(for bookmark: Bookmark) {
    guard bookmark.type == .tracker else { return }

    if self.expandedTrackers.contains(bookmark) {
      // Collapse: cancel ongoing fetch and clear data
      self.fetchTasks[bookmark]?.cancel()
      self.fetchTasks[bookmark] = nil
      self.expandedTrackers.remove(bookmark)
      self.trackerServers[bookmark] = nil
      self.loadingTrackers.remove(bookmark)
    } else {
      // Expand: start fetch task
      self.expandedTrackers.insert(bookmark)
      let task = Task {
        await self.fetchServers(for: bookmark)
      }
      self.fetchTasks[bookmark] = task
    }
  }

  func setExpanded(_ expanded: Bool, for bookmark: Bookmark) {
    guard bookmark.type == .tracker else { return }

    if expanded && !self.expandedTrackers.contains(bookmark) {
      self.expandedTrackers.insert(bookmark)
      let task = Task {
        await self.fetchServers(for: bookmark)
      }
      self.fetchTasks[bookmark] = task
    } else if !expanded && self.expandedTrackers.contains(bookmark) {
      // Cancel ongoing fetch and clear data
      self.fetchTasks[bookmark]?.cancel()
      self.fetchTasks[bookmark] = nil
      self.expandedTrackers.remove(bookmark)
      self.trackerServers[bookmark] = nil
      self.loadingTrackers.remove(bookmark)
    }
  }

  private func fetchServers(for bookmark: Bookmark) async {
    print("TrackerView.fetchServers: Starting fetch for bookmark: \(bookmark.name)")
    self.loadingTrackers.insert(bookmark)
    let servers = await bookmark.fetchServers()
    print("TrackerView.fetchServers: Got \(servers.count) servers from bookmark.fetchServers()")
    await MainActor.run {
      print("TrackerView.fetchServers: Assigning \(servers.count) servers to trackerServers[\(bookmark.name)]")
      self.trackerServers[bookmark] = servers
      self.loadingTrackers.remove(bookmark)
      self.fetchTasks[bookmark] = nil  // Clean up completed task
      print("TrackerView.fetchServers: trackerServers now has \(self.trackerServers.count) entries")
      print("TrackerView.fetchServers: Verification - trackerServers[\(bookmark.name)] now has \(self.trackerServers[bookmark]?.count ?? -1) servers")
    }
  }
}

struct TrackerBookmarkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  
  @State private var bookmark: Bookmark? = nil
  @State private var trackerAddress: String = ""
  @State private var trackerName: String = ""
  
  init() {
    
  }
  
  init(_ editingBookmark: Bookmark) {
    _bookmark = .init(initialValue: editingBookmark)
    _trackerAddress = .init(initialValue: editingBookmark.displayAddress)
    _trackerName = .init(initialValue: editingBookmark.name)
  }
  
  var body: some View {
    VStack(alignment: .leading) {
      if self.bookmark == nil {
        Text("Type the address and name of a Hotline Tracker:")
          .foregroundStyle(.secondary)
          .padding(.bottom, 8)
      }
      
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
        Button {
          self.saveTracker()
        } label: {
          if self.bookmark != nil {
            Text("Save Tracker")
          }
          else {
            Text("Add Tracker")
          }
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.trackerName = ""
          self.trackerAddress = ""
          
          self.dismiss()
        }
      }
    }
  }
  
  private func saveTracker() {
    var displayName = trackerName.trimmingCharacters(in: .whitespacesAndNewlines)
    let (host, port) = Tracker.parseTrackerAddressAndPort(trackerAddress)
    
    if displayName.isEmpty {
      displayName = host
    }
    
    if !displayName.isEmpty && !host.isEmpty {
      if !host.isEmpty {
        if self.bookmark != nil {
          // We're editing an existing bookmark.
          self.bookmark?.name = displayName
          self.bookmark?.address = host
          self.bookmark?.port = port
        }
        else {
          // We're creating a new bookmark.
          let newBookmark = Bookmark(type: .tracker, name: displayName, address: host, port: port)
          Bookmark.add(newBookmark, context: modelContext)
        }
        
        self.trackerName = ""
        self.trackerAddress = ""
        
        self.dismiss()
      }
    }
  }
}

struct ServerBookmarkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var bookmark: Bookmark
  @State private var serverName: String = ""
  @State private var serverAddress: String = ""
  @State private var serverLogin: String = ""
  @State private var serverPassword: String = ""

  init(_ editingBookmark: Bookmark) {
    _bookmark = .init(initialValue: editingBookmark)
    _serverName = .init(initialValue: editingBookmark.name)
    _serverAddress = .init(initialValue: editingBookmark.displayAddress)
    _serverLogin = .init(initialValue: editingBookmark.login ?? "")
    _serverPassword = .init(initialValue: editingBookmark.password ?? "")
  }

  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Group {
          TextField(text: $serverName) {
            Text("Name:")
          }
          .padding(.bottom)
          
          TextField(text: $serverAddress) {
            Text("Address:")
          }
          TextField(text: $serverLogin, prompt: Text("Optional")) {
            Text("Login:")
          }
          SecureField(text: $serverPassword, prompt: Text("Optional")) {
            Text("Password:")
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
        Button("Save Bookmark") {
          let displayName = self.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
          let (host, port) = Server.parseServerAddressAndPort(self.serverAddress)
          let login = self.serverLogin.trimmingCharacters(in: .whitespacesAndNewlines)
          let password = self.serverPassword

          if !displayName.isEmpty && !host.isEmpty {
            self.bookmark.name = displayName
            self.bookmark.address = host
            self.bookmark.port = port
            self.bookmark.login = login.isEmpty ? nil : login
            self.bookmark.password = password.isEmpty ? nil : password

            self.dismiss()
          }
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }
    }
  }
}

struct TrackerBookmarkServerView: View {
  let server: BookmarkServer

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      Spacer()
        .frame(width: 14 + 8 + 16)
      Image("Server")
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16, alignment: .center)
      Text(self.server.name ?? "Server").lineLimit(1).truncationMode(.tail)
      if let serverDescription = self.server.description {
        Text(serverDescription)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 0)
      if self.server.users > 0 {
        Text(String(self.server.users))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Circle()
          .fill(.fileComplete)
          .frame(width: 7, height: 7)
          .keyframeAnimator(initialValue: 1.0, repeating: true) { content, opacity in
            content.opacity(opacity)
          } keyframes: { _ in
            CubicKeyframe(1.0, duration: 2.0)  // Stay visible for 1 second
            CubicKeyframe(0.6, duration: 0.5) // Fade out quickly
            CubicKeyframe(1.0, duration: 0.5) // Fade in quickly
          }
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct TrackerItemView: View {
  let bookmark: Bookmark
  let isExpanded: Bool
  let isLoading: Bool
  let count: Int
  let onToggleExpanded: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      if bookmark.type == .tracker {
        Button {
          self.onToggleExpanded()
        } label: {
          Text(Image(systemName: self.isExpanded ? "chevron.down" : "chevron.right"))
            .bold()
            .font(.system(size: 10))
            .opacity(0.5)
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: 10)
        .padding(.leading, 4)
        .padding(.trailing, 2)
      }

      switch bookmark.type {
      case .tracker:
        Image("Tracker")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16, alignment: .center)
        Text(bookmark.name).bold().lineLimit(1).truncationMode(.tail)
        if isLoading {
          ProgressView()
            .padding([.leading, .trailing], 2)
            .controlSize(.small)
        }
        Spacer(minLength: 0)
        if isExpanded && count > 0 {
          HStack(spacing: 4) {
            Text(String(count))
            
            Image(systemName: "globe.americas.fill")
              .resizable()
              .scaledToFit()
              .frame(width: 12, height: 12)
              .opacity(0.5)
          }
          
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(.quinary)
            .clipShape(.capsule)
        }
      case .server:
        Image(systemName: "bookmark.fill")
          .resizable()
          .renderingMode(.template)
          .aspectRatio(contentMode: .fit)
          .frame(width: 11, height: 11, alignment: .center)
          .opacity(0.5)
          .padding(.leading, 3)
          .padding(.trailing, 2)
        Image("Server")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16, alignment: .center)
        Text(bookmark.name).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#if DEBUG
private struct TrackerViewPreview: View {
  @State var selection: TrackerSelection? = nil

  var body: some View {
    TrackerView(selection: $selection)
  }
}

#Preview {
  TrackerViewPreview()
}
#endif
