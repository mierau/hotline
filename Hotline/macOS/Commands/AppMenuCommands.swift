import SwiftUI

/// The Hotline menu: About, updates, and Settings.
struct AppMenuCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Hotline", systemImage: "info.circle") {
        self.openWindow(id: "about")
      }

      Button("Check for Updates...", systemImage: "questionmark.diamond") {
        AppUpdate.shared.checkForUpdates()
      }
      // Not while an update's being checked for, or installed.
      .disabled(!AppUpdate.shared.canCheck)
    }

    CommandGroup(replacing: .appSettings) {
      Button("Settings...", systemImage: "gearshape") {
        self.openWindow(id: "settings")
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}
