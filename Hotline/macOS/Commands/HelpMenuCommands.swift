import SwiftUI

/// Links to the project, below Hotline Help in the Help menu, and every build's release notes.
struct HelpMenuCommands: Commands {
  @Environment(\.openURL) private var openURL
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .help) {
      Divider()
      Button("Request Feature...", systemImage: "sparkles.2") {
        self.open("https://github.com/mierau/hotline/issues/new?labels=enhancement")
      }
      Button("Report Bug...", systemImage: "ladybug") {
        self.open("https://github.com/mierau/hotline/issues/new?labels=bug")
      }
      Divider()
      // Each build's, with a link to its release on GitHub.
      Button("Release Notes", systemImage: "app.gift") {
        self.openWindow(id: "release-notes")
      }
    }
  }

  private func open(_ address: String) {
    if let url = URL(string: address) {
      self.openURL(url)
    }
  }
}
