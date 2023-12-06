import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt32) -> String {
//    let bcf = ByteCountFormatter()
    FilesView.byteFormatter.allowedUnits = [.useAll]
    FilesView.byteFormatter.countStyle = .file
    return FilesView.byteFormatter.string(fromByteCount: Int64(fileSize))
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
    NavigationStack {
      List(hotline.fileList, id: \.self, children: \.files) { tree in
        HStack {
          if tree.isFolder {
            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
              Image(systemName: "folder.fill")
            }
            .frame(minWidth: 25)
            Text(tree.name).bold()
            Spacer()
            Text("\(tree.fileSize)").foregroundStyle(.gray)
          }
          else {
            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
              Image(uiImage: fileIcon(name: tree.name))
            }
            .frame(minWidth: 25)
            Text(tree.name).bold()
            Spacer()
            Text(formattedFileSize(tree.fileSize)).foregroundStyle(.gray)
          }
        }
      }
      .listStyle(.plain)
      .task {
        if !fetched {
          hotline.sendGetFileList() {
            fetched = true
          }
        }
      }
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
