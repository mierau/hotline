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
        if file.isFolder {
          Image(systemName: "folder.fill")
        }
        else {
          fileIcon(name: file.name)
            .resizable()
            .aspectRatio(contentMode: .fit)
//            .scaledToFill()
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 15)
      Text(file.name).lineLimit(1).truncationMode(.tail)
      if file.isFolder && loading {
        ProgressView().controlSize(.small).padding([.leading, .trailing], 1)
      }
      Spacer()
      if file.isFolder {
        Text("^[\(file.fileSize) file](inflect: true)")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      else {
        Text(formattedFileSize(file.fileSize)).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.leading, CGFloat(depth * (12 + 10)))
    .onChange(of: file.expanded) {
      loading = false
      if file.isFolder {
        print("EXPANDED \(file.name)? \(expanded)")
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
  
  private func fileIcon(name: String) -> Image {
    let fileExtension = (name as NSString).pathExtension
    return Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? UTType.content))
  }
}

struct FilesView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var selection: FileInfo?
  
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
        print("ITEMS?", items)
        guard let clickedFile = items.first else {
          return
        }
        
        self.selection = clickedFile
        if clickedFile.isFolder {
          clickedFile.expanded.toggle()
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
            Label("Download File", systemImage: "square.and.arrow.down")
          }
          .help("Download")
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
          } label: {
            Label("Preview File", systemImage: "eye")
          }
          .help("Preview")
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button {
          } label: {
            Label("Delete File", systemImage: "trash")
          }
          .help("Delete")
        }
      }
    }
  }
}

#Preview {
  FilesView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
