import SwiftUI
import SwiftData

enum ServerWindowDestination: Hashable, Codable {
  case server(server: Server)
  case none
}

@main
struct Application: App {
  #if os(iOS)
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
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
    .defaultSize(width: 700, height: 800)
    .defaultPosition(.center)
//    .commandsRemoved()
//    .commands {
//      CommandGroup(before: CommandGroupPlacement.newItem) {
//        Button("before item") {
//          print("before item")
//        }
//      }
//    }
    
    Settings {
      SettingsView()
        .environment(preferences)
    }

    #endif
  }
}
