import SwiftUI

private let gridColumnSpacing: CGFloat = 12
private let gridPadding: CGFloat = 24
private let gridColumnMin: CGFloat = 100
private let gridColumnMax: CGFloat = 120

struct FileGridItemView: View {
  let file: FileInfo
  let isSelected: Bool
  let isDragTarget: Bool

  var body: some View {
    VStack(spacing: 2) {
      Group {
        if self.file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .resizable()
            .scaledToFit()
        }
        else if self.file.isFolder {
          if self.file.isAdminDropboxFolder {
            Image("Admin Drop Box Large")
              .resizable()
              .scaledToFit()
          }
          else if self.file.isDropboxFolder {
            Image("Drop Box Large")
              .resizable()
              .scaledToFit()
          }
          else {
            Image("Folder Large")
              .resizable()
              .scaledToFit()
          }
        }
        else {
          FileIconView(filename: self.file.name, fileType: self.file.type)
        }
      }
      .frame(width: 48, height: 48)
      .padding(4)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(self.isSelected ? Color(nsColor: .tertiaryLabelColor).opacity(0.3) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.accentColor.opacity(0.15))
          .opacity(self.isDragTarget ? 1 : 0)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(Color.accentColor, lineWidth: 2)
          .opacity(self.isDragTarget ? 1 : 0)
      )

      Text(self.file.name)
        .font(.subheadline)
        .lineLimit(2)
        .truncationMode(.middle)
        .multilineTextAlignment(.center)
        .foregroundStyle(self.isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(self.isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
        )
        .frame(width: 90, alignment: .center)
        .help(self.file.name.count > 10 ? self.file.name : "")
    }
    .opacity(self.file.isUnavailable ? 0.5 : 1.0)
    .frame(width: 100, height: 90, alignment: .top)
  }
}

struct FilesGridView: View {
  @Environment(HotlineState.self) private var model: HotlineState

  @Binding var selection: FileInfo?
  @Binding var folderPath: [String]
  @Binding var fileDetails: FileDetails?
  @Binding var confirmDeleteShown: Bool
  @Binding var uploadFileSelectorDisplayed: Bool
  @Binding var newFolderShown: Bool

  var actions: FileActions
  var isShowingSearchResults: Bool
  @Binding var folderLoading: Bool

  @State private var showSpinner: Bool = false
  @State private var dragOver: Bool = false
  @State private var gridWidth: CGFloat = 0
  @State private var didSelectItem: Bool = false
  @State private var dropTargetFileID: FileInfo.ID? = nil
  @State private var springLoadTask: Task<Void, Never>? = nil

