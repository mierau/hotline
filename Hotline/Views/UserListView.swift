import SwiftUI

struct UserListView: View {
  @Environment(HotlineClient.self) private var hotline
  
  var body: some View {
    NavigationStack {
      List(hotline.userList) { u in
        Text("🤖 \(u.name)")
          .fontWeight(.medium)
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(u.isAdmin ? Color(hex: 0xE10000) : Color.accentColor)
          .opacity(u.isIdle ? 0.5 : 1.0)
      }
//      .listStyle(.grouped)
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
  ChatView()
    .environment(HotlineClient())
}
