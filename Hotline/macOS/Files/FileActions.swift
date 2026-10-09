import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct FileActions {
  let model: HotlineState
  let openWindow: OpenWindowAction

  /// Downloads files and folders to the downloads folder, one after another, each waiting its turn
  /// in the transfers list, and not what's in a folder that's among them, which comes with it.
  func download(_ files: [FileInfo]) {
    for file in Self.outermost(files) {
      self.model.enqueueDownload(file)
    }
  }

  func downloadFile(_ file: FileInfo) {
    self.download([file])
  }

  // MARK: What You Can Do

  /// Without what's in a folder that's among them, as in a list with folders opened in it, which
  /// goes along with the folder, rather than again on its own, or from where it no longer is, once
  /// the folder's gone.
  static func outermost(_ files: [FileInfo]) -> [FileInfo] {
    let folders = files.filter(\.isFolder).map(\.path)
    return files.filter { file in
      !folders.contains { $0.count < file.path.count && file.path.starts(with: $0) }
    }
  }

  /// Whether they can all be downloaded, files and folders by the rights you have for each.
  func canDownload(_ files: [FileInfo]) -> Bool {
    !files.isEmpty && files.allSatisfy { !$0.isUnavailable && self.model.access?.contains($0.isFolder ? .canDownloadFolders : .canDownloadFiles) == true }
  }

  /// Whether they can all be deleted, files and folders by the rights you have for each.
  func canDelete(_ files: [FileInfo]) -> Bool {
    !files.isEmpty && files.allSatisfy { self.model.access?.contains($0.isFolder ? .canDeleteFolders : .canDeleteFiles) == true }
  }

  /// Whether it can be moved into another folder on the server.
  func canMove(_ file: FileInfo) -> Bool {
    self.canMove(isFolder: file.isFolder)
  }

  func canMove(isFolder: Bool) -> Bool {
    self.model.access?.contains(isFolder ? .canMoveFolders : .canMoveFiles) == true
  }

  /// Whether any of what's dragged from a server's files can be moved into a folder: what's from
  /// this server, that you can move, and isn't there already, or a folder going into itself.
  func canMove(_ items: [DraggedServerItem], into path: [String]) -> Bool {
    items.contains { self.canMove($0, into: path) }
  }

  private func canMove(_ item: DraggedServerItem, into path: [String]) -> Bool {
    item.server == self.model.id && self.canMove(isFolder: item.isFolder) && Array(item.path.dropLast()) != path && !path.starts(with: item.path)
  }

  /// Whether you can upload.
  var canUpload: Bool {
    self.model.access?.contains(.canUploadFiles) == true
  }

  /// Whether it can be renamed, by the rights you have for files or folders.
  func canRename(_ file: FileInfo) -> Bool {
    self.model.access?.contains(file.isFolder ? .canRenameFolders : .canRenameFiles) == true
  }

  /// Renames it, and lists again the folder it's in, as the server has it then. False when the
  /// server wouldn't, which it's said why.
  func rename(_ file: FileInfo, to name: String) async -> Bool {
    let folder = Array(file.path.dropLast())
    guard (try? await self.model.setFileInfo(fileName: file.name, path: folder, fileNewName: name, comment: nil)) == true else {
      return false
    }
    let _ = try? await self.model.getFileList(path: folder)
    return true
  }

  func previewFile(_ file: FileInfo) {
    guard file.isPreviewable else {
      return
    }

    // Shown by what's in it, read from the start of it, or the end, where its list is.
    if let archiveKind = file.archiveKind, let server = model.server {
      openPreviewWindow(PreviewFileInfo(
        id: UInt32.random(in: 1...UInt32.max),
        address: server.address,
        port: server.port,
        size: Int(file.fileSize),
        name: file.name,
        type: file.type,
        creator: file.creator,
        archiveKind: archiveKind,
        hotlineID: model.id,
        path: file.path
      ))
      return
    }

    model.previewFile(file.name, path: file.path) { info in
      if let info = info {
        var extendedInfo = info
        extendedInfo.creator = file.creator
        extendedInfo.type = file.type
        openPreviewWindow(extendedInfo)
      }
    }
  }

  /// Deletes them, one after another, and lists again the folders they were in. What's in a folder
  /// that's among them goes with it.
  func delete(_ files: [FileInfo]) async {
    var parents: Set<[String]> = []
    for file in Self.outermost(files) {
      do {
        try await model.deleteFile(file.name, path: file.path)
        parents.insert(Array(file.path.dropLast()))
      }
      catch {
        print("Error deleting file: \(error)")
      }
    }
    for parent in parents {
      let _ = try? await model.getFileList(path: parent)
    }
  }

  func getFileInfo(_ file: FileInfo) async -> FileDetails? {
    return try? await model.getFileDetails(file.name, path: file.path)
  }

  // MARK: Dropping

  /// Moves what's dragged from a server's files into a folder, what of it can go there: what's from
  /// this server, as another's files aren't anywhere on it to move, that you can move, and that isn't
  /// there already. False when none of it can, to turn the drop away.
  func move(_ items: [DraggedServerItem], into path: [String]) -> Bool {
    let paths = items.filter { self.canMove($0, into: path) }.map(\.path)
    guard !paths.isEmpty else {
      return false
    }
    Task {
      await self.model.moveItems(at: paths, to: path)
    }
    return true
  }

  /// Uploads what's dropped, all of it, files and folders, to a folder, if you can upload, in the
  /// order it was dropped. False when there's nothing to upload, or you can't, to turn the drop
  /// away.
  func upload(_ providers: [NSItemProvider], to path: [String]) -> Bool {
    let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    guard self.canUpload, !providers.isEmpty else {
      return false
    }

    Task {
      var fileURLs: [URL] = []
      for provider in providers {
        if let fileURL = await Self.fileURL(of: provider) {
          fileURLs.append(fileURL)
        }
      }
      self.upload(fileURLs, to: path)
    }
    return true
  }

  /// Uploads files and folders to a folder, one after another, each in the transfers list from
  /// the start, waiting its turn.
  func upload(_ fileURLs: [URL], to path: [String]) {
    self.model.enqueueUploads(fileURLs, to: path)
  }

  /// Where something dropped is.
  private static func fileURL(of provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        continuation.resume(returning: (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) } ?? (item as? URL))
      }
    }
  }

  /// Makes a folder in another one, the top of the server's files for an empty path.
  func newFolder(name: String, in path: [String]) {
    Task {
      do {
        if try await model.newFolder(name: name, parentPath: path) {
          try await model.getFileList(path: path)
        }
      }
      catch {
        // The server didn't make it, so there's nothing new to list.
      }
    }
  }

  /// Links to them, one a line, to paste in chat, or anywhere.
  func copyLinks(_ files: [FileInfo]) {
    let links = files.compactMap(self.link(to:))
    guard !links.isEmpty else {
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
  }

  private func link(to file: FileInfo) -> String? {
    guard let server = self.model.server else {
      return nil
    }

    var components = URLComponents()
    components.scheme = "hotline"
    components.host = server.address
    components.port = server.port == HotlinePorts.DefaultServerPort ? nil : server.port
    var pathComponentAllowed = CharacterSet.urlPathAllowed
    pathComponentAllowed.remove(charactersIn: "/")
    let path = file.path.map {
      $0.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed) ?? $0
    }.joined(separator: "/")
    // A link to a folder ends in a slash, which is how chat knows to show it as one.
    components.percentEncodedPath = "/files/" + path + (file.isFolder ? "/" : "")
    return components.string
  }

  private func openPreviewWindow(_ previewInfo: PreviewFileInfo) {
    // PICTs too, which the preview draws itself, as Quick Look can't draw most of them.
    openWindow(id: "preview-quicklook", value: previewInfo)
  }
}