  private var columnsPerRow: Int {
    let available = self.gridWidth - (gridPadding * 2)
    return max(1, Int((available + gridColumnSpacing) / (gridColumnMin + gridColumnSpacing)))
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: gridColumnMin, maximum: gridColumnMax), spacing: gridColumnSpacing)],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(self.currentItems, id: \.self) { file in
              self.gridItemView(for: file)
                .id(file.id)
            }
          }
          .padding(gridPadding)
        }
        .onChange(of: self.selection) { _, newValue in
          if let file = newValue {
            withAnimation {
              proxy.scrollTo(file.id, anchor: nil)
            }
          }
        }
      }
      .contentShape(Rectangle())
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            DispatchQueue.main.async {
              if !self.didSelectItem {
                self.selection = nil
              }
            }
          }
          .onEnded { _ in
            self.didSelectItem = false
          }
      )
      .contextMenu {
        self.itemContextMenu(for: nil)
      }
      .background(
        GeometryReader { geo in
          Color.clear
            .onAppear { self.gridWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, newWidth in self.gridWidth = newWidth }
        }
      )
    }
    .focusable()
    .focusEffectDisabled()
    .onDrop(of: [.fileURL], isTargeted: self.$dragOver) { items in
      guard self.model.access?.contains(.canUploadFiles) == true else {
        return false
      }

      return self.actions.upload(droppedItems: items, to: self.folderPath)
    }
    .task(id: self.folderLoading) {
      if self.folderLoading {
        self.showSpinner = false
        try? await Task.sleep(for: .seconds(1))
        if self.folderLoading {
          withAnimation(.easeIn(duration: 0.2)) {
            self.showSpinner = true
          }
        }
      } else {
        withAnimation(.easeOut(duration: 0.2)) {
          self.showSpinner = false
        }
      }
    }
    .overlay {
      if self.showSpinner || (!self.model.filesLoaded && self.folderPath.isEmpty) {
        VStack {
          ProgressView()
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
      }
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
    .onKeyPress(.space) {
      if let s = self.selection, s.isPreviewable {
        self.actions.previewFile(s)
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in
      self.moveSelectionHorizontally(by: 1)
    }
    .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in
      self.moveSelectionHorizontally(by: -1)
    }
    .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
      if press.modifiers.contains(.command) {
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
      return self.moveSelectionVertically(by: 1)
    }
    .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
      if press.modifiers.contains(.command) {
        if !self.folderPath.isEmpty && !self.isShowingSearchResults {
          self.folderPath.removeLast()
          return .handled
        }
        return .ignored
      }
      return self.moveSelectionVertically(by: -1)
    }
  }

  @ViewBuilder
  private func gridItemView(for file: FileInfo) -> some View {
    let view = FileGridItemView(file: file, isSelected: self.selection == file, isDragTarget: self.dropTargetFileID == file.id)
      .padding(6)
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            self.didSelectItem = true
            self.selection = file
          }
      )
      .simultaneousGesture(
        TapGesture(count: 2)
          .onEnded {
            if file.isFolder {
              self.folderPath = file.path
            }
            else {
              self.actions.downloadFile(file)
            }
          }
      )
      .contextMenu {
        self.itemContextMenu(for: file)
      }

    if file.isFolder {
      view
        .onDrop(of: [.fileURL], isTargeted: self.dropTargetBinding(for: file)) { items in
          guard self.model.access?.contains(.canUploadFiles) == true else {
            return false
          }

          return self.actions.upload(droppedItems: items, to: file.path)
        }
    }
    else {
      view
    }
  }

  @ViewBuilder
  private func itemContextMenu(for file: FileInfo?) -> some View {
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
    .onAppear {
      if let file = file {
        self.selection = file
      }
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
  }

  private func dropTargetBinding(for file: FileInfo) -> Binding<Bool> {
    Binding(
      get: { self.dropTargetFileID == file.id },
      set: { newValue in
        let newID = newValue ? file.id : nil
        if self.dropTargetFileID != newID {
          self.dropTargetFileID = newID
          self.springLoadTask?.cancel()
          self.springLoadTask = nil

          if newValue {
            self.springLoadTask = Task {
              try? await Task.sleep(for: .seconds(0.8))
              guard !Task.isCancelled else { return }
              self.folderPath = file.path
            }
          }
        }
      }
    )
  }

  private func moveSelectionHorizontally(by offset: Int) -> KeyPress.Result {
    let items = self.currentItems
    guard !items.isEmpty else { return .handled }

    guard let current = self.selection, let index = items.firstIndex(of: current) else {
      self.selection = items.first
      return .handled
    }

    let newIndex = index + offset
    guard newIndex >= 0, newIndex < items.count else {
      return .handled
    }

    // Don't wrap across rows
    let cols = self.columnsPerRow
    if index / cols != newIndex / cols {
      return .handled
    }

    self.selection = items[newIndex]
    return .handled
  }

  private func moveSelectionVertically(by rows: Int) -> KeyPress.Result {
    let items = self.currentItems
    let cols = self.columnsPerRow
    guard !items.isEmpty else { return .handled }

    guard let current = self.selection, let index = items.firstIndex(of: current) else {
      self.selection = items.first
      return .handled
    }

    let newIndex = index + (rows * cols)

    // Exact target exists
    if newIndex >= 0, newIndex < items.count {
      self.selection = items[newIndex]
      return .handled
    }

    // Moving down: snap to last item if there's a partial row below
    if rows > 0, newIndex >= items.count {
      let lastIndex = items.count - 1
      // Only snap if the last item is on a row below the current one
      if lastIndex / cols > index / cols {
        self.selection = items[lastIndex]
      }
      return .handled
    }

    return .handled
  }

  private var currentItems: [FileInfo] {
    if self.isShowingSearchResults {
      return self.model.fileSearchResults
    }

    if self.folderPath.isEmpty {
      return self.model.files
    }

    return self.findFolder(in: self.model.files, at: self.folderPath)?.children ?? []
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
}
