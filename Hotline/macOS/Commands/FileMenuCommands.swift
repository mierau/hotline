import SwiftUI

/// The File menu.
struct FileMenuCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Connect to Server...", systemImage: "globe.americas.fill") {
        self.openWindow(id: "server")
      }
      .keyboardShortcut(.init("K"), modifiers: .command)
    }
  }
}
