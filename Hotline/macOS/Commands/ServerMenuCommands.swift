import SwiftUI

/// The commands for the server window in front: its sections at the top of the View menu, as what
/// the window shows, and what you can do on the server in the Server menu.
struct ServerMenuCommands: Commands {
  @FocusedValue(\.activeHotlineModel) private var activeHotline: HotlineState?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  @FocusedValue(\.activeServerIsBookmarked) private var isBookmarked: Bool?

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
      // To anyone here, by name, as it's typed. ⌘N, as a new message is in Mail and Messages.
      Button("New Private Message...", systemImage: "square.and.pencil") {
        self.activeServerState?.composeMessage = PrivateMessageCompose()
      }
      .disabled(self.activeHotline?.status != .loggedIn || self.activeHotline?.access?.contains(.canSendMessages) != true)
      .keyboardShortcut(.init("n"), modifiers: .command)

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

      // Yours on this server, for this window, as Settings has them when it opens: private messages,
      // then private chat.
      Toggle("Refuse Private Messages", isOn: Binding(
        get: { self.activeHotline?.refusePrivateMessages == true },
        set: { self.activeHotline?.setOptions(refusePrivateMessages: $0) }
      ))
      .disabled(self.activeHotline == nil)

      // Checked while it's on. Choosing it shows the reply, to change, or turn on or off.
      Toggle("Auto-Reply...", isOn: Binding(
        get: { self.activeHotline?.automaticResponseOn == true },
        set: { _ in self.activeServerState?.automaticResponseShown = true }
      ))
      .disabled(self.activeHotline == nil)

      Divider()

      Toggle("Refuse Private Chat Invites", isOn: Binding(
        get: { self.activeHotline?.refusePrivateChat == true },
        set: { self.activeHotline?.setOptions(refusePrivateChat: $0) }
      ))
      .disabled(self.activeHotline == nil)

      Divider()

      // Off once it's in your bookmarks.
      Button("Add Bookmark...", systemImage: "bookmark") {
        self.activeServerState?.addBookmarkShown = true
      }
      .disabled(self.activeHotline?.status != .loggedIn || self.activeHotline?.server == nil || self.isBookmarked != false)
    }
  }
}