extension UTType {
  /// A file or folder on a server, as it's dragged from the Files section, to move into another
  /// folder on the same server.
  static let hotlineServerItem = UTType(exportedAs: "co.goodmake.hotline.server-item")
}

/// What's said of a file or folder dragged from a server's files, for a folder it's dropped on:
/// which server, by its state's own mark, and where on it.
struct DraggedServerItem: Codable {
  let server: UUID
  let path: [String]
  let isFolder: Bool
}

/// Where something dragged over the files would go if it were dropped now, to show it there: a
/// folder, by where it is, and the last of the rows shown under it in the list, to draw it and them
/// as one, or the folder in view, which is shown around all of them.
@MainActor @Observable
final class FileDropTarget {
  /// The folder in view.
  var root: [String] = []
  private(set) var folder: [String]?
  private(set) var last: [String]?

  /// Where it'd go now, and the last of the rows shown under it, or nothing, for nowhere.
  func show(_ folder: [String]?, last: [String]? = nil) {
    let last = folder == nil ? nil : last ?? folder
    if self.folder != folder {
      self.folder = folder
    }
    if self.last != last {
      self.last = last
    }
  }

  /// Whether it'd go into the folder in view.
  var isRoot: Bool {
    self.folder == self.root
  }

  /// Whether a row shows where it'd go, as the folder's own, or one shown under it, and whether the
  /// rows above and below it do too.
  func shows(_ path: [String]) -> (above: Bool, below: Bool)? {
    guard let folder, folder != self.root, path.starts(with: folder) else {
      return nil
    }
    return (above: path != folder, below: path != self.last)
  }

