import SwiftUI
import UniformTypeIdentifiers

struct FileView: View {
//  @Environment(HotlineClient.self) private var hotline
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
        Task {
          await model.getFileList(path: file.path)
        }
      }
    }
    else {
      HStack {
        HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
          Image(uiImage: fileIcon(name: file.name))
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
  
  private func fileIcon(name: String) -> UIImage {
    //    func utTypeForFilename(_ filename: String) -> UTType? {
    let fileExtension = (name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      print("\(name) \(fileExtension) = \(fileType)")
      
      if fileType.isSubtype(of: .movie) {
        return UIImage(systemName: "play.rectangle")!
      }
      else if fileType.isSubtype(of: .image) {
        return UIImage(systemName: "photo")!
      }
      else if fileType.isSubtype(of: .archive) {
        return UIImage(systemName: "doc.zipper")!
      }
      else if fileType.isSubtype(of: .text) {
        return UIImage(systemName: "doc.text")!
      }
      else {
        return UIImage(systemName: "doc")!
      }
    }
    
    return UIImage(systemName: "doc")!
  }
}

struct FilesView: View {
//  @Environment(HotlineClient.self) private var hotline
  @Environment(Hotline.self) private var model: Hotline
    
  @State var initialLoad = false
  
  var body: some View {
    NavigationStack {
      List(model.files) { file in
        FileView(file: file)
          .frame(height: 44)
      }
      .task {
        if !initialLoad {
          let _ = await model.getFileList()
          initialLoad = true
        }
      }
      .listStyle(.plain)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.server?.name ?? "")
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
    .environment(HotlineClient())
}
