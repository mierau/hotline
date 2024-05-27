import SwiftUI

struct HotlinePanelView: View {
  @Environment(\.openWindow) var openWindow
  @Environment(\.colorScheme) var colorScheme
  
  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: ApplicationState.shared.activeServerBanner ?? NSImage(named: "Default Banner")!)
        .interpolation(.high)
        .resizable()
        .scaledToFit()
        .frame(width: 468, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6.0))
        .padding([.top, .leading, .trailing], 4)
      
      HStack(spacing: 16) {
        Button {
          if NSEvent.modifierFlags.contains(.option) {
            openWindow(id: "server")
          }
          else {
            openWindow(id: "servers")
          }
        }
        label: {
          Image(systemName: "globe.americas.fill")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .help("Hotline Servers")
        
        Button {
          ApplicationState.shared.activeServerState?.selection = .chat
        }
        label: {
          Image(systemName: "bubble.fill")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .opacity(ApplicationState.shared.activeServerState == nil ? 0.5 : 1.0)
        .disabled(ApplicationState.shared.activeServerState == nil)
        .help("Public Chat")
        
        Button {
          ApplicationState.shared.activeServerState?.selection = .board
        }
        label: {
          Image(systemName: "pin.fill")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .opacity(ApplicationState.shared.activeServerState == nil ? 0.5 : 1.0)
        .disabled(ApplicationState.shared.activeServerState == nil)
        .help("Message Board")
        
        Button {
          ApplicationState.shared.activeServerState?.selection = .news
        }
        label: {
          Image(systemName: "newspaper.fill")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .opacity(ApplicationState.shared.activeServerState == nil ? 0.5 : 1.0)
        .disabled(ApplicationState.shared.activeServerState == nil)
        .help("News")
        
        Button {
          ApplicationState.shared.activeServerState?.selection = .files
        }
        label: {
          Image(systemName: "folder.fill")
            .resizable()
            .scaledToFit()
        }
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .opacity(ApplicationState.shared.activeServerState == nil ? 0.5 : 1.0)
        .disabled(ApplicationState.shared.activeServerState == nil)
        .help("Files")
        
        Spacer()
        
        SettingsLink(label: {
          Image(systemName: "gearshape.fill")
            .resizable()
            .scaledToFit()
        })
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .help("Settings")
      }
      .padding(.top, 16)
      .padding(.bottom, 16)
      .padding([.leading, .trailing], 16)
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
