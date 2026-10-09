import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FilesView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.openWindow) private var openWindow
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverTheme) private var theme

  @Bindable var serverState: ServerState

  /// What's selected: one thing, or more than one, or nothing.
  @State private var selection: Set<FileInfo> = []
  @State private var fileDetails: FileDetails?
  @State private var uploadFileSelectorDisplayed: Bool = false
  /// Where what's picked to upload goes: the folder it was asked for on, or the one you're in.
  @State private var uploadDestination: [String] = []
  /// What deleting's being asked about.
  @State private var deleting: [FileInfo] = []
  @State private var searchText: String = ""
  @State private var isSearching: Bool = false
  @State private var confirmDeleteShown: Bool = false
  @State private var newFolderShown: Bool = false
  /// Where a new folder goes: the folder it was asked for in, or the one you're in.
  @State private var newFolderParent: [String] = []
  @State private var viewMode: String = Prefs.shared.filesViewMode
  @State private var pendingFileSelection: String? = nil
  @State private var folderLoading: Bool = false
  /// A folder's been loading a while, long enough to say so, rather than look empty.
  @State private var showFolderLoading: Bool = false
  /// Dragging files and folders out, to the Finder.
  @State private var dragOut = FileDragOut()
  /// How wide the files are, which their part of the toolbar is too.
  @State private var filesWidth: CGFloat = 0
  /// Where something dragged over the list or the icons would go.
  @State private var dropTarget = FileDropTarget()
  /// Renaming a file or folder where it's shown.
  @State private var rename = FileRename()
  /// Where the files' names are shown, in the window, for a click on one to rename it.
  @State private var namePlaces = FilePlaces(space: nil)
  /// Renaming what's been clicked, once it's not the first of a double click.
  @State private var renameClick: Task<Void, Never>? = nil
  /// What a press was on, if it was all that was selected then.
  @State private var pressedAlone: FileInfo? = nil
  /// Where the list's rows are in the window, for a drop to find what it's over, as each row's shown
  /// in a view of its own, which a coordinate space of the list's own doesn't reach.
  @State private var listPlaces = FilePlaces(space: nil)
  /// Where the list is in the window, which a drop on it is measured from.
  @State private var listFrame = CGRect.zero
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
            actions: actions,
            isShowingSearchResults: isShowingSearchResults,
            loading: showFolderLoading,
            menu: { files in AnyView(self.fileMenu(for: files, inToolbar: false)) },
            open: { files in self.open(files) }
          )
        }
        else {
          listView
        }
      }
      .fileDragOut(self.dragOut)
      .environment(self.dropTarget)
      .environment(self.rename)
      .environment(\.fileNamePlaces, self.namePlaces)
      .onChange(of: self.serverState.fileFolderPath, initial: true) { _, newPath in
        self.dropTarget.root = newPath
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
        // Listed again each time it's gone into, for what's changed on the server since, as what
        // hasn't keeps its rows, and what's selected stays so. One that's been listed shows what it
        // had while it is, and one that hasn't, that it's loading. The top's listed the first time
        // the files are shown, above.
        let existingFolder = self.folderPath.isEmpty ? nil : self.findFolder(in: self.model.files, at: self.folderPath)
        if !self.folderPath.isEmpty || self.model.filesLoaded {
          let listed = self.folderPath.isEmpty || existingFolder?.loaded == true
          if !listed {
            self.folderLoading = true
          }
          let _ = try? await self.model.getFileList(path: self.folderPath)
          if !listed {
            self.folderLoading = false
          }
          // What was selected, as it's listed now, where it's changed.
          let selected = Set(self.selection.map(\.path))
          self.selection = Set(self.shownFiles.filter { selected.contains($0.path) })
        }
        self.resolvePendingFileSelection()
      }
      // A folder that's loading shows nothing yet, as an empty one does, so after a moment, it
      // says it's loading, and not before, so one that loads quickly doesn't flash it.
      .task(id: self.folderLoading) {
        if self.folderLoading {
          try? await Task.sleep(for: .seconds(1))
          guard self.folderLoading, !Task.isCancelled else {
            return
          }
          withAnimation(.easeIn(duration: 0.2)) {
            self.showFolderLoading = true
          }
        }
        else if self.showFolderLoading {
          withAnimation(.easeOut(duration: 0.2)) {
            self.showFolderLoading = false
          }
        }
      }
      .onChange(of: self.serverState.fileFolderPath) { oldPath, newPath in
        // Going into a folder from a search's results ends the search, so it's the folder that
        // shows, in a list of its own, which the keys go on in.
        if self.isShowingSearchResults {
          self.model.cancelFileSearch()
          self.selection = []
          self.isFileListFocused = true
          return
        }
        // What's selected stays selected only if it's in the folder now, as when a link asked for
        // it, and going up, the folder you came out of is, as in the Finder.
        if newPath.count < oldPath.count, Array(oldPath.prefix(newPath.count)) == newPath {
          let cameFrom = Array(oldPath.prefix(newPath.count + 1))
          self.selection = Set(self.displayedFiles.filter { $0.path == cameFrom })
        }
        else {
          self.selection = self.selection.intersection(self.shownFiles)
        }
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
        // Dragged out, downloaded where it's dropped, if it can be downloaded, or moved, if it can
        // be moved, with all of what's selected, if it's selected, and selected once it's pressed,
        // and what's selected with it, kept, to drag it all.
        self.dragOut.model = self.model
        self.dragOut.canDrag = { [actions = self.actions] file in
          !file.isUnavailable && (actions.canDownload([file]) || actions.canMove(file))
        }
        self.dragOut.items = { file in
          self.selection.contains(file) ? self.selectedFiles : [file]
        }
        self.dragOut.onPress = { file in
          self.pressedAlone = self.selection == [file] ? file : nil
          if !self.selection.contains(file) {
            self.selection = [file]
          }
        }
        // A click on the name of what was all that was selected renames it, a moment later, once
        // it's not the first of a double click, as in the Finder, if you can rename it. Anything
        // pressed in the meantime keeps it as it is.
        self.dragOut.onAnyPress = {
          self.renameClick?.cancel()
          self.renameClick = nil
        }
        self.dragOut.onClick = { file, place in
          guard self.pressedAlone == file, self.namePlaces.file(at: place) == file, self.actions.canRename(file) else {
            return
          }
          self.renameClick = Task {
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, self.selection == [file] else {
              return
            }
            self.startRenaming(file)
          }
        }
        self.rename.give = { file, name in
          await self.renamed(file, to: name)
        }
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
          Button {
            self.refresh()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .help("Refresh")
          .keyboardShortcut("r", modifiers: .command)
          // Once at a time, and in a search's results, only for folders selected, as listing again
          // all a search went through would be a lot to ask of the server.
          .disabled(!self.model.refreshingFileLists.isEmpty || self.refreshPaths.isEmpty)
        }

        ToolbarItem {
          // Side by side, as the Finder's are, with room, and as a menu, as they are in the Finder too,
          // without enough, before they'd push the rest into the toolbar's overflow menu.
          if self.viewButtonsSideBySide {
            Picker("View", selection: self.$viewMode) {
              Label("as List", systemImage: "list.bullet")
                .tag("list")
              Label("as Icons", systemImage: "square.grid.2x2")
                .tag("grid")
            }
            .pickerStyle(.segmented)
            .help("View Mode")
          }
          else {
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
        }
        ToolbarItem {
          Button {
            if let selectedFile = self.selectedFile, selectedFile.isPreviewable {
              self.actions.previewFile(selectedFile)
            }
          } label: {
            Label("Quick Look", systemImage: "eye")
          }
          .help("Quick Look")
          // One thing at a time.
          .disabled(self.selectedFile?.isPreviewable != true)
        }

        ToolbarItem {
          Button {
            self.actions.download(self.selectedFiles)
          } label: {
            Label("Download", systemImage: "arrow.down")
          }
          .help("Download")
          .disabled(!self.actions.canDownload(self.selectedFiles))
        }

        ToolbarItem {
          Menu {
            self.fileMenu(for: self.selectedFiles, inToolbar: true)
          } label: {
            Label("Actions", systemImage: "ellipsis")
          }
          .help("More Actions")
          .popover(isPresented: self.$newFolderShown, arrowEdge: .bottom) {
            NewFolderPopover { folderName in
              self.actions.newFolder(name: folderName, in: self.newFolderParent)
            }
          }
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      self.filesWidth = width
    }
    .alert(self.deleting.count == 1 ? "Are you sure you want to permanently delete \"\(self.deleting[0].name)\"?" : "Are you sure you want to permanently delete these \(self.deleting.count) items?", isPresented: self.$confirmDeleteShown, actions: {
      Button("Delete", role: .destructive) {
        let files = self.deleting
        Task {
          await actions.delete(files)
        }
      }
    }, message: {
      Text("You cannot undo this action.")
    })
    .sheet(item: self.$fileDetails) { item in
      FileDetailsSheet(details: item)
    }
    .fileImporter(isPresented: self.$uploadFileSelectorDisplayed, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true, onCompletion: { results in
      switch results {
      case .success(let fileURLs):
        self.actions.upload(fileURLs, to: self.uploadDestination)

      case .failure(let error):
        print(error)
      }
    })
    .fileDialogConfirmationLabel("Upload")
    .fileDialogMessage(Text(self.uploadDestinationName.map { "Select files or folders to upload to \"\($0)\"" } ?? "Select files or folders to upload"))
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
      // Not what's in the folders opened in the list, which the icons don't show.
      self.selection = self.selection.intersection(self.shownFiles)
      self.isFileListFocused = true
    }
    .onAppear {
      if searchText != model.fileSearchQuery {
        searchText = model.fileSearchQuery
      }
    }
    .safeAreaInset(edge: .top) {
      if isShowingSearchResults, let message = searchStatusMessage {
        // In the window in front, white on the bar's color, and in other windows, dimmer, on a
        // fainter bar, as selections are.
        let emphasized = self.controlActiveState == .key
        let onBar: Color = emphasized ? .white : .secondary
        HStack(alignment: .center, spacing: 6) {
          if case .searching(_, _) = model.fileSearchStatus {
            // The spinner only takes its color from light and dark, so it's dark's, light, on the
            // bar's color, to go with the white there.
            ProgressView()
              .controlSize(.small)
              .environment(\.colorScheme, emphasized ? .dark : self.colorScheme)
          }
          else if case .completed = model.fileSearchStatus {
            Image(systemName: "checkmark.circle.fill")
              .resizable()
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(onBar)
              .aspectRatio(contentMode: .fit)
              .frame(width: 16, height: 16)
          }
          else if case .failed = model.fileSearchStatus {
            Image(systemName: "exclamationmark.triangle.fill")
              .resizable()
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(onBar)
              .aspectRatio(contentMode: .fit)
              .frame(width: 16, height: 16)
          }

          Text(message)
            .lineLimit(1)
            .font(.body)
            .foregroundStyle(onBar)

          Spacer()

          if let pathMessage = searchStatusPath {
            Text(pathMessage)
              .lineLimit(1)
              .truncationMode(.tail)
              .font(.footnote)
              .foregroundStyle(onBar)
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
              // The selection's color in the server's theme, which is dark enough for white on it.
              Color(nsColor: self.theme?.selection ?? .controlAccentColor)
            }
          }
          .opacity(emphasized ? 1 : 0.35)
          .clipShape(.capsule(style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
      }
    }
    .serverBackground(.content)
  }

  // MARK: - List View

  private var listView: some View {
    self.listContent
      .onKeyPress(.rightArrow) {
        let folders = self.selectedFiles.filter(\.isFolder)
        folders.forEach { $0.expanded = true }
        return folders.isEmpty ? .ignored : .handled
      }
      .onKeyPress(.leftArrow) {
        let folders = self.selectedFiles.filter(\.isFolder)
        folders.forEach { $0.expanded = false }
        return folders.isEmpty ? .ignored : .handled
      }
      .onKeyPress(.space) {
        if let s = self.selectedFile, s.isPreviewable {
          self.actions.previewFile(s)
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.downArrow, phases: .down) { press in
        guard press.modifiers.contains(.command) else { return .ignored }
        if let s = self.selectedFile, s.isFolder {
          self.folderPath = s.path
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.upArrow, phases: .down) { press in
        guard press.modifiers.contains(.command) else { return .ignored }
        // Not from a search's results, which aren't in the folder above, as Back isn't there either.
        if !self.folderPath.isEmpty && !self.isShowingSearchResults {
          self.folderPath.removeLast()
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.return) {
        guard !self.selection.isEmpty else {
          return .ignored
        }
        self.open(self.selectedFiles)
        return .handled
      }
      .overlay {
        if !model.filesLoaded || self.showFolderLoading {
          VStack {
            ProgressView()
              .controlSize(.large)
          }
          .frame(maxWidth: .infinity)
          .transition(.opacity)
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
      .serverThemedList(selected: self.selection, in: self.shownFiles)
      // A search's results, and a folder, as lists of their own, and not one changed into the
      // other, which the table under it can't always work out the rows' heights for, and which
      // starts the folder at its top.
      .id(self.isShowingSearchResults)
      // Where you've gone with the keys, kept in view.
      .onChange(of: self.selection) { _, newValue in
        if newValue.count == 1, let file = newValue.first {
          withAnimation {
            proxy.scrollTo(file, anchor: nil)
          }
        }
      }
    }
    // Into the folder under where it's dropped, as the list shows it, as it's dragged over it, or
    // else the folder you're in, shown around all of the list: what's uploaded, or moved there from
    // elsewhere on the server.
    .onDrop(of: [.fileURL, .hotlineServerItem], delegate: FileDrop(actions: self.actions, target: self.dropTarget, place: { location in
      self.listDropPlace(at: CGPoint(x: self.listFrame.minX + location.x, y: self.listFrame.minY + location.y))
    }))
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
      self.listFrame = frame
    }
    .environment(\.filePlaces, self.listPlaces)
    .overlay {
      if self.dropTarget.isRoot {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color(nsColor: self.theme?.selection ?? .controlAccentColor), lineWidth: 2)
          .padding(4)
          .allowsHitTesting(false)
      }
    }
    .contextMenu(forSelectionType: FileInfo.self) { items in
      self.fileMenu(for: self.shownFiles.filter(items.contains), inToolbar: false)
    } primaryAction: { items in
      self.open(self.shownFiles.filter(items.contains))
    }
  }

  // MARK: - Menus

  /// What can be done with files and folders: with what's selected, from the toolbar, or with what
  /// a menu on them is for, all of it, or with nothing, between them, in the folder you're in. What
  /// works on one thing, like Get Info, is off for more than one.
  @ViewBuilder
  private func fileMenu(for files: [FileInfo], inToolbar: Bool) -> some View {
    let single = files.count == 1 ? files.first : nil
    // Into the one folder it's for, or from the toolbar, or between files, the one you're in.
    let uploadFolder: [String]? = single?.isFolder == true ? single?.path : (inToolbar || files.isEmpty) ? self.folderPath : nil

    Button {
      self.uploadDestination = uploadFolder ?? self.folderPath
      self.uploadFileSelectorDisplayed = true
    } label: {
      Label("Upload...", systemImage: "arrow.up")
    }
    .disabled(uploadFolder == nil || self.model.access?.contains(.canUploadFiles) != true)

    Button {
      self.actions.download(files)
    } label: {
      Label("Download", systemImage: "arrow.down")
    }
    .disabled(!self.actions.canDownload(files))

    Divider()

    Button {
      self.actions.copyLinks(files)
    } label: {
      Label(files.count > 1 ? "Copy Links" : "Copy Link", systemImage: "link")
    }
    .disabled(files.isEmpty)

    Button {
      if let single {
        Task {
          if let details = await self.actions.getFileInfo(single) {
            self.fileDetails = details
          }
        }
      }
    } label: {
      Label("Get Info", systemImage: "info.circle")
    }
    .disabled(single == nil)

    Button {
      if let single {
        self.actions.previewFile(single)
      }
    } label: {
      Label("Quick Look", systemImage: "eye")
    }
    .disabled(single?.isPreviewable != true)

    Button {
      if let single {
        self.startRenaming(single)
      }
    } label: {
      Label("Rename", systemImage: "pencil")
    }
    .disabled(single.map { !self.actions.canRename($0) } ?? true)

    Button {
      // In the folder it's asked for on, or the one you're in.
      self.newFolderParent = !inToolbar && single?.isFolder == true ? single?.path ?? self.folderPath : self.folderPath
      self.newFolderShown = true
    } label: {
      Label("New Folder", systemImage: "folder.badge.plus")
    }
    .disabled((!inToolbar && !files.isEmpty && single?.isFolder != true) || self.model.access?.contains(.canCreateFolders) != true)

    Divider()

    Button {
      self.deleting = files
      self.confirmDeleteShown = true
    } label: {
      Label(files.count > 1 ? "Delete \(files.count) Items..." : single?.isFolder == true ? "Delete Folder..." : "Delete File...", systemImage: "trash")
    }
    .disabled(!self.actions.canDelete(files))
  }

  /// What's dropped at a point in the window, over the list, goes into: a folder it's over, or the
  /// open folder what it's over is shown in, as in the Finder's list, or else the folder you're in.
  private func listDropPlace(at point: CGPoint) -> (folder: [String], last: [String]?) {
    // Out to the row's edges, to the next row's.
    guard let file = self.listPlaces.file(at: point, slop: CGSize(width: 6, height: 4)) else {
      return (self.folderPath, nil)
    }
    let folder = file.isFolder ? file : self.shownFiles.first { $0.isFolder && $0.path == Array(file.path.dropLast()) }
    guard let folder, folder.path != self.folderPath else {
      return (self.folderPath, nil)
    }
    return (folder.path, FileDropTarget.lastShown(in: folder))
  }

  /// What Refresh lists again: the folders selected, or else the folder you're in, or the top, and the
  /// folders open in it in the list, as what's in them is shown too, but not a search's results.
  private var refreshPaths: [[String]] {
    let selected = self.selectedFiles.filter(\.isFolder).map(\.path)
    if !selected.isEmpty {
      return selected
    }
    guard !self.isShowingSearchResults else {
      return []
    }
    return [self.folderPath] + self.shownFiles.filter { $0.isFolder && $0.expanded }.map(\.path)
  }

  /// Lists again what Refresh is for, as the server has it now, keeping what hasn't changed as it
  /// was, and what's selected selected.
  private func refresh() {
    let paths = self.refreshPaths
    guard !paths.isEmpty else {
      return
    }
    Task {
      await self.model.refreshFileLists(paths)
      let selected = Set(self.selection.map(\.path))
      self.selection = Set(self.shownFiles.filter { selected.contains($0.path) })
    }
  }

  /// Renames it where it's shown, selected, as it's renamed.
  private func startRenaming(_ file: FileInfo) {
    self.renameClick?.cancel()
    self.renameClick = nil
    self.selection = [file]
    self.rename.start(file)
  }

  /// Gives it its new name on the server, and selects it as it's listed after, and a folder open in
  /// the list, open still, with what's in it listed under its new name.
  private func renamed(_ file: FileInfo, to name: String) async {
    let path = Array(file.path.dropLast()) + [name]
    guard await self.actions.rename(file, to: name) else {
      return
    }
    let renamed = self.shownFiles.first { $0.path == path }
    self.selection = Set([renamed].compactMap { $0 })
    if file.isFolder, file.expanded, let renamed {
      renamed.expanded = true
      let _ = try? await self.model.getFileList(path: path)
    }
  }

  /// What's opened, with a double click or Return: a folder, on its own, by going into it, and
  /// anything else, all of it, by downloading it.
  private func open(_ files: [FileInfo]) {
    if files.count == 1, let folder = files.first, folder.isFolder {
      self.folderPath = folder.path
      return
    }
    self.actions.download(files.filter { self.actions.canDownload([$0]) })
  }

  // MARK: - Computed Properties

  /// Whether there's room in the toolbar for the view buttons side by side, as there is with the
  /// files at least this wide, which leaves room for all the rest, and the Back button, with it, in
  /// a folder, as measured, and otherwise, they're a menu, which takes less.
  private var viewButtonsSideBySide: Bool {
    self.filesWidth >= (self.folderPath.isEmpty ? 480 : 520)
  }

  private var uploadDestinationName: String? {
    self.uploadDestination.last
  }

  /// What's shown, in the order it's shown: what's in the folder, or what a search found, and in
  /// the list, what's in the folders opened in it, under each.
  private var shownFiles: [FileInfo] {
    guard self.viewMode != "grid" else {
      return self.displayedFiles
    }
    var shown: [FileInfo] = []
    func add(_ files: [FileInfo]) {
      for file in files {
        shown.append(file)
        if file.isFolder, file.expanded, let children = file.children {
          add(children)
        }
      }
    }
    add(self.displayedFiles)
    return shown
  }

  /// What's selected, in the order it's shown, and not what's in a folder closed since.
  private var selectedFiles: [FileInfo] {
    self.shownFiles.filter(self.selection.contains)
  }

  /// What's selected, when it's one thing, for what works on one thing at a time.
  private var selectedFile: FileInfo? {
    let selected = self.selectedFiles
    return selected.count == 1 ? selected.first : nil
  }

  private func resolvePendingFileSelection() {
    guard let targetName = self.pendingFileSelection else { return }
    if let match = self.displayedFiles.first(where: { $0.name == targetName }) {
      print("[FileLink] Resolved pending selection: \(match.name)")
      self.pendingFileSelection = nil
      self.selection = [match]
      self.isFileListFocused = true
    }
  }

  private func consumeFileNavigationPath() {
    guard let path = self.serverState.fileNavigationPath else { return }
    self.serverState.fileNavigationPath = nil

    if path.isEmpty {
      return
    }

    // What the link's to, and not a search's results, even when it's in the folder searched.
    if self.isShowingSearchResults {
      self.model.cancelFileSearch()
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
