import SwiftUI
import SwiftData

@main
struct Application: App {
  #if os(iOS)
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  #endif
  
  var body: some Scene {
    #if os(iOS)
    WindowGroup {
      TrackerView()
        .environment(model)
    }
    #elseif os(macOS)
    Window("Servers", id: "servers") {
      TrackerView()
        .frame(minWidth: 250, minHeight: 250)
        .toolbar {
          ToolbarItem(placement: .navigation) {
            Image("Hotline")
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .foregroundColor(Color(hex: 0xE10000))
              .frame(width: 9)
          }
        }
    }
    .defaultSize(width: 700, height: 600)
    .defaultPosition(.center)
    
    WindowGroup(for: Server.self) { $server in
      if let s = server {
        ServerView(server: s)
          .frame(minWidth: 400, minHeight: 300)
          .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
      }
    }
    .defaultSize(width: 700, height: 800)
    .defaultPosition(.center)

    #endif
  }
}
