import SwiftUI
import UniformTypeIdentifiers

struct FileView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State var expanded = false
  @State var loading = false
  
  var file: FileInfo
  let depth: Int
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      if file.isFolder {
        Button {
          if file.isFolder {
            file.expanded.toggle()
          }
        } label: {
          Text(Image(systemName: file.expanded ? "chevron.down" : "chevron.right"))
            .bold()
            .font(.system(size: 10))
            .opacity(0.5)
        }
        .buttonStyle(.plain)
        .frame(width: 10)
        .padding(.leading, 4)
        .padding(.trailing, 8)
      }
      else {
        Spacer()
          .frame(width: 10)
          .padding(.leading, 4)
          .padding(.trailing, 8)
      }
      
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
        else if file.isFolder {
          Image("Folder")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
//          FolderIconView(dropbox: file.isUploadFolder)
//            .frame(width: 16, height: 16)
        }
        else {
          FileIconView(filename: file.name)
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 16)
      .padding(.trailing, 6)
      
      Text(file.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(file.isUnavailable ? 0.5 : 1.0)
      
      if file.isFolder && loading {
        ProgressView().controlSize(.small).padding([.leading, .trailing], 1)
      }
      Spacer()
      if !file.isUnavailable {
        if file.isFolder {
          Text(file.fileSize == 0 ? "Empty" : "^[\(file.fileSize) \("file")](inflect: true)")
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.trailing, 6)
        }
        else {
          Text(formattedFileSize(file.fileSize)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.leading, CGFloat(depth * (12 + 10)))
    .onChange(of: file.expanded) {
      loading = false
      if file.isFolder && file.fileSize > 0 {
        if file.expanded {
          Task {
            loading = true
            let _ = await model.getFileList(path: file.path)
            loading = false
          }
        }
      }
    }
    
    if file.expanded {
      ForEach(file.children!, id: \.self) { childFile in
        FileView(file: childFile, depth: self.depth + 1).tag(file.id)
//          .environment(self.selectedFile)
//            .frame(height: 34)
      }
    }
  }
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt) -> String {
    //    let bcf = ByteCountFormatter()
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
    
  private func openPreviewWindow(_ previewInfo: PreviewFileInfo) {
    switch previewInfo.previewType {
    case .image:
      openWindow(id: "preview-image", value: previewInfo)
    case .text:
      openWindow(id: "preview-text", value: previewInfo)
    default:
      return
    }
//    let _ = FilePreviewWindowController(info: previewInfo)
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
        FileView(file: file, depth: 0).tag(file.id)
      }
      .environment(\.defaultMinListRowHeight, 34)
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
//        ToolbarItem(placement: .primaryAction) {
//          Button {
//          } label: {
//            Label("Delete", systemImage: "trash")
//          }
//          .help("Delete")
//          .disabled(true)
//        }
        
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
            if let selectedFile = selection, !selectedFile.isFolder {
              downloadFile(selectedFile)
            }
          } label: {
            Label("Download", systemImage: "arrow.down")
          }
          .help("Download")
          .disabled(selection == nil || selection?.isFolder == true)
        }
      }
    }
    .sheet(item: $fileDetails ) { item in
      FileDetailsView(fd: item)
    }
  }
}

#Preview {
  FilesView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
