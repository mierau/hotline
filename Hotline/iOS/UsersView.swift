import SwiftUI

struct UsersView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  var body: some View {
    NavigationStack {
      List(model.users) { u in
        HStack(alignment: .center, spacing: 4) {
          HStack(alignment: .center, spacing: 0) {
            if let iconImage = Hotline.getClassicIcon(Int(u.iconID)) {
              Image(uiImage: iconImage)
                .interpolation(.none)
                .frame(width: 32, height: 16, alignment: .center)
                .scaledToFit()
            }
          }
          .frame(width: 32)
          Text(u.name)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(u.isAdmin ? Color(hex: 0xE10000) : Color.accentColor)
        }
        .opacity(u.isIdle ? 0.5 : 1.0)
      }
      .scrollBounceBehavior(.basedOnSize)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.serverTitle)
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
