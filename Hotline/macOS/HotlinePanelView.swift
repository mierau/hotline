import SwiftUI

struct HotlinePanelView: View {
  @Environment(\.openWindow) var openWindow
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: AppState.shared.activeServerState?.serverBanner ?? NSImage(named: "Default Banner")!)
        .interpolation(.high)
        .resizable()
        .scaledToFill()
        .frame(width: 468, height: 60)
        .frame(minWidth: 468, maxWidth: 468, minHeight: 60, maxHeight: 60)
        .clipped()
        .background(.black)
//        .clipShape(RoundedRectangle(cornerRadius: 6.0))
//        .padding([.top, .leading, .trailing], 4)
      
      HStack(spacing: 12) {
        Button {
          if NSEvent.modifierFlags.contains(.option) {
            openWindow(id: "server")
          }
          else {
            openWindow(id: "servers")
          }
        }
        label: {
          Image("Section Servers")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .help("Hotline Servers")

        Button {
          AppState.shared.activeServerState?.selection = .chat
        }
        label: {
          Image("Section Chat")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .disabled(AppState.shared.activeServerState == nil)
        .help("Public Chat")

        Button {
          AppState.shared.activeServerState?.selection = .board
        }
        label: {
          Image("Section Board")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .disabled(AppState.shared.activeServerState == nil)
        .help("Message Board")

        Button {
          AppState.shared.activeServerState?.selection = .news
        }
        label: {
          Image("Section News")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .disabled(AppState.shared.activeServerState == nil || (AppState.shared.activeHotline?.serverVersion ?? 0) < 151)
        .help("News")

        Button {
          AppState.shared.activeServerState?.selection = .files
        }
        label: {
          Image("Section Files")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .disabled(AppState.shared.activeServerState == nil)
        .help("Files")

        Spacer()

        if AppState.shared.activeHotline?.access?.contains(.canOpenUsers) == true {
          Button {
            AppState.shared.activeServerState?.selection = .accounts
          }
          label: {
            Image("Section Users")
              .resizable()
              .scaledToFit()
          }
          .buttonStyle(.plain)
          .frame(width: 20, height: 20)
          .disabled(AppState.shared.activeServerState == nil)
          .help("Accounts")
        }

        SettingsLink(label: {
          Image("Section Settings")
            .resizable()
            .scaledToFit()
        })
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .help("Settings")
      }
      .padding(.top, 12)
      .padding(.bottom, 12)
      .padding([.leading, .trailing], 12)
      .background(AppState.shared.activeServerState?.bannerColors.map { Color(nsColor: $0.backgroundColor) } ?? Color(nsColor: .controlBackgroundColor))
      .foregroundStyle(AppState.shared.activeServerState?.bannerColors.map { Color(nsColor: $0.primaryColor) } ?? Color.primary)
//      .background(Color.red.opacity(0.5).blendMode(.multiply))
      
//      GroupBox {
//        HStack(spacing: 0) {
//          Text("Not Connected")
//            .font(.system(size: 10.0))
//            .lineLimit(1)
//            .truncationMode(.tail)
//            .opacity(0.5)
//            .padding(.vertical, 0.0)
//            .padding(.horizontal, 4.0)
//          
//          Spacer()
//        }
//      }
//      .padding([.leading, .bottom, .trailing], 4.0)
    }
//    .frame(width: 468)
//    .background(colorScheme == .dark ? .black : .white)
//    .background(
//      VisualEffectView(material: .headerView, blendingMode: .behindWindow)
//        .cornerRadius(10.0)
//    )
  }
}

#Preview {
  HotlinePanelView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
