import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FilesView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.openWindow) private var openWindow

  @Bindable var serverState: ServerState

  @State private var selection: FileInfo?
  @State private var fileDetails: FileDetails?
  @State private var uploadFileSelectorDisplayed: Bool = false
  @State private var searchText: String = ""
  @State private var isSearching: Bool = false
  @State private var dragOver: Bool = false
  @State private var confirmDeleteShown: Bool = false
  @State private var newFolderShown: Bool = false
  @State private var viewMode: String = Prefs.shared.filesViewMode
  @State private var pendingFileSelection: String? = nil
  @State private var folderLoading: Bool = false
  @FocusState private var isFileListFocused: Bool

  private var folderPath: [String] {
    get { self.serverState.fileFolderPath }
    nonmutating set { self.serverState.fileFolderPath = newValue }
  }

  private var actions: FileActions {
    FileActions(model: model, openWindow: openWindow)
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewMode == "grid" {
          FilesGridView(
            selection: $selection,
            folderPath: $serverState.fileFolderPath,
            fileDetails: $fileDetails,
            confirmDeleteShown: $confirmDeleteShown,
            uploadFileSelectorDisplayed: $uploadFileSelectorDisplayed,
            newFolderShown: $newFolderShown,
            actions: actions,
            isShowingSearchResults: isShowingSearchResults,
            folderLoading: $folderLoading
          )
        }
        else {
          listView
        }
      }
      .focused($isFileListFocused)
      .task {
        if !self.model.filesLoaded {
          let _ = try? await self.model.getFileList()
        }
      }
      // MARK: Folder Loading
      //
      // Folder loading is owned by FilesView so it happens exactly once
      // regardless of whether the list or grid child view is active.
      // After loading, any pending file link selection is resolved.
      .task(id: self.folderPath) {
        if !self.folderPath.isEmpty {
          // Skip reloading if the folder was already fetched from the server.
          // Reloading replaces FileInfo objects (new UUIDs), which would
          // invalidate any pending file link selection. Placeholder folders
          // created by ensureIntermediateFolders have loaded == false, so
          // they will still be fetched on first visit.
          let existingFolder = self.findFolder(in: self.model.files, at: self.folderPath)
          if existingFolder?.loaded != true {
            self.folderLoading = true
            let _ = try? await self.model.getFileList(path: self.folderPath)
            self.folderLoading = false
          }
        }
        self.resolvePendingFileSelection()
      }
      // MARK: File Link Navigation
      //
      // When a user clicks a hotline:// file link in chat, ChatView sets
      // serverState.fileNavigationPath and switches to the Files tab.
      //
      // Flow:
      //  1. consumeFileNavigationPath() reads the path, sets folderPath
      //     to the parent folder, and stores the target filename in
      //     pendingFileSelection.
      //
      //  2. The .task(id: folderPath) above loads the folder contents.
      //     (ensureIntermediateFolders in getFileList creates placeholder
      //     tree nodes so results can be attached even if parent folders
      //     haven't been browsed yet.)
      //
      //  3. After loading, resolvePendingFileSelection() finds and
      //     selects the target file.
      .onAppear {
        self.consumeFileNavigationPath()
      }
      .onChange(of: self.serverState.fileNavigationPath) { _, _ in
        self.consumeFileNavigationPath()
      }
      .searchable(text: $searchText, isPresented: $isSearching, placement: .automatic, prompt: self.folderPath.last.map { "Search \($0)" } ?? "Search")
      .background(Button("", action: { isSearching = true }).keyboardShortcut("f").hidden())
      .navigationSubtitle(!folderPath.isEmpty ? folderPath.last ?? "" : "")
      .toolbar {
        if !folderPath.isEmpty && !isShowingSearchResults {
          ToolbarItem {
            Button {
              self.folderPath.removeLast()
            } label: {
              Label("Back", systemImage: "chevron.left")
            }
            .help("Back")
          }
        }

        ToolbarItem {
          Menu {
            Button {
              self.viewMode = "list"
            } label: {
              Label("as List", systemImage: "list.bullet")
            }

            Button {
              self.viewMode = "grid"
            } label: {
              Label("as Icons", systemImage: "square.grid.2x2")
            }
          } label: {
            Label("View", systemImage: self.viewMode == "grid" ? "square.grid.2x2" : "list.bullet")
          }
          .help("View Mode")
        }
        ToolbarItem {
          Button {
            if let selectedFile = self.selection, selectedFile.isPreviewable {
              self.actions.previewFile(selectedFile)
            }
          } label: {
            Label("Quick Look", systemImage: "eye")
          }
          .help("Quick Look")
          .disabled(self.selection == nil || self.selection?.isPreviewable != true)
        }

        ToolbarItem {
          Button {
            if let selectedFile = self.selection {
              self.actions.downloadFile(selectedFile)
            }
          } label: {
            Label("Download", systemImage: "arrow.down")
          }
          .help("Download")
          .disabled(self.selection == nil || self.model.access?.contains(.canDownloadFiles) != true)
        }

        ToolbarItem {
          Menu {
            Button {
              self.uploadFileSelectorDisplayed = true
            } label: {
              Label("Upload...", systemImage: "arrow.up")
            }
            .disabled(self.model.access?.contains(.canUploadFiles) != true)
            
            Button {
              if let selectedFile = self.selection {
                self.actions.downloadFile(selectedFile)
              }
            } label: {
              Label("Download", systemImage: "arrow.down")
            }
            .disabled(self.selection == nil || self.model.access?.contains(.canDownloadFiles) != true)

            Divider()

            Button {
              if let selectedFile = self.selection {
                self.actions.copyFileLink(selectedFile)
              }
            } label: {
              Label("Copy Link", systemImage: "link")
            }
            .disabled(self.selection == nil)

            Button {
              if let selectedFile = self.selection {
                Task {
                  if let details = await self.actions.getFileInfo(selectedFile) {
                    self.fileDetails = details
                  }
                }
              }
            } label: {
              Label("Get Info", systemImage: "info.circle")
            }
            .disabled(self.selection == nil)
            
            Button {
              if let selectedFile = self.selection, selectedFile.isPreviewable {
                self.actions.previewFile(selectedFile)
              }
            } label: {
              Label("Quick Look", systemImage: "eye")
            }
            .disabled(self.selection == nil || self.selection?.isPreviewable != true)
            
            Button {
              self.newFolderShown = true
            } label: {
              Label("New Folder", systemImage: "folder.badge.plus")
            }
            .disabled(self.model.access?.contains(.canCreateFolders) != true)

            Divider()

            Button {
              self.confirmDeleteShown = true
            } label: {
              Label(self.selection?.isFolder == true ? "Delete Folder..." : "Delete File...", systemImage: "trash")
            }
            .disabled(self.selection == nil || (self.model.access?.contains(.canDeleteFiles) != true && self.model.access?.contains(.canDeleteFolders) != true))
          } label: {
            Label("Actions", systemImage: "ellipsis")
          }
          .help("More Actions")
          .popover(isPresented: self.$newFolderShown, arrowEdge: .bottom) {
            NewFolderPopover { folderName in
              self.actions.newFolder(name: folderName, parent: self.selection)
            }
          }
        }
      }
    }
    .alert("Are you sure you want to permanently delete \"\(self.selection?.name ?? "this file")\"?", isPresented: self.$confirmDeleteShown, actions: {
      Button("Delete", role: .destructive) {
        if let s = self.selection {
          Task {
            await actions.deleteFile(s)
          }
        }
      }
    }, message: {
      Text("You cannot undo this action.")
    })
    .sheet(item: self.$fileDetails) { item in
      FileDetailsSheet(details: item)
    }
    .fileImporter(isPresented: self.$uploadFileSelectorDisplayed, allowedContentTypes: [.data, .folder], allowsMultipleSelection: false, onCompletion: { results in
      switch results {
      case .success(let fileURLS):
        guard let fileURL = fileURLS.first else {
          return
        }

        var uploadPath: [String] = []

        if let selection = self.selection, selection.isFolder {
          uploadPath = selection.path
        }
        else if !self.folderPath.isEmpty {
          uploadPath = self.folderPath
        }

        self.actions.upload(file: fileURL, to: uploadPath)

      case .failure(let error):
        print(error)
      }
    })
    .fileDialogConfirmationLabel("Upload")
    .fileDialogMessage(Text(self.uploadDestinationName.map { "Select a file or folder to upload to \"\($0)\"" } ?? "Select a file or folder to upload"))
    .onSubmit(of: .search) {
      #if os(macOS)
      let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
      if shiftPressed {
        model.clearFileListCache()
      }
      #endif

      let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        model.cancelFileSearch()
        return
      }
      searchText = trimmed
      model.startFileSearch(query: trimmed, startPath: self.folderPath)
    }
    .onChange(of: searchText) { _, newValue in
      if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if isShowingSearchResults {
          model.cancelFileSearch()
        }
      }
    }
    .onChange(of: model.fileSearchQuery) { _, newValue in
      if newValue != searchText {
        searchText = newValue
      }
    }
    .onChange(of: viewMode) { _, newValue in
      Prefs.shared.filesViewMode = newValue
      self.isFileListFocused = true
    }
    .onAppear {
      if searchText != model.fileSearchQuery {
        searchText = model.fileSearchQuery
      }
    }
    .safeAreaInset(edge: .top) {
      if isShowingSearchResults, let message = searchStatusMessage {
        HStack(alignment: .center, spacing: 6) {
          if case .searching(_, _) = model.fileSearchStatus {
            ProgressView()
              .controlSize(.small)
              .accentColor(.white)
              .tint(.white)
          }
          else if case .completed = model.fileSearchStatus {
            Image(systemName: "checkmark.circle.fill")
              .resizable()
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(.white)
              .aspectRatio(contentMode: .fit)
              .frame(width: 16, height: 16)
          }
          else if case .failed = model.fileSearchStatus {
            Image(systemName: "exclamationmark.triangle.fill")
              .resizable()
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(.white)
              .aspectRatio(contentMode: .fit)
              .frame(width: 16, height: 16)
          }

          Text(message)
            .lineLimit(1)
            .font(.body)
            .foregroundStyle(.white)

          Spacer()

          if let pathMessage = searchStatusPath {
            Text(pathMessage)
              .lineLimit(1)
              .truncationMode(.tail)
              .font(.footnote)
              .foregroundStyle(.white)
              .opacity(0.5)
              .padding(.top, 2)
          }
        }
        .padding(.trailing, 14)
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .background {
          Group {
            if case .completed = model.fileSearchStatus {
              Color.fileComplete
            }
            else {
              Color(nsColor: .controlAccentColor)
            }
          }
          .clipShape(.capsule(style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
      }
    }
    .background {
      if #available(macOS 26.0, *) {
        Color(.windowBackgroundColor)
          .ignoresSafeArea()
      } else {
        Color(nsColor: .textBackgroundColor)
          .ignoresSafeArea()
      }
    }
  }

  // MARK: - List View

  private var listView: some View {
    self.listContent
      .onKeyPress(.rightArrow) {
        if let s = self.selection, s.isFolder {
          s.expanded = true
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.leftArrow) {
        if let s = self.selection, s.isFolder {
          s.expanded = false
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.space) {
        if let s = self.selection, s.isPreviewable {
          self.actions.previewFile(s)
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.downArrow, phases: .down) { press in
        guard press.modifiers.contains(.command) else { return .ignored }
        if let s = self.selection, s.isFolder {
          self.folderPath = s.path
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.upArrow, phases: .down) { press in
        guard press.modifiers.contains(.command) else { return .ignored }
        if !self.folderPath.isEmpty {
          self.folderPath.removeLast()
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.return) {
        if let s = self.selection {
          if s.isFolder {
            self.folderPath = s.path
          }
          else {
            self.actions.downloadFile(s)
          }
          return .handled
        }
        return .ignored
      }
      .overlay {
        if !model.filesLoaded {
          VStack {
            ProgressView()
              .controlSize(.large)
          }
          .frame(maxWidth: .infinity)
        }
      }
  }

  private var listContent: some View {
    ScrollViewReader { proxy in
      List(self.displayedFiles, id: \.self, selection: self.$selection) { file in
        if file.isFolder {
          FolderItemView(file: file, depth: 0).tag(file.id)
        }
        else {
          FileItemView(file: file, depth: 0).tag(file.id)
        }
      }
      .environment(\.defaultMinListRowHeight, 28)
      .listStyle(.inset)
      .alternatingRowBackgrounds(.enabled)
      .onChange(of: self.selection) { _, newValue in
        if let file = newValue {
          withAnimation {
            proxy.scrollTo(file, anchor: nil)
          }
        }
      }
    }
    .onDrop(of: [.fileURL], isTargeted: self.$dragOver) { items in
      guard self.model.access?.contains(.canUploadFiles) == true else {
        return false
      }

      return actions.upload(droppedItems: items, to: self.folderPath)
    }
    .contextMenu(forSelectionType: FileInfo.self) { items in
      let file = items.first

      Button {
        self.selection = file
        self.uploadFileSelectorDisplayed = true
      } label: {
        Label("Upload...", systemImage: "arrow.up")
      }
      .disabled(file != nil && !file!.isFolder || self.model.access?.contains(.canUploadFiles) != true)

      Button {
        if let file = file {
          self.actions.downloadFile(file)
        }
      } label: {
        Label("Download", systemImage: "arrow.down")
      }
      .disabled(file == nil || self.model.access?.contains(.canDownloadFiles) != true)

      Divider()

      Button {
        if let file = file {
          self.actions.copyFileLink(file)
        }
      } label: {
        Label("Copy Link", systemImage: "link")
      }
      .disabled(file == nil)

      Button {
        if let file = file {
          Task {
            if let details = await self.actions.getFileInfo(file) {
              self.fileDetails = details
            }
          }
        }
      } label: {
        Label("Get Info", systemImage: "info.circle")
      }
      .disabled(file == nil)

      Button {
        if let file = file {
          self.actions.previewFile(file)
        }
      } label: {
        Label("Quick Look", systemImage: "eye")
      }
      .disabled(file == nil || file?.isPreviewable != true)

      Button {
        self.newFolderShown = true
      } label: {
        Label("New Folder", systemImage: "folder.badge.plus")
      }
      .disabled((file != nil && !file!.isFolder) || self.model.access?.contains(.canCreateFolders) != true)

      Divider()

      Button {
        if let file = file {
          self.selection = file
          self.confirmDeleteShown = true
        }
      } label: {
        Label(file?.isFolder == true ? "Delete Folder..." : "Delete File...", systemImage: "trash")
      }
      .disabled(file == nil || (self.model.access?.contains(.canDeleteFiles) != true && self.model.access?.contains(.canDeleteFolders) != true))
    } primaryAction: { items in
      guard let clickedFile = items.first else {
        return
      }

      self.selection = clickedFile
      if clickedFile.isFolder {
        self.folderPath = clickedFile.path
      }
      else {
        actions.downloadFile(clickedFile)
      }
    }
  }

  // MARK: - Computed Properties

  private var uploadDestinationName: String? {
    if let selection = self.selection, selection.isFolder {
      return selection.name
    }
    if !self.folderPath.isEmpty {
      return self.folderPath.last
    }
    return nil
  }

  private func resolvePendingFileSelection() {
    guard let targetName = self.pendingFileSelection else { return }
    if let match = self.displayedFiles.first(where: { $0.name == targetName }) {
      print("[FileLink] Resolved pending selection: \(match.name)")
      self.pendingFileSelection = nil
      self.selection = match
      self.isFileListFocused = true
    }
  }

  private func consumeFileNavigationPath() {
    guard let path = self.serverState.fileNavigationPath else { return }
    self.serverState.fileNavigationPath = nil

    if path.isEmpty {
      return
    }

    let parentPath = path.count > 1 ? Array(path.dropLast()) : [String]()
    self.folderPath = parentPath
    self.pendingFileSelection = path.last

    // Try to resolve immediately if the folder data is already loaded.
    // This handles the case where folderPath didn't change (so .task
    // won't re-fire) but the file data is already available.
    self.resolvePendingFileSelection()
  }

  private var isShowingSearchResults: Bool {
    switch model.fileSearchStatus {
    case .idle:
      return !model.fileSearchResults.isEmpty
    case .cancelled(_):
      return !model.fileSearchResults.isEmpty
    default:
      return true
    }
  }

  private var displayedFiles: [FileInfo] {
    if self.isShowingSearchResults {
      return self.model.fileSearchResults
    }
    if !self.folderPath.isEmpty {
      return self.findFolder(in: self.model.files, at: self.folderPath)?.children ?? []
    }
    return self.model.files
  }

  private func findFolder(in files: [FileInfo], at path: [String]) -> FileInfo? {
    guard !path.isEmpty, !files.isEmpty else { return nil }

    let currentName = path[0]
    for file in files {
      if file.name == currentName {
        if path.count == 1 {
          return file
        }
        else if let children = file.children {
          return self.findFolder(in: children, at: Array(path[1...]))
        }
      }
    }
    return nil
  }

  private var searchStatusMessage: String? {
    switch model.fileSearchStatus {
    case .searching(let processed, _):
      let scanned = processed == 1 ? "folder" : "folders"
      return "Searched \(processed) \(scanned)..."
    case .completed(let processed):
      let count = model.fileSearchResults.count
      let folderWord = processed == 1 ? "folder" : "folders"
      if count == 0 {
        return "No files found in \(processed) \(folderWord)"
      }
      return "\(count) file\(count == 1 ? "" : "s") found in \(processed) \(folderWord)"
    case .cancelled(_):
      if model.fileSearchResults.isEmpty {
        return nil
      }
      return "Search cancelled"
    case .failed(let message):
      return "Search failed: \(message)"
    case .idle:
      return nil
    }
  }

  private var searchStatusPath: String? {
    guard let path = model.fileSearchCurrentPath else {
      return nil
    }
    if path.isEmpty {
      return "/"
    }
    return path.joined(separator: "/")
  }
}

#Preview {
  FilesView(serverState: ServerState(selection: .files))
    .environment(HotlineState())
}
