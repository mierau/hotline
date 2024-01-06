import SwiftUI
import UniformTypeIdentifiers

struct FileView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State var expanded = false
  
  var file: FileInfo
  
  var body: some View {
    if file.isFolder {
      DisclosureGroup(isExpanded: $expanded) {
        ForEach(file.children!) { childFile in
          FileView(file: childFile)
            .frame(height: 44)
        }
      } label: {
        HStack {
          HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
            Image(systemName: "folder.fill")
          }
          .frame(minWidth: 25)
          Text(file.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
          Spacer()
          Text("\(file.fileSize)").foregroundStyle(.secondary).lineLimit(1)
        }
      }
      .onChange(of: expanded) {
        if !expanded {
          return
        }
        
        // Some servers don't reply when asking for the contents of an empty folder.
        if file.isFolder && file.fileSize == 0 {
          return
        }
        
        Task {
          await model.getFileList(path: file.path)
        }
      }
    }
    else {
      HStack {
        HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
          fileIcon(name: file.name)
            .renderingMode(.template)
        }
        .frame(minWidth: 25)
        Text(file.name).lineLimit(1).truncationMode(.tail)
        Spacer()
        Text(formattedFileSize(file.fileSize)).foregroundStyle(.secondary).lineLimit(1)
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
    //    func utTypeForFilename(_ filename: String) -> UTType? {
    let fileExtension = (name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      print("\(name) \(fileExtension) = \(fileType)")
      
      if fileType.isSubtype(of: .movie) {
        return Image(systemName: "play.rectangle")
//        return UIImage(systemName: "play.rectangle")!
      }
      else if fileType.isSubtype(of: .image) {
        return Image(systemName: "photo")
//        return UIImage(systemName: "photo")!
      }
      else if fileType.isSubtype(of: .archive) {
        return Image(systemName: "doc.zipper")
//        return UIImage(systemName: "doc.zipper")!
      }
      else if fileType.isSubtype(of: .text) {
        return Image(systemName: "doc.text")
//        return UIImage(systemName: "doc.text")!
      }
      else {
        return Image(systemName: "doc")
//        return UIImage(systemName: "doc")!
      }
    }
    
    return Image(systemName: "doc")
  }
}

struct FilesView: View {
  @Environment(Hotline.self) private var model: Hotline
    
  @State var initialLoadComplete = false
  
  var body: some View {
    NavigationStack {
      List(model.files) { file in
        FileView(file: file)
          .frame(height: 44)
      }
      .task {
        if !initialLoadComplete {
          let _ = await model.getFileList()
          initialLoadComplete = true
        }
      }
      .overlay {
        if !initialLoadComplete {
          VStack {
            ProgressView()
              .controlSize(.large)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .listStyle(.plain)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.serverTitle)
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            model.disconnect()
          } label: {
            Text(Image(systemName: "xmark.circle.fill"))
              .symbolRenderingMode(.hierarchical)
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }
}

#Preview {
  FilesView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
