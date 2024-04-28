import SwiftUI
import UniformTypeIdentifiers

struct FileView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State var expanded = false
  @State var loading = false
  
  var file: FileInfo
  let depth: Int
  
  var body: some View {
    HStack {
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
      }
      else {
        HStack {
          
        }.frame(width: 10)
          .padding(.leading, 4)
      }
      HStack(alignment: .center) {
        if file.isUnavailable {
          Image(systemName: "questionmark.app.fill").opacity(0.5)
        }
        else if file.isFolder {
          Image(systemName: "folder.fill")
        }
        else {
          FileIconView(filename: file.name)
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 15)
      Text(file.name).lineLimit(1).truncationMode(.tail).opacity(file.isUnavailable ? 0.5 : 1.0)
      
      if file.isFolder && loading {
        ProgressView().controlSize(.small).padding([.leading, .trailing], 1)
      }
      Spacer()
      if !file.isUnavailable {
        if file.isFolder {
          Text("^[\(file.fileSize) file](inflect: true)")
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
  
  var body: some View {
    NavigationStack {
      List(model.files, id: \.self, selection: $selection) { file in
        FileView(file: file, depth: 0).tag(file.id)
//          .environment(self.fileSelection)
//          .frame(height: 34)
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
          // ...
      } primaryAction: { items in
        guard let clickedFile = items.first else {
          return
        }
        
        self.selection = clickedFile
        if clickedFile.isFolder {
          clickedFile.expanded.toggle()
        }
        else {
          model.downloadFile(clickedFile.name, path: clickedFile.path)
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
          model.previewFile(s.name, path: s.path) { info in
            if let info = info {
              openPreviewWindow(info)
            }
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
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
          } label: {
            Label("Delete File", systemImage: "trash")
          }
          .help("Delete")
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let s = selection, !s.isFolder {
              model.previewFile(s.name, path: s.path) { info in
                if let info = info {
                  openPreviewWindow(info)
                }
              }
            }
          } label: {
            Label("Preview File", systemImage: "eye")
          }
          .help("Preview File")
          .disabled(selection?.isPreviewable == false)
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let s = selection {
              model.fileDetails(s.name, path: s.path) { info in
                fileDetails = info
              }
            }
          } label: {
            Label("Get File Info", systemImage: "info.circle")
          }
          .help("Get File Info")
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let s = selection, !s.isFolder {
              model.downloadFile(s.name, path: s.path)
            }
          } label: {
            Label("Download File", systemImage: "square.and.arrow.down")
          }
          .help("Download")
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
