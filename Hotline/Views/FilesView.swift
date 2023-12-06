import SwiftUI

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
  
  var body: some View {
    List(hotline.fileList, id: \.self, children: \.files) { tree in
      HStack {
        if tree.isFolder {
          Image(systemName: "folder")
          Text(tree.name).bold()
          Spacer()
          Text("\(tree.fileSize)").foregroundStyle(.gray)
        }
        else {
          Image(systemName: "doc")
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
  }
}

#Preview {
  FilesView()
    .environment(HotlineClient())
}