  /// The last of a folder's rows in the list: what's last in it, or in that, if it's an open folder
  /// too, or its own, when it's closed, or empty.
  static func lastShown(in folder: FileInfo) -> [String] {
    guard folder.isFolder, folder.expanded, let last = folder.children?.last else {
      return folder.path
    }
    return Self.lastShown(in: last)
  }
}

/// A file or folder being renamed where it's shown, in the list or the icons: the name it's being
/// given, until it's done with, or let be, and once it's given, the new name, shown in its place,
/// until the server has renamed it.
@MainActor @Observable
final class FileRename {
  private(set) var file: FileInfo?
  var name = ""
  /// Names given, by what they're given to, until the server has them.
  private(set) var given: [FileInfo.ID: String] = [:]
  /// What's done with a name given.
  @ObservationIgnored var give: (FileInfo, String) async -> Void = { _, _ in }

  /// Renaming it, once what was being renamed, if anything, is done with.
  func start(_ file: FileInfo) {
    if let current = self.file {
      self.finish(current)
    }
    self.name = file.name
    self.file = file
  }

  /// The name, done with: given, if it's changed, and shown until it's what it's called. Only for
  /// what's being renamed, and not one being renamed before, whose field's going as this one comes.
  func finish(_ file: FileInfo) {
    guard self.file == file else {
      return
    }
    self.file = nil
    let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != file.name else {
      return
    }
    self.given[file.id] = name
    Task {
      await self.give(file, name)
      self.given[file.id] = nil
    }
  }

  /// Left as it was.
  func cancel(_ file: FileInfo) {
    if self.file == file {
      self.file = nil
    }
  }

  /// What a file or folder's called where it's shown: the name it's been given, until it has it.
  func name(of file: FileInfo) -> String {
    self.given[file.id] ?? file.name
  }
}

/// A file or folder's name, as it's renamed where it's shown: what's before its extension selected,
/// as the Finder does, given with Return, or by clicking away, and left as it was with Escape.
/// Presses in it are for it, and aren't drags of the file.
struct FileNameField: View {
  @Bindable var rename: FileRename
  let file: FileInfo
  var alignment: TextAlignment = .leading
  @FocusState private var focused: Bool
  @State private var selection: TextSelection?

