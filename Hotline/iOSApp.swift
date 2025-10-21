import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct Application: App {
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
    
  @FocusedValue(\.activeHotlineModel) private var activeHotline: Hotline?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  
  var body: some Scene {
    WindowGroup {
      TrackerView()
        .environment(model)
    }
  }
}
