import SwiftUI

struct FileListView: View {
  var item: HotlineFile
  
  var body: some View {
    List {
      ForEach(item.files) { f in
        if f.isFolder {
          DisclosureGroup(f.name, isExpanded: false)
        }
        else {
          Text("HELLO")
        }
      }
    }
  }
}

#Preview {
  FileListView(item: HotlineFile(type: "fldr", creator: "", fileSize: 0, fileName: "Folder"))
}
