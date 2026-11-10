import SwiftUI

/// The File menu: connecting to a server, and disconnecting from the one in front, and what can be
/// done with what's selected in the Files list that has the keys, with the Finder's keys for it.
struct FileMenuCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.fileList) private var fileList: FileListMenu?
  @FocusedValue(\.activeHotlineModel) private var activeHotline: HotlineState?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Connect...", systemImage: "globe.americas.fill") {
        self.openWindow(id: "server")
      }
      .keyboardShortcut(.init("K"), modifiers: .command)

      // With Connect, as they go together. It asks first when that would lose something.
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

    // After the system's Close, which goes with Connect, as opening and closing a window. Close is
    // in a group of its own, which a group put before or after Save isn't put by, as there's no
    // saving here, so this goes before Import and Export, which comes after it.
    CommandGroup(before: .importExport) {
      self.button(.newFolder)
      self.button(.upload)
      self.button(.download)

      Divider()

      self.button(.open)
      self.button(.quickLook)
      self.button(.getInfo)
      self.button(.rename)

      Divider()

      self.button(.delete)
    }
  }

  /// Off unless a Files list has the keys, and what's selected in it allows it. Its keys are only
  /// its own while the list has them too, as a menu item that's off still takes its keys, and
  /// beeps, so ⌘⌫ would stop deleting back to the start of a line in what you're writing, and ⌘I
  /// would stop being Italic.
  private func button(_ command: FileListCommand) -> some View {
    Button(self.fileList?.title(of: command) ?? command.title, systemImage: command.systemImage) {
      self.fileList?.perform(command)
    }
    .keyboardShortcut(self.fileList != nil ? command.shortcut : nil)
    .disabled(self.fileList?.allows(command) != true)
  }
}

// MARK: - Files List

/// Something to do with what's selected in a Files list, from the File menu, or the list's own
/// menus.
enum FileListCommand: CaseIterable {
  case newFolder
  case upload
  case download
  case open
  case quickLook
  case getInfo
  case rename
  case delete

  var title: String {
    switch self {
    case .newFolder: "New Folder"
    case .upload: "Upload..."
    case .download: "Download"
    case .open: "Open"
    case .quickLook: "Quick Look"
    case .getInfo: "Get Info"
    case .rename: "Rename"
    case .delete: "Delete..."
    }
  }

  var systemImage: String {
    switch self {
    case .newFolder: "folder.badge.plus"
    case .upload: "arrow.up"
    case .download: "arrow.down"
    case .open: "arrow.up.forward.app"
    case .quickLook: "eye"
    case .getInfo: "info.circle"
    case .rename: "pencil"
    case .delete: "trash"
    }
  }

  /// The Finder's, where it has one. Download has the Finder's Duplicate's, which a server can't
  /// do, and Upload goes with Underline's. Rename has none, as Return starts it.
  var shortcut: KeyboardShortcut? {
    switch self {
    case .newFolder: KeyboardShortcut("n", modifiers: [.command, .shift])
    case .upload: KeyboardShortcut("u", modifiers: [.command, .shift])
    case .download: KeyboardShortcut("d")
    case .open: KeyboardShortcut("o")
    case .quickLook: KeyboardShortcut("y")
    // As Italic's, which has it back once the list doesn't have the keys.
    case .getInfo: KeyboardShortcut("i")
    case .rename: nil
    case .delete: KeyboardShortcut(.delete)
    }
  }
}

/// What the Files list that has the keys lets the File menu do with what's selected in it, and
/// where to ask it to.
struct FileListMenu: Equatable {
  /// What can be done with what's selected now.
  var allowed: Set<FileListCommand>
  /// What Delete says, for a file, a folder, or how many.
  var deleteTitle: String
  /// The list, to do what's chosen.
  let list: FileListActions

  func allows(_ command: FileListCommand) -> Bool {
    self.allowed.contains(command)
  }

  func title(of command: FileListCommand) -> String {
    command == .delete ? self.deleteTitle : command.title
  }

  @MainActor
  func perform(_ command: FileListCommand) {
    self.list.perform?(command)
  }
}

/// Where the File menu's choices go: the Files view the list is in, which has what they show, like
/// the sheet for Get Info.
@MainActor
final class FileListActions: Equatable {
  var perform: ((FileListCommand) -> Void)?

  nonisolated static func == (lhs: FileListActions, rhs: FileListActions) -> Bool {
    lhs === rhs
  }
}

extension FocusedValues {
  /// The Files list that has the keys, for the File menu.
  @Entry var fileList: FileListMenu?
}
