import SwiftUI

/// What can be done with a file or folder a link in someone's words points to. On this server,
/// what the Files list offers for it, short of changing it: download it, look at it, get its info,
/// or show it in Files. On another, connect to that server. Either way, copy the link.
@MainActor
struct FileLinkMenu {
  let model: HotlineState
  let openWindow: OpenWindowAction
  /// Goes where a link goes, as clicking it does: a link to a file shows it in Files.
  var open: (URL) -> Void = FileLinkMenu.open
  /// Shows a file's info.
  let showInfo: (FileDetails) -> Void

  /// Goes where a link goes, outside chat: a hotline:// link to the server it's on, through the app,
  /// which shows that part of a server already open, or connects to it, and anything else in its
  /// app.
  static func open(_ url: URL) {
    if url.scheme?.lowercased() == "hotline", let server = Server(url: url) {
      AppState.shared.pendingServerOpen = server
    }
    else {
      NSWorkspace.shared.open(url)
    }
  }

  /// Whether a link's server is the one this is connected to.
  func isThisServer(_ server: Server) -> Bool {
    guard let currentServer = self.model.server else {
      return false
    }
    return server.address == currentServer.address && server.port == currentServer.port
  }

  func menu(for url: URL) -> NSMenu? {
    guard let linkServer = Server(url: url), let path = linkServer.initialFilePath, let name = path.last else {
      return nil
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    if self.isThisServer(linkServer) {
      let file = FileInfo(linkedName: name, path: path, isFolder: url.hasDirectoryPath)
      let actions = FileActions(model: self.model, openWindow: self.openWindow)
      menu.addItem(ChatMenuItem("Download", systemImage: "arrow.down", isEnabled: self.model.access?.contains(.canDownloadFiles) == true) {
        actions.downloadFile(file)
      })
      if !file.isFolder {
        menu.addItem(ChatMenuItem("Quick Look", systemImage: "eye", isEnabled: file.isPreviewable) {
          actions.previewFile(file)
        })
      }
      let showInfo = self.showInfo
      menu.addItem(ChatMenuItem("Get Info", systemImage: "info.circle") {
        Task {
          if let details = await actions.getFileInfo(file) {
            showInfo(details)
          }
        }
      })
      let open = self.open
      menu.addItem(ChatMenuItem("Show in Files", systemImage: "folder") {
        open(url)
      })
    }
    else {
      let open = self.open
      menu.addItem(ChatMenuItem("Connect to \(linkServer.displayAddress)", systemImage: "network") {
        open(url)
      })
    }
    menu.addItem(.separator())
    menu.addItem(ChatMenuItem("Copy Link", systemImage: "link") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
    })
    return menu
  }
}
