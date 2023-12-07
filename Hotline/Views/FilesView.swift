import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  @State var fileList: [HotlineFile] = []
  
  var path: [String] = []
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt32) -> String {
    //    let bcf = ByteCountFormatter()
    FileListView.byteFormatter.allowedUnits = [.useAll]
    FileListView.byteFormatter.countStyle = .file
    return FileListView.byteFormatter.string(fromByteCount: Int64(fileSize))
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
  
  var body: some View {
    List {
      ForEach(fileList, id: \.self) { file in
        if file.isFolder {
          DisclosureGroup {
            if !fetched {
              ProgressView()
            }
            else {
              FileListView(path: [])
            }
          } label: {
            HStack {
              HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
                Image(systemName: "folder.fill")
              }
              .frame(minWidth: 25)
              Text(file.name).fontWeight(.medium)
              Spacer()
              Text("\(file.fileSize)").foregroundStyle(.secondary)
            }
          }
        }
        else {
          HStack {
            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
              Image(uiImage: fileIcon(name: file.name))
                .renderingMode(.template)
                .foregroundColor(.accentColor)
            }
            .frame(minWidth: 25)
            Text(file.name)
            Spacer()
            Text(formattedFileSize(file.fileSize)).foregroundStyle(.gray)
          }
        }
      }
    }
    .listStyle(.plain)
    .task {
      if !fetched {
        hotline.sendGetFileList() {
          print("FETCHED!")
          fetched = true
        } reply: {
          print("GOT FILES REPLY?")
          fileList = hotline.fileList
        }
      }
    }
  }
}

struct FilesView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
//  let fileList: [HotlineFile]
  
//  static let byteFormatter = ByteCountFormatter()
//  
//  private func formattedFileSize(_ fileSize: UInt32) -> String {
//    //    let bcf = ByteCountFormatter()
//    FilesView.byteFormatter.allowedUnits = [.useAll]
//    FilesView.byteFormatter.countStyle = .file
//    return FilesView.byteFormatter.string(fromByteCount: Int64(fileSize))
//  }
//  
//  private func fileIcon(name: String) -> UIImage {
//    //    func utTypeForFilename(_ filename: String) -> UTType? {
//    let fileExtension = (name as NSString).pathExtension
//    if let fileType = UTType(filenameExtension: fileExtension) {
//      print("\(name) \(fileExtension) = \(fileType)")
//      
//      if fileType.isSubtype(of: .movie) {
//        return UIImage(systemName: "play.rectangle")!
//      }
//      else if fileType.isSubtype(of: .image) {
//        return UIImage(systemName: "photo")!
//      }
//      else if fileType.isSubtype(of: .archive) {
//        return UIImage(systemName: "doc.zipper")!
//      }
//      else if fileType.isSubtype(of: .text) {
//        return UIImage(systemName: "doc.text")!
//      }
//      else {
//        return UIImage(systemName: "doc")!
//      }
//    }
//    
//    return UIImage(systemName: "doc")!
//  }
  
  var body: some View {
    NavigationStack {
      FileListView(path: [])
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(hotline.server?.name ?? "")
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            hotline.disconnect()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.hierarchical)
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
