import SwiftUI
import SwiftData

@main
struct HotlineApp: App {
  @State private var appState = HotlineState()
  
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  
  var body: some Scene {
    WindowGroup {
      TrackerView()
        .environment(appState)
        .environment(model)
    }
  }
}
