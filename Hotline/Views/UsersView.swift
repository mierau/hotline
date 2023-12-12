import SwiftUI

struct UsersView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  var body: some View {
    NavigationStack {
      List(model.users) { u in
        Text("🤖 \(u.name)")
          .fontWeight(.medium)
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(u.status.contains(.admin) ? Color(hex: 0xE10000) : Color.accentColor)
          .opacity(u.status.contains(.idle) ? 0.5 : 1.0)
      }
//      .listStyle(.grouped)
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
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
