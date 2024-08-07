import SwiftUI
import UniformTypeIdentifiers

struct FolderView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State var loading = false
  @State var dragOver = false
  
  var file: FileInfo
  let depth: Int
  
  @MainActor private func uploadFile(file fileURL: URL) {
    var filePath: [String] = [String](self.file.path)
    if !self.file.isFolder {
      filePath.removeLast()
    }
    
    print("UPLOADING TO PATH: ", filePath)
    
    model.uploadFile(url: fileURL, path: filePath) { info in
      Task {
        // Refresh file listing to display newly uploaded file.
        let _ = await model.getFileList(path: filePath)
      }
    }
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Spacer()
        .frame(width: CGFloat(depth * (12 + 2)))
      
      Button {
        if file.isFolder {
          file.expanded.toggle()
        }
      } label: {
        Text(Image(systemName: file.expanded ? "chevron.down" : "chevron.right"))
          .bold()
          .font(.system(size: 10))
          .foregroundStyle(dragOver ? Color.white : Color.primary)
          .opacity(0.5)
      }
      .buttonStyle(.plain)
      .frame(width: 10)
      .padding(.leading, 4)
      .padding(.trailing, 8)
      
      HStack(alignment: .center) {
        if file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .frame(width: 16, height: 16)
            .opacity(0.5)
        }
        else if file.isAdminDropboxFolder {
          Image("Admin Drop Box")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else if file.isDropboxFolder {
          Image("Drop Box")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else {
          Image("Folder")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 16)
      .padding(.trailing, 6)
      
      Text(file.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(dragOver ? Color.white : Color.primary)
        .opacity(file.isUnavailable ? 0.5 : 1.0)
      
      if loading {
        ProgressView().controlSize(.small).padding([.leading, .trailing], 5)
      }
      Spacer()
      if !file.isUnavailable {
        Text(file.fileSize == 0 ? "Empty" : "^[\(file.fileSize) \("file")](inflect: true)")
          .foregroundStyle(dragOver ? Color.white.opacity(0.75) : Color.secondary)
          .lineLimit(1)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 4.0)
        .fill(dragOver ? Color(nsColor: NSColor.selectedContentBackgroundColor) : Color.clear)
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
    )
    .onChange(of: file.expanded) {
      loading = false
      if file.expanded && file.fileSize > 0 {
        Task {
          loading = true
          let _ = await model.getFileList(path: file.path)
          loading = false
        }
      }
    }
    .onDrop(of: [.fileURL], isTargeted: $dragOver) { items in
      guard let item = items.first,
            let identifier = item.registeredTypeIdentifiers.first else {
        return false
      }
      
      item.loadItem(forTypeIdentifier: identifier, options: nil) { (urlData, error) in
        DispatchQueue.main.async {
          if let urlData = urlData as? Data,
             let fileURL = URL(dataRepresentation: urlData, relativeTo: nil, isAbsolute: true) {
            uploadFile(file: fileURL)
          }
        }
      }
      
      return true
    }
    
    if file.expanded {
      ForEach(file.children!, id: \.self) { childFile in
        if childFile.isFolder {
          FolderView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
        else {
          FileView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
      }
    }
  }
}

struct FileView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  var file: FileInfo
  let depth: Int
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Spacer()
        .frame(width: CGFloat(depth * (12 + 2)))
      
      Spacer()
        .frame(width: 10)
        .padding(.leading, 4)
        .padding(.trailing, 8)
      
      HStack(alignment: .center) {
        if file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .frame(width: 16, height: 16)
            .opacity(0.5)
        }
        else {
          FileIconView(filename: file.name, fileType: file.type)
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 16)
      .padding(.trailing, 6)
      
      Text(file.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(file.isUnavailable ? 0.5 : 1.0)

      Spacer()
      if !file.isUnavailable {
        Text(formattedFileSize(file.fileSize))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    if file.expanded {
      ForEach(file.children!, id: \.self) { childFile in
        if childFile.isFolder {
          FolderView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
        else {
          FileView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
      }
    }
  }
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt) -> String {
    FileView.byteFormatter.allowedUnits = [.useAll]
    FileView.byteFormatter.countStyle = .file
    return FileView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
}

struct FilesView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.openWindow) private var openWindow
  
  @State private var selection: FileInfo?
  @State private var fileDetails: FileDetails?
  @State private var uploadFileSelectorDisplayed: Bool = false
    
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
    guard !file.isFolder else {
      return
    }
    
    model.downloadFile(file.name, path: file.path)
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
      List(model.files, id: \.self, selection: $selection) { file in
        if file.isFolder {
          FolderView(file: file, depth: 0).tag(file.id)
        }
        else {
          FileView(file: file, depth: 0).tag(file.id)
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
          if let s = selectedFile, !s.isFolder {
            downloadFile(s)
          }
        } label: {
          Label("Download", systemImage: "arrow.down")
        }
        .disabled(selectedFile == nil || (selectedFile != nil && selectedFile!.isFolder))
        
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
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let selectedFile = selection, selectedFile.isPreviewable {
              previewFile(selectedFile)
            }
          } label: {
            Label("Preview", systemImage: "eye")
          }
          .help("Preview")
          .disabled(selection == nil || selection?.isPreviewable == false)
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let selectedFile = selection {
              getFileInfo(selectedFile)
            }
          } label: {
            Label("Get Info", systemImage: "info.circle")
          }
          .help("Get Info")
          .disabled(selection == nil)
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
            uploadFileSelectorDisplayed = true
          } label: {
            Label("Upload", systemImage: "arrow.up")
          }
          .help("Upload")
          .disabled(model.access?.contains(.canUploadFiles) != true)
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let selectedFile = selection, !selectedFile.isFolder {
              downloadFile(selectedFile)
            }
          } label: {
            Label("Download", systemImage: "arrow.down")
          }
          .help("Download")
          .disabled(selection == nil || selection?.isFolder == true || model.access?.contains(.canDownloadFiles) != true)
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
  }
}

#Preview {
  FilesView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
