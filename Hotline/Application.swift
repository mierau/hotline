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
    // MARK: Tracker Window
    Window("Servers", id: "servers") {
      TrackerView()
        .frame(minWidth: 250, minHeight: 250)
    }
    .keyboardShortcut(.init(.init("R"), modifiers: .command))
    .defaultSize(width: 700, height: 550)
    .defaultPosition(.center)
        
    // MARK: Server Window
    WindowGroup(id: "server", for: Server.self) { $server in
      ServerView(server: $server)
        .frame(minWidth: 400, minHeight: 300)
        .environment(preferences)
    } defaultValue: {
      Server(name: nil, description: nil, address: "")
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
    
//    WindowGroup(id: "preview", for: PreviewFileInfo.self) { info in
//      FilePreviewView(info: info)
//        .frame(minWidth: 400, minHeight: 300)
//    }
//    .defaultSize(width: 750, height: 700)
//    .windowStyle(.hiddenTitleBar)
//    .aspectRatio(nil, contentMode: .fit)
    
    // MARK: Settings Window
    Settings {
      SettingsView()
        .environment(preferences)
    }

    #endif
  }
}
