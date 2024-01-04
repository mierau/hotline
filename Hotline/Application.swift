import SwiftUI
import SwiftData

@main
struct Application: App {
  #if os(iOS)
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  #endif
  
  #if os(macOS)
  @Environment(\.openWindow) private var openWindow
  #endif
  
  @State private var preferences = Prefs()
  
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
    }
    .defaultSize(width: 700, height: 550)
    .defaultPosition(.center)
    
    WindowGroup(id: "server", for: Server.self) { $server in
      ServerView(server: $server)
        .frame(minWidth: 400, minHeight: 300)
        .environment(preferences)
    }
    .defaultSize(width: 750, height: 700)
    .defaultPosition(.center)
    .commands {
      CommandGroup(replacing: CommandGroupPlacement.newItem) {
        Button("Connect to Server...") {
          openWindow(id: "server")
        }
        .keyboardShortcut(.init("K"), modifiers: .command)
      }
    }
    
    Settings {
      SettingsView()
        .environment(preferences)
    }

    #endif
  }
}
