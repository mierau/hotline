import SwiftUI

struct UserListView: View {
  @Environment(HotlineClient.self) private var hotline
  
  var body: some View {
    VStack(spacing: 0) {
      List(hotline.userList) { u in
        HStack(alignment: .firstTextBaseline) {
          Text(u.name).bold().foregroundStyle(u.isAdmin ? Color.red : Color.black).opacity(u.isIdle ? 0.5 : 1.0)
        }
      }
      .listStyle(.plain)
      .padding()
    }
  }
}

#Preview {
  ChatView()
    .environment(HotlineClient())
}