  var body: some View {
    TextField("Name", text: self.$rename.name, selection: self.$selection)
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(self.alignment)
      .focused(self.$focused)
      .onSubmit {
        self.rename.finish(self.file)
      }
      .onExitCommand {
        self.rename.cancel(self.file)
      }
      .onChange(of: self.focused) { _, focused in
        if focused {
          // Once it has the focus, which selects all of it, just what's before its extension.
          Task { @MainActor in
            let name = self.rename.name
            let stem = self.file.isFolder ? name : (name as NSString).deletingPathExtension
            let end = name.index(name.startIndex, offsetBy: stem.isEmpty ? name.count : stem.count)
            self.selection = TextSelection(range: name.startIndex..<end)
          }
        }
        else {
          self.rename.finish(self.file)
        }
      }
      .onAppear {
        self.focused = true
      }
      .fileDragPassThrough()
  }
}

/// A row in the list that shows where what's dragged would go: the folder's, or one shown under it,
/// all of them drawn as one, faintly in the selection's color, over the list's stripes, without a
/// theme, rather than through them, and outlined in it.
struct FileDropHighlight: View {
  @Environment(\.serverTheme) private var theme
  let above: Bool
  let below: Bool

  var body: some View {
    let color = Color(nsColor: self.theme?.selection ?? .controlAccentColor)
    let top: CGFloat = self.above ? 0 : 6
    let bottom: CGFloat = self.below ? 0 : 6
    let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    shape
      .fill(self.theme == nil ? Color(nsColor: NSColor.alternatingContentBackgroundColors[0]) : Color.clear)
      .overlay {
        shape.fill(color.opacity(0.15))
      }
      .overlay {
        // Without its edge where it meets the row above or below, which is past this one's, cut off.
        shape
          .strokeBorder(color, lineWidth: 2)
          .padding(.top, self.above ? -2 : 0)
          .padding(.bottom, self.below ? -2 : 0)
      }
      .clipped()
  }
}

/// Where files and folders can be dropped, in the list or the icons: ones from elsewhere, to upload
/// them, and ones dragged from the same server's files, to move them, into the folder under where
/// they are, as `place` finds it, for a point there, and shows it, or else the folder in view, but
/// not into the folder they're in already, or into themselves, which is somewhere they're turned
/// away. One for all of the list, or the icons, which works out where everything in it is itself, as
/// a drag over a row of a list doesn't come to anything of the row's own.
struct FileDrop: DropDelegate {
  let actions: FileActions
  let target: FileDropTarget
  /// The folder something at a point would go into, and the last row shown under it in the list.
  let place: (CGPoint) -> (folder: [String], last: [String]?)

  func validateDrop(info: DropInfo) -> Bool {
    if info.hasItemsConforming(to: [.hotlineServerItem]) {
      return self.actions.canMove(isFolder: false) || self.actions.canMove(isFolder: true)
    }
    return info.hasItemsConforming(to: [.fileURL]) && self.actions.canUpload
  }

  func dropEntered(info: DropInfo) {
    _ = self.dropUpdated(info: info)
  }

  /// Moved, from the same server's files, or else copied up to it, into where it's over, as that
  /// shows, or turned away, where it can't go.
  func dropUpdated(info: DropInfo) -> DropProposal? {
    let place = self.place(info.location)
    let moving = info.hasItemsConforming(to: [.hotlineServerItem])
    guard !moving || self.actions.canMove(FileDragOut.dragging, into: place.folder) else {
      self.target.show(nil)
      return DropProposal(operation: .forbidden)
    }
    self.target.show(place.folder, last: place.last)
    return DropProposal(operation: moving ? .move : .copy)
  }

  func dropExited(info: DropInfo) {
    self.target.show(nil)
  }

  /// What's dragged from the files is what's being dragged out of them, as the drop has it only as
  /// a promise of a file, for the Finder, and not as what it is on the server, which this app has
  /// already, as the drag's from it.
  func performDrop(info: DropInfo) -> Bool {
    let place = self.place(info.location)
    self.target.show(nil)
    if info.hasItemsConforming(to: [.hotlineServerItem]) {
      return self.actions.move(FileDragOut.dragging, into: place.folder)
    }
    return self.actions.upload(info.itemProviders(for: [.fileURL]), to: place.folder)
  }
}
