import SwiftUI

struct TransfersView: View {
  @Environment(\.appState) private var appState
  
  @State private var selectedTransfers = Set<TransferInfo>()
  
  var body: some View {
    VStack(spacing: 0) {
      if self.appState.transfers.isEmpty {
        self.emptyState
      } else {
        self.transfersList
      }
    }
    .frame(minWidth: 500, minHeight: 200)
    .navigationTitle("Transfers")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          if self.selectedTransfers.isEmpty {
            NSWorkspace.shared.open(Prefs.shared.resolvedDownloadFolder)
          }
          else {
            let fileURLs = self.selectedTransfers.compactMap(\.fileURL)
            if !fileURLs.isEmpty {
              NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
            }
          }
        } label: {
          Label("Show Downloads", systemImage: "folder")
        }
        .help("Show Downloads")
      }
      
      ToolbarItem(placement: .primaryAction) {
        Button {
          for transfer in self.selectedTransfers {
            self.appState.cancelTransfer(id: transfer.id)
          }
          self.selectedTransfers = []
        } label: {
          Label(self.selectedTransfers.count == 1 ? "Remove Transfer" : "Remove Transfers", systemImage: "xmark")
        }
        .disabled(self.selectedTransfers.isEmpty)
        .help(self.selectedTransfers.count == 1 ? "Remove Transfer" : "Remove Transfers")
      }
    }
  }
  
  // MARK: - Empty State
  
  private var emptyState: some View {
    ContentUnavailableView {
      Label("No Transfers", systemImage: "arrow.up.arrow.down")
    } description: {
      Text("Your Hotline file transfers will appear here")
    }
  }
  
  // MARK: - Transfers List
  
  private var transfersList: some View {
    List(selection: self.$selectedTransfers) {
      ForEach(self.appState.transfers) { transfer in
        TransferRow(transfer: transfer)
          .id(transfer)
      }
    }
    .listStyle(.inset)
    .environment(\.defaultMinListRowHeight, 56)
    .contextMenu(forSelectionType: TransferInfo.self) { items in
      self.contextMenuForItems(items)
    } primaryAction: { items in
      self.performPrimaryAction(for: items)
    }
  }
  
  // MARK: - Double Click
  
  private func performPrimaryAction(for items: Set<TransferInfo>) {
    if let fileURL = items.first?.fileURL {
      NSWorkspace.shared.open(fileURL)
    }
  }
  
  // MARK: - Context Menu
  
  @ViewBuilder
  private func contextMenuForItems(_ items: Set<TransferInfo>) -> some View {
    if items.allSatisfy(\.completed) {
      let fileURLs: [URL] = items.compactMap(\.fileURL)
      
      Button("Remove Transfer\(items.count > 1 ? "s" : "")", systemImage: "xmark") {
        self.appState.cancelTransfers(ids: items.map(\.id))
        self.selectedTransfers = []
      }
      
      Divider()
      
      Button("Open", systemImage: "arrow.up.right.square") {
        for fileURL in fileURLs {
          NSWorkspace.shared.open(fileURL)
        }
      }
      
      self.openWithMenu(for: fileURLs)
      
      Button("Show in Finder", systemImage: "finder") {
        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
      }
      
      Divider()
      
      Button("Move to Trash", systemImage: "trash") {
        self.appState.cancelTransfers(ids: items.map(\.id))
        NSWorkspace.shared.recycle(fileURLs)
        self.selectedTransfers = []
      }
    } else {
      Button("Remove Transfer\(items.count > 1 ? "s" : "")", systemImage: "xmark") {
        self.appState.cancelTransfers(ids: items.map(\.id))
        self.selectedTransfers = []
      }
      
      Divider()
      
      Button("Move to Trash", systemImage: "trash") {
        self.appState.cancelTransfers(ids: items.map(\.id))
        
        let fileURLs: [URL] = items.compactMap(\.fileURL)
        if !fileURLs.isEmpty {
          NSWorkspace.shared.recycle(fileURLs)
        }
        
        self.selectedTransfers = []
      }
    }
  }
  
  private func getOpenWithApps(for fileURLs: [URL], defaultAppURL: URL? = nil) -> [(name: String, url: URL)] {
    // If no files provided, there is no common app to open them
    guard !fileURLs.isEmpty else { return [] }
    
    // Build a list of app URL sets for each file URL
    let appSets: [Set<URL>] = fileURLs.map { url in
      let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
      return Set(apps)
    }
    
    // Compute the intersection across all file URL app sets
    guard var intersection = appSets.first else { return [] }
    for set in appSets.dropFirst() {
      intersection.formIntersection(set)
    }
    
    // Optionally remove the default app from the list
    if let defaultAppURL {
      intersection.remove(defaultAppURL)
    }
    
    // Map to display names and sort by name
    let result: [(name: String, url: URL)] = intersection.compactMap { url in
      let appName = FileManager.default
        .displayName(atPath: url.path)
        .replacing(".app", with: "")
      return (name: appName, url: url)
    }.sorted { $0.name < $1.name }
    
    return result
  }
  
  private func getDefaultApp(for fileURLs: [URL]) -> (name: String, url: URL)? {
    // No files -> no default app
    guard !fileURLs.isEmpty else { return nil }
    
    // Single file: use the system default directly
    if fileURLs.count == 1, let url = NSWorkspace.shared.urlForApplication(toOpen: fileURLs[0]) {
      let name = FileManager.default
        .displayName(atPath: url.path)
        .replacing(".app", with: "")
      return (name, url)
    }
    
    // Build the intersection of apps that can open ALL files
    let appSets: [Set<URL>] = fileURLs.map { url in
      Set(NSWorkspace.shared.urlsForApplications(toOpen: url))
    }
    guard var intersection = appSets.first else { return nil }
    for set in appSets.dropFirst() {
      intersection.formIntersection(set)
      if intersection.isEmpty { return nil }
    }
    
    // Tally the system default app for each file
    var defaultCounts: [URL: Int] = [:]
    for fileURL in fileURLs {
      if let def = NSWorkspace.shared.urlForApplication(toOpen: fileURL) {
        defaultCounts[def, default: 0] += 1
      }
    }
    
    // Prefer the app that's the default for the majority of files, provided it can open all
    if let bestByMajority = intersection.max(by: { (a, b) -> Bool in
      let ca = defaultCounts[a, default: 0]
      let cb = defaultCounts[b, default: 0]
      if ca == cb {
        // Tie-breaker deferred to later
        return false
      }
      return ca < cb
    }),
       defaultCounts[bestByMajority, default: 0] > 0 {
      let name = FileManager.default
        .displayName(atPath: bestByMajority.path)
        .replacing(".app", with: "")
      return (name, bestByMajority)
    }
    
    return nil
  }
  
  private func openWithMenu(for fileURLs: [URL]) -> some View {
    Menu("Open With") {
      let defaultApp: (name: String, url: URL)? = self.getDefaultApp(for: fileURLs)
      let apps: [(name: String, url: URL)] = self.getOpenWithApps(for: fileURLs, defaultAppURL: defaultApp?.url)
      
      if let defaultApp {
        Button {
          NSWorkspace.shared.open(fileURLs, withApplicationAt: defaultApp.url, configuration: NSWorkspace.OpenConfiguration())
        } label: {
          Label {
            Text(defaultApp.name)
          } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: defaultApp.url.path))
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
          }
        }
        
        if !apps.isEmpty {
          Divider()
        }
      }
      
      if !apps.isEmpty {
        ForEach(apps, id: \.url) { app in
          Button {
            NSWorkspace.shared.open(fileURLs, withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
          } label: {
            Label {
              Text(app.name)
            } icon: {
              Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            }
          }
        }
      }
    }
  }
  
}

