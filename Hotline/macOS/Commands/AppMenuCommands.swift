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
        Task {
          await AppUpdate.shared.checkForUpdatesManually()
        }
      }
    }

    CommandGroup(replacing: .appSettings) {
      Button("Settings...", systemImage: "gearshape") {
        self.openWindow(id: "settings")
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}
