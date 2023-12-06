import SwiftUI

struct FileListView: View {
  @State var files: [HotlineFile]
  
  var body: some View {
    Text("HI")
//    @Bindable var fls = files
//    List {
//      ForEach($fls, id: \.self) { f in
//        if f.isFolder {
//          DisclosureGroup(f.name, isExpanded: false)
//        }
//        else {
//          Text("HELLO")
//        }
//      }
//    }
  }
}

#Preview {
  FileListView(files: [
    HotlineFile(type: "fldr", creator: "", fileSize: 0, fileName: "Folder")
  ])
}
