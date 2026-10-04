import SwiftUI
import SwiftData
import Foundation
import UniformTypeIdentifiers

enum TrackerSelection: Hashable {
  case bookmark(Bookmark)
  case bookmarkServer(BookmarkServer)
  case bonjourGroup
  case bonjourServer(BonjourState.BonjourServer)
  
  var server: Server? {
    switch self {
    case .bookmark(let b): b.server
    case .bookmarkServer(let t): t.server
    case .bonjourGroup: nil
    case .bonjourServer(let b): b.server
    }
  }
}

struct TrackerView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openWindow) private var openWindow
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
  
  var bonjourRowView: some View {
    HStack(alignment: .center, spacing: 6) {
      Button {
        AppState.shared.bonjourState.isExpanded.toggle()
      } label: {
        Text(Image(systemName: AppState.shared.bonjourState.isExpanded ? "chevron.down" : "chevron.right"))
          .bold()
          .font(.system(size: 10))
          .opacity(0.5)
          .frame(alignment: .center)
      }
      .buttonStyle(.plain)
      .frame(width: 10)
      .padding(.leading, 4)
      .padding(.trailing, 2)
      
      Image(systemName: "bonjour")
        .resizable()
        .scaledToFit()
        .symbolRenderingMode(.multicolor)
        .frame(width: 16, height: 16, alignment: .center)
      Text("Bonjour").bold().lineLimit(1).truncationMode(.tail)

      if AppState.shared.bonjourState.isBrowsing {
        ProgressView()
          .controlSize(.mini)
      }
      
      Spacer(minLength: 0)
      
      if AppState.shared.bonjourState.isExpanded && !AppState.shared.bonjourState.discoveredServers.isEmpty {
        HStack(spacing: 4) {
          Text(String(AppState.shared.bonjourState.discoveredServers.count))

          SpinningGlobeView()
            .fontWeight(.semibold)
            .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(.secondary)
//          .background(.quinary)
        .clipShape(.capsule)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: AppState.shared.bonjourState.isExpanded) { oldState, newState in
      if newState {
        AppState.shared.bonjourState.startBrowsing()
      }
      else {
        AppState.shared.bonjourState.stopBrowsing()
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
              .padding(.leading, 16 + 8 + 10)
          }
        }
      }
      .onMove { movedIndexes, destinationIndex in
        Bookmark.move(movedIndexes, to: destinationIndex, context: modelContext)
      }
      .onDelete { deletedIndexes in
        Bookmark.delete(at: deletedIndexes, context: modelContext)
      }
      
      self.bonjourRowView
        .tag(TrackerSelection.bonjourGroup)
      
      if AppState.shared.bonjourState.isExpanded {
        ForEach(AppState.shared.bonjourState.discoveredServers, id: \.self) { record in
          BonjourServerRow(server: record)
            .tag(TrackerSelection.bonjourServer(record))
            .padding(.leading, 16 + 8 + 10)
        }
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
        case .bonjourGroup:
          EmptyView()
        case .bonjourServer(let bonjourServer):
          self.bonjourServerContextMenu(bonjourServer)
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
      
      case .bonjourGroup:
        AppState.shared.bonjourState.isExpanded.toggle()
        
      case .bonjourServer(let bonjourServer):
        if let server = bonjourServer.server {
          openWindow(id: "server", value: server)
        }
        
      }
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
          self.setExpanded(true, for: bookmark)
          return .handled
        }
      default:
        break
      }
      
      return .ignored
    }
    .onKeyPress(.leftArrow) {
      switch self.selection {
      case .bookmark(let bookmark):
        if bookmark.type == .tracker {
          self.setExpanded(false, for: bookmark)
          return .handled
        }
      default:
        break
      }
      
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
    .searchable(text: $searchText, isPresented: $isSearching, placement: .automatic, prompt: "Search")
    .background(Button("", action: { isSearching = true }).keyboardShortcut("f").hidden())
  }
  
  @ViewBuilder
  func bookmarkServerContextMenu(_ server: BookmarkServer) -> some View {
    Button {
      NSPasteboard.general.clearContents()
      let displayAddress = (server.port == HotlinePorts.DefaultServerPort) ? server.address : "\(server.address):\(server.port)"
      NSPasteboard.general.setString("hotline://\(displayAddress)", forType: .string)
    } label: {
      Label("Copy Link", systemImage: "link")
    }
    
    Button {
      NSPasteboard.general.clearContents()
      let displayAddress = (server.port == HotlinePorts.DefaultServerPort) ? server.address : "\(server.address):\(server.port)"
      NSPasteboard.general.setString(displayAddress, forType: .string)
    } label: {
      Label("Copy Address", systemImage: "doc.on.doc")
    }
    
    Divider()
    
    Button {
      let newBookmark = Bookmark(type: .server, name: server.name ?? server.address, address: server.address, port: server.port, login: nil, password: nil)
      Bookmark.add(newBookmark, context: modelContext)
    } label: {
      Label("Bookmark", systemImage: "bookmark")
    }
  }
  
  @ViewBuilder
  func bookmarkContextMenu(_ bookmark: Bookmark) -> some View {
    Button {
      let linkString: String = switch bookmark.type {
      case .tracker: "hotlinetracker://\(bookmark.displayAddress)"
      case .server: "hotline://\(bookmark.displayAddress)"
      }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(linkString, forType: .string)
    } label: {
      Label("Copy Link", systemImage: "link")
    }
    
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
      if bookmark.type == .tracker {
        Label("Delete Tracker", systemImage: "xmark")
      }
      else {
        Label("Delete Bookmark", systemImage: "bookmark.slash")
      }
    }
  }
  
  @ViewBuilder
  func bonjourServerContextMenu(_ bonjourServer: BonjourState.BonjourServer) -> some View {
    Button {
      guard let server = bonjourServer.server else {
        return
      }
      NSPasteboard.general.clearContents()
      let displayAddress = (server.port == HotlinePorts.DefaultServerPort) ? server.address : "\(server.address):\(server.port)"
      NSPasteboard.general.setString("hotline://\(displayAddress)", forType: .string)
    } label: {
      Label("Copy Link", systemImage: "link")
    }
    
    Button {
      guard let server = bonjourServer.server else {
        return
      }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(server.displayAddress, forType: .string)
    } label: {
      Label("Copy Address", systemImage: "doc.on.doc")
    }
    
    Divider()
    
    Button {
      guard let server = bonjourServer.server else {
        return
      }
      let newBookmark = Bookmark(type: .server, name: server.name ?? server.address, address: server.address, port: server.port, login: nil, password: nil)
      Bookmark.add(newBookmark, context: modelContext)
    } label: {
      Label("Bookmark", systemImage: "bookmark")
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
    self.setExpanded(!self.expandedTrackers.contains(bookmark), for: bookmark)
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