// MARK: - Transfer Row

struct TransferRow: View {
  @Environment(\.appState) private var appState
  
  @Bindable var transfer: TransferInfo
  
  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      if self.transfer.isFolder {
        self.folderIconView
      }
      else {
        self.fileIconView
      }
      
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(self.transfer.title)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
          
          Spacer()
          
          if !self.transfer.done {
            self.statsView
          }
        }
        
        // Progress bar and status
        if self.transfer.cancelled {
          Text("Cancelled")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        else if self.transfer.failed {
          Text("Failed")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        else if self.transfer.completed {
          Text(self.transfer.isUpload ? "Uploaded" : "Downloaded")
            .font(.subheadline)
            .foregroundStyle(.fileComplete)
        }
        else if self.transfer.waiting {
          Text("Waiting")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        else {
          ProgressView(value: self.transfer.progress, total: 1.0)
            .progressViewStyle(.linear)
            .controlSize(.large)
        }
      }
    }
  }
  
  // MARK: -
  
  private var statsView: some View {
    HStack(spacing: 8) {
      // Progress percentage
      //      Text("\(Int(self.transfer.progress * 100))%")
      
      // Speed
      if let speed = self.transfer.displaySpeed {
        Label(speed, systemImage: self.transfer.isUpload ? "arrow.up" : "arrow.down")
      }
      
      // Time remaining
      if let timeRemaining = self.transfer.displayTimeRemaining {
        Label(timeRemaining, systemImage: "clock")
      }
      
      // File size
      Label(self.transfer.displaySize, systemImage: "document")
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }
  
  private var folderIconView: some View {
    FolderIconView()
      .frame(width: 32, height: 32)
      .overlay(alignment: .bottomTrailing) {
        if self.transfer.cancelled || self.transfer.failed {
          Image(systemName: "exclamationmark.triangle.fill")
            .resizable()
            .symbolRenderingMode(.multicolor)
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else if self.transfer.completed {
          Image(systemName: "checkmark.circle.fill")
            .resizable()
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .fileComplete)
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else {
          FileIconView(filename: self.transfer.title, fileType: nil)
            .frame(width: 16, height: 16)
        }
      }
  }
  
  private var fileIconView: some View {
    FileIconView(filename: self.transfer.title, fileType: nil)
      .frame(width: 32, height: 32)
      .overlay(alignment: .bottomTrailing) {
        if self.transfer.cancelled || self.transfer.failed {
          Image(systemName: "exclamationmark.triangle.fill")
            .resizable()
            .symbolRenderingMode(.multicolor)
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else if self.transfer.completed {
          Image(systemName: "checkmark.circle.fill")
            .resizable()
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .fileComplete)
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
      }
  }
}

// MARK: - Preview

#Preview {
  TransfersView()
    .environment(AppState.shared)
}

