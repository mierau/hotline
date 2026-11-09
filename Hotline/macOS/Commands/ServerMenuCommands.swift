import SwiftUI

/// The Server menu. Connect opens the server picked in the Servers window; the rest act on the
/// server window in front.
struct ServerMenuCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  @FocusedValue(\.trackerSelection) private var trackerSelection: TrackerSelection?
  @FocusedValue(\.activeHotlineModel) private var activeHotline: HotlineState?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?

  var body: some Commands {
    CommandMenu("Server") {
      Button("Connect", systemImage: "globe.americas.fill") {
        if let server = self.trackerSelection?.server {
          self.openWindow(id: "server", value: server)
        }
      }
      .disabled(self.trackerSelection?.server == nil)
      .keyboardShortcut(.downArrow, modifiers: .command)

      Button("Disconnect", systemImage: "xmark") {
        if let hotline = self.activeHotline {
          Task {
            await hotline.disconnect()
          }
        }
      }
      .disabled(self.activeHotline?.status == .disconnected)

      Divider()

      Button("Broadcast Message...", systemImage: "megaphone") {
        self.activeServerState?.broadcastShown = true
      }
      .disabled(self.activeHotline?.access?.contains(.canBroadcast) != true)
      .keyboardShortcut(.init("B"), modifiers: .command)

      Divider()

      Button("Chat", systemImage: "bubble.left") {
        self.activeServerState?.selection = .chat
      }
      .disabled(self.activeHotline?.status != .loggedIn)
      .keyboardShortcut(.init("1"), modifiers: .command)

      Button("Board", systemImage: "pin") {
        self.activeServerState?.selection = .board
      }
      .disabled(self.activeHotline?.status != .loggedIn)
      .keyboardShortcut(.init("2"), modifiers: .command)

      Button("News", systemImage: "newspaper") {
        self.activeServerState?.selection = .news
      }
      .disabled(self.activeHotline?.status != .loggedIn || (self.activeHotline?.serverVersion ?? 0) < 151)
      .keyboardShortcut(.init("3"), modifiers: .command)

      Button("Files", systemImage: "folder") {
        self.activeServerState?.selection = .files
      }
      .disabled(self.activeHotline?.status != .loggedIn)
      .keyboardShortcut(.init("4"), modifiers: .command)

      Divider()

      Button("Manage Accounts...", systemImage: "person.2") {
        self.activeServerState?.accountsShown = true
      }
      .disabled(self.activeHotline?.status != .loggedIn || self.activeHotline?.access?.contains(.canOpenUsers) != true)
    }
  }
}
