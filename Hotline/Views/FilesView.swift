import SwiftUI

struct FilesView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  var body: some View {
    List(hotline.fileList) {
      FileListView(item: $0)
    }
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
