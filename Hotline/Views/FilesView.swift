import SwiftUI

struct FilesView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        List(hotline.userList) { u in
          HStack(alignment: .firstTextBaseline) {
            Text(u.name).bold().foregroundStyle(u.isAdmin ? Color.red : Color.black)
          }
        }
        .padding()
      }
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
