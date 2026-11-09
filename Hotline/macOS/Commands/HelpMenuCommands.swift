import SwiftUI

/// Links to the project, below Hotline Help in the Help menu.
struct HelpMenuCommands: Commands {
  @Environment(\.openURL) private var openURL

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
      Button("View Latest Release...", systemImage: "app.gift") {
        self.open("https://github.com/mierau/hotline/releases/latest")
      }
    }
  }

  private func open(_ address: String) {
    if let url = URL(string: address) {
      self.openURL(url)
    }
  }
}
