import SwiftUI
import UniformTypeIdentifiers
import AppKit





struct FilesView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.openWindow) private var openWindow
  
  @State private var selection: FileInfo?
  @State private var fileDetails: FileDetails?
  @State private var uploadFileSelectorDisplayed: Bool = false
  @State private var searchText: String = ""
  @State private var isSearching: Bool = false

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
    isShowingSearchResults ? model.fileSearchResults : model.files
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
    
  private func openPreviewWindow(_ previewInfo: PreviewFileInfo) {
    switch previewInfo.previewType {
    case .image:
      openWindow(id: "preview-image", value: previewInfo)
    case .text:
      openWindow(id: "preview-text", value: previewInfo)
    default:
      return
    }
  }
  
  @MainActor private func getFileInfo(_ file: FileInfo) {
    Task {
      if let fileInfo = await model.getFileDetails(file.name, path: file.path) {
        Task { @MainActor in
          self.fileDetails = fileInfo
        }
      }
    }
  }
  
  @MainActor private func downloadFile(_ file: FileInfo) {
    if file.isFolder {
      model.downloadFolder(file.name, path: file.path)
    }
    else {
      model.downloadFile(file.name, path: file.path)
    }
  }
  
  @MainActor private func uploadFile(file fileURL: URL, to path: [String]) {
    model.uploadFile(url: fileURL, path: path) { info in
      Task {
        // Refresh file listing to display newly uploaded file.
        let _ = await model.getFileList(path: path)
      }
    }
  }
  
  @MainActor private func previewFile(_ file: FileInfo) {
    guard file.isPreviewable else {
      return
    }
  
    model.previewFile(file.name, path: file.path) { info in
      if let info = info {
        openPreviewWindow(info)
      }
    }
  }
  
  private func deleteFile(_ file: FileInfo) async {
    var parentPath: [String] = []
    if file.path.count > 1 {
      parentPath = Array(file.path[0..<file.path.count-1])
    }
    
    if await model.deleteFile(file.name, path: file.path) {
      let _ = await model.getFileList(path: parentPath)
    }
  }
  
  var body: some View {
    NavigationStack {
      List(displayedFiles, id: \.self, selection: $selection) { file in
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
      .task {
        if !model.filesLoaded {
          let _ = await model.getFileList()
        }
      }
      .contextMenu(forSelectionType: FileInfo.self) { items in
        let selectedFile = items.first
        
        Button {
          if let s = selectedFile {
            downloadFile(s)
          }
        } label: {
          Label("Download", systemImage: "arrow.down")
        }
        .disabled(selectedFile == nil)
        
        Divider()
                
        Button {
          if let s = selectedFile {
            getFileInfo(s)
          }
        } label: {
          Label("Get Info", systemImage: "info.circle")
        }
        .disabled(selectedFile == nil)
        
        Button {
          if let s = selectedFile {
            previewFile(s)
          }
        } label: {
          Label("Preview", systemImage: "eye")
        }
        .disabled(selectedFile == nil || (selectedFile != nil && !selectedFile!.isPreviewable))
        
        if model.access?.contains(.canDeleteFiles) == true {
          Divider()
          
          Button {
            if let s = selectedFile {
              Task {
                await deleteFile(s)
              }
            }
          } label: {
            Label("Delete", systemImage: "trash")
          }
          .disabled(selectedFile == nil)
        }
      } primaryAction: { items in
        guard let clickedFile = items.first else {
          return
        }
        
        self.selection = clickedFile
        if clickedFile.isFolder {
          clickedFile.expanded.toggle()
        }
        else {
          downloadFile(clickedFile)
        }
      }
      .onKeyPress(.rightArrow) {
        if let s = selection, s.isFolder {
          s.expanded = true
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.leftArrow) {
        if let s = selection, s.isFolder {
          s.expanded = false
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.space) {
        if let s = selection, s.isPreviewable {
          previewFile(s)
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
      .searchable(text: $searchText, isPresented: $isSearching, placement: .automatic, prompt: "Search")
      .background(Button("", action: { isSearching = true }).keyboardShortcut("f").hidden())
      .toolbar {
        ToolbarItemGroup(placement: .automatic) {
          Button {
            if let selectedFile = selection, selectedFile.isPreviewable {
              previewFile(selectedFile)
            }
          } label: {
            Label("Preview", systemImage: "eye")
          }
          .help("Preview")
          .disabled(selection == nil || selection?.isPreviewable == false)

          Button {
            if let selectedFile = selection {
              getFileInfo(selectedFile)
            }
          } label: {
            Label("Get Info", systemImage: "info.circle")
          }
          .help("Get Info")
          .disabled(selection == nil)

          Button {
            uploadFileSelectorDisplayed = true
          } label: {
            Label("Upload", systemImage: "arrow.up")
          }
          .help("Upload")
          .disabled(
            model.access?.contains(.canUploadFiles) != true ||
            (model.fileSearchStatus.isActive && !(selection?.isFolder ?? false))
          )

          Button {
            if let selectedFile = selection {
              downloadFile(selectedFile)
            }
          } label: {
            Label("Download", systemImage: "arrow.down")
          }
          .help("Download")
          .disabled(selection == nil || model.access?.contains(.canDownloadFiles) != true)
        }
      }
    }
    .sheet(item: $fileDetails ) { item in
      FileDetailsView(fd: item)
    }
    .fileImporter(isPresented: $uploadFileSelectorDisplayed, allowedContentTypes: [.data], allowsMultipleSelection: false, onCompletion: { results in
      switch results {
      case .success(let fileURLS):
        guard fileURLS.count > 0 else {
          return
        }
        
        let fileURL = fileURLS.first!

        print(fileURL)
        
        var uploadPath: [String] = []
        
        if let selection = selection {
          if selection.isFolder {
            uploadPath = selection.path
          }
          else {
            uploadPath = Array<String>(selection.path)
            uploadPath.removeLast()
          }
        }
        
        print("UPLOAD PATH: \(uploadPath)")
        uploadFile(file: fileURL, to: uploadPath)
        
      case .failure(let error):
        print(error)
      }
    })
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
      model.startFileSearch(query: trimmed)
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
//              .fontWeight(.semibold)
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
  }
}

#Preview {
  FilesView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
