import SwiftUI

/// The commands for the server window in front: its sections at the top of the View menu, as what
/// the window shows, and what you can do on the server in the Server menu.
struct ServerMenuCommands: Commands {
  @FocusedValue(\.activeHotlineModel) private var activeHotline: HotlineState?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?

  var body: some Commands {
    // Which section the window shows, as Finder and Calendar have their ⌘1 to ⌘4 in View.
    CommandGroup(before: .toolbar) {
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
    }

    CommandMenu("Server") {
      Button("Broadcast Message...", systemImage: "megaphone") {
        self.activeServerState?.broadcastShown = true
      }
      .disabled(self.activeHotline?.access?.contains(.canBroadcast) != true)
      // ⌘B is Bold, in the Format menu.
      .keyboardShortcut(.init("b"), modifiers: [.command, .shift])

      Button("Manage Accounts...", systemImage: "person.2") {
        self.activeServerState?.accountsShown = true
      }
      .disabled(self.activeHotline?.status != .loggedIn || self.activeHotline?.access?.contains(.canOpenUsers) != true)

      Divider()

      // Last, as it ends the session. It asks first when that would lose something.
      Button("Disconnect", systemImage: "xmark") {
        if let hotline = self.activeHotline,
           let state = self.activeServerState,
           !state.askBeforeDisconnecting(.disconnect, from: hotline) {
          Task {
            await hotline.disconnect()
          }
        }
      }
      .disabled(self.activeHotline?.status != .loggedIn)
    }
  }
}
