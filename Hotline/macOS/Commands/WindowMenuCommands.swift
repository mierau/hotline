import SwiftUI

/// The Window menu's items above the list of windows.
struct WindowMenuCommands: Commands {
  var body: some Commands {
    CommandGroup(before: .singleWindowList) {
      Button("Toolbar") {
        AppState.shared.toggleBannerToolbar()
      }
      .keyboardShortcut(.init("\\"), modifiers: [.shift, .command])
    }
  }
}
