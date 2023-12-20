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
    WindowGroup {
      TrackerView()
    }
    WindowGroup(for: Server.self) { $server in
      if let s = server {
        ServerView(server: s)
          .frame(minWidth: 400, minHeight: 300)
          .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
      }
    }
    .defaultSize(width: 700, height: 800)

    #endif
  }
}
