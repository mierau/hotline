import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(iOS)

@main
struct Application: App {
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  
  @State private var preferences = Prefs()
  @State private var soundEffects = SoundEffectPlayer()
  @State private var bookmarks = Bookmarks()
  
  @FocusedValue(\.activeHotlineModel) private var activeHotline: Hotline?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  
  var body: some Scene {
    WindowGroup {
      TrackerView()
        .environment(model)
    }
  }
}

#endif
