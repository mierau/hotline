import SwiftUI
import SwiftData
import Foundation
import UniformTypeIdentifiers

struct TrackerView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openWindow) private var openWindow
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.modelContext) private var modelContext
  
  @State private var refreshing = false
  @State private var trackerSheetPresented: Bool = false
  @State private var trackerSheetBookmark: Bookmark? = nil
  @State private var attemptedPrepopulate: Bool = false
  @State private var fileDropActive = false
  @State private var bookmarkExportActive = false
  @State private var bookmarkExport: BookmarkDocument? = nil
  @State private var searchText = ""
  
  @Query(sort: \Bookmark.order) private var bookmarks: [Bookmark]
  @Binding var selection: Bookmark?

  var filteredBookmarks: [Bookmark] {
    if searchText.isEmpty {
      return bookmarks
    }

    return bookmarks.filter { bookmark in
      let bookmarkMatches = bookmark.name.localizedCaseInsensitiveContains(searchText)

      if bookmark.type == .tracker {
        let hasMatchingServers = bookmark.servers.contains { server in
          server.name.localizedCaseInsensitiveContains(searchText)
        }
        return bookmarkMatches || hasMatchingServers
      } else {
        return bookmarkMatches
      }
    }
  }

  func filteredServers(for tracker: Bookmark) -> [Bookmark] {
    if searchText.isEmpty {
      return tracker.servers
    }

    return tracker.servers.filter { server in
      server.name.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    List(selection: $selection) {
      ForEach(filteredBookmarks, id: \.persistentModelID) { bookmark in
        TrackerItemView(bookmark: bookmark)
          .tag(bookmark)
        
        if bookmark.type == .tracker && bookmark.expanded {
          ForEach(filteredServers(for: bookmark), id: \.persistentModelID) { trackedServer in
            TrackerItemView(bookmark: trackedServer)
              .moveDisabled(true)
              .deleteDisabled(true)
              .tag(trackedServer)
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
      if let bookmark = selection,
         bookmark.type != .temporary {
        Bookmark.delete(bookmark, context: modelContext)
      }
    }
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .onChange(of: ApplicationState.shared.cloudKitReady) {
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
    .contextMenu(forSelectionType: Bookmark.self) { items in
      if let item = items.first {
        if item.type == .temporary {
          Button {
            let newBookmark = Bookmark(type: .server, name: item.name, address: item.address, port: item.port, login: item.login, password: item.password)
            Bookmark.add(newBookmark, context: modelContext)
          } label: {
            Label("Bookmark", systemImage: "bookmark")
          }
          
          Divider()
        }
        
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(item.displayAddress, forType: .string)
        } label: {
          Label("Copy Address", systemImage: "doc.on.doc")
        }
        
        if item.type == .tracker || item.type == .server {
          Divider()
          
          if item.type == .tracker {
            Button {
              trackerSheetBookmark = item
            } label: {
              Label("Edit Tracker...", systemImage: "pencil")
            }
          }
          
          if item.type == .server {
            Button {
              bookmarkExport = BookmarkDocument(bookmark: item)
              bookmarkExportActive = true
            } label: {
              Label("Export Bookmark...", systemImage: "bookmark.square")
            }
          }
          
          Divider()
          
          Button {
            Bookmark.delete(item, context: modelContext)
          } label: {
            Label(item.type == .tracker ? "Delete Tracker" : "Delete Bookmark", systemImage: "trash")
          }
        }
      }
    } primaryAction: { items in
      guard let clickedItem = items.first else {
        return
      }
      
      if clickedItem.type == .tracker {
        if NSEvent.modifierFlags.contains(.option) {
          trackerSheetBookmark = clickedItem
        }
        else {
          clickedItem.expanded.toggle()
        }
      }
      else if let server = clickedItem.server {
        openWindow(id: "server", value: server)
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
      if
        let bookmark = selection,
        bookmark.type == .tracker {
        bookmark.expanded = true
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.leftArrow) {
      if
        let bookmark = selection,
        bookmark.type == .tracker {
        bookmark.expanded = false
        return .handled
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
          refreshing = true
          refresh()
          refreshing = false
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
    .searchable(text: $searchText, prompt: "Search servers...")
  }
  
  func refresh() {
    // When a tracker is selected, refresh only that tracker.
    if
      let selectedBookmark = selection,
      selectedBookmark.type == .tracker {
      if !selectedBookmark.expanded {
        selectedBookmark.expanded = true
      }
      else {
        Task {
          await selectedBookmark.fetchServers()
        }
      }
      return
    }
    
    // Otherwise refresh/expand all trackers.
    for bookmark in self.bookmarks {
      if bookmark.type == .tracker {
        if !bookmark.expanded {
          bookmark.expanded = true
        }
        else {
          Task {
            await bookmark.fetchServers()
          }
        }
      }
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
        Button(self.bookmark != nil ? "Save Tracker" : "Add Tracker") {
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
              
              dismiss()
            }
          }
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.trackerName = ""
          self.trackerAddress = ""
          
          dismiss()
        }
      }
    }
  }
}

struct TrackerItemView: View {
  let bookmark: Bookmark
  
  @State private var onlineAnimationMaxState: Bool = true
  
  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      if bookmark.type == .tracker {
        Button {
          bookmark.expanded.toggle()
        } label: {
          Text(Image(systemName: bookmark.expanded ? "chevron.down" : "chevron.right"))
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
        if bookmark.loading {
          ProgressView()
            .padding([.leading, .trailing], 2)
            .controlSize(.small)
        }
        Spacer(minLength: 0)
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
      case .temporary:
        Spacer()
          .frame(width: 14 + 8 + 16)
        Image("Server")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16, alignment: .center)
        Text(bookmark.name).lineLimit(1).truncationMode(.tail)
        if let serverDescription = bookmark.serverDescription {
          Text(serverDescription)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        Spacer(minLength: 0)
        if let serverUserCount = bookmark.serverUserCount,
           serverUserCount > 0 {
          Text(String(serverUserCount))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          
          Circle()
            .fill(.fileComplete)
            .frame(width: 7, height: 7)
            .opacity(onlineAnimationMaxState ? 1.0 : 0.2)
            .onAppear {
              withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                onlineAnimationMaxState.toggle()
              }
            }
            .padding(.trailing, 6)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      // Fetch servers for trackers that are already expanded on appear
      if bookmark.type == .tracker && bookmark.expanded && bookmark.servers.isEmpty && !bookmark.loading {
        Task {
          await bookmark.fetchServers()
        }
      }
    }
    .onChange(of: bookmark.expanded) {
      guard bookmark.type == .tracker else {
        return
      }

      if bookmark.expanded {
        Task {
          await bookmark.fetchServers()
        }
      }
    }
  }
}

#if DEBUG
private struct TrackerViewPreview: View {
  @State var selection: Bookmark? = nil

  var body: some View {
    TrackerView(selection: $selection)
  }
}

#Preview {
  TrackerViewPreview()
}
#endif
