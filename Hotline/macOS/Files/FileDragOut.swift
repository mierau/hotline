import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Dragging files and folders out of the Files section, to the Finder or wherever else files go,
/// which downloads them to where they're dropped, as the Finder asks for them, one after another,
/// with their progress on their icons there, as any download has, and in the transfers list, or to
/// a folder of the same server's files, which moves them there. A drag from something selected is
/// all of what's selected, but what's in a folder that's selected too. The list and the icons can't promise files on their own, so a press on
/// one selects it at once, as the Finder does, and is held until it's a click, which goes on to
/// them as if it hadn't been held, or a drag, which starts here.
@MainActor
final class FileDragOut: NSObject {
  /// Who downloads what's dropped.
  weak var model: HotlineState?
  /// Whether something can be dragged out, which is whether it can be downloaded, or moved.
  var canDrag: (FileInfo) -> Bool = { _ in false }
  /// What a drag from something is: all of what's selected, if it's selected.
  var items: (FileInfo) -> [FileInfo] = { [$0] }
  /// Something that can be dragged out's been pressed, to select it at once, as the Finder does,
  /// before it's known whether it's a click or a drag.
  var onPress: (FileInfo) -> Void = { _ in }
  /// Something that can be dragged out's been clicked: pressed, and let go without being dragged,
  /// with where, in the window.
  var onClick: (FileInfo, CGPoint) -> Void = { _, _ in }
  /// Anything's been pressed, anywhere, before what's pressed is known.
  var onAnyPress: () -> Void = {}

  /// What's shown, and where, in the window, as each row and icon says, by each one's own mark, as
  /// a list can show a file in a new row before its old one goes, which mustn't take the new one's
  /// place with it, and without a file, where a press is left alone, as on a folder's arrow.
  fileprivate var frames: [UUID: (file: FileInfo?, frame: CGRect)] = [:]
  /// The view under the files that drags start from, and where it is in the window, to match a
  /// press's place up with theirs.
  fileprivate weak var anchor: FileDragAnchorView?
  fileprivate var anchorFrame: CGRect = .zero

  private var monitor: Any?

  /// What's being dragged out now, from any server's files, as it's said for a folder it's dropped
  /// on, for one it's over to know whether it can take it, before it's dropped. Empty when nothing
  /// is.
  private(set) static var dragging: [DraggedServerItem] = []

  /// How far a press moves before it's a drag.
  private static let dragDistance: CGFloat = 4
  private static let iconSize: CGFloat = 32

  /// Watching presses while the files are in a window, and not after.
  fileprivate func anchorMoved(toWindow: Bool) {
    if toWindow, self.monitor == nil {
      self.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
        let dragged = MainActor.assumeIsolated {
          self?.press(event) ?? false
        }
        return dragged ? nil : event
      }
    }
    else if !toWindow, let monitor = self.monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }

  /// A press on something that can be dragged out, selected at once, and held until it's a click,
  /// or a drag, which starts here. A click goes on as it was: the press and its release are put
  /// back, in order, ahead of anything that's come in since, for the list to have as if the press
  /// had never been held, with what it's handled with seeing it. With ⌘ or ⇧ down, it isn't held,
  /// as it's for the list, to add to what's selected, or take away from it. True when the press is
  /// held, and goes no further now.
  private func press(_ event: NSEvent) -> Bool {
    if self.replaying {
      self.replaying = false
      return false
    }
    self.onAnyPress()
    guard event.clickCount == 1, event.modifierFlags.intersection([.control, .command, .shift]).isEmpty,
          let file = self.file(at: event), self.canDrag(file) else {
      return false
    }
    self.onPress(file)
    let start = event.locationInWindow
    while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
      if next.type == .leftMouseUp {
        NSApp.postEvent(next, atStart: true)
        if let place = self.place(of: event) {
          self.onClick(file, place)
        }
        break
      }
      if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) >= Self.dragDistance {
        self.drag(self.items(file).filter(self.canDrag), from: event)
        return true
      }
    }
    NSApp.postEvent(event, atStart: true)
    self.replaying = true
    return true
  }

  /// The press put back, for the list, which isn't to be held again.
  private var replaying = false

  /// What a press is on, if it's on a row or an icon, and not on something over them, like the
  /// toolbar, or in them, like a folder's arrow.
  private func file(at event: NSEvent) -> FileInfo? {
    guard let anchor = self.anchor, let window = anchor.window, event.window === window,
          let content = window.contentView,
          let hit = content.superview?.hitTest(event.locationInWindow), hit.isDescendant(of: content) else {
      return nil
    }
    guard let place = self.place(of: event) else {
      return nil
    }
    let under = self.frames.values.filter { $0.frame.contains(place) }
    guard !under.contains(where: { $0.file == nil }) else {
      return nil
    }
    return under.first?.file
  }

  /// Where a press is, in the window, as what's shown says where it is.
  private func place(of event: NSEvent) -> CGPoint? {
    guard let anchor = self.anchor else {
      return nil
    }
    let point = anchor.convert(event.locationInWindow, from: nil)
    return CGPoint(x: self.anchorFrame.minX + point.x, y: self.anchorFrame.minY + point.y)
  }

  /// Drags them out, each a promise of it, kept once it's dropped somewhere, and said for what it is
  /// on the server, for a folder there, each with its icon and name, more than one in a pile, as
  /// the Finder drags them.
  private func drag(_ files: [FileInfo], from event: NSEvent) {
    // Not what's in a folder that's dragged too, which goes with it.
    let files = FileActions.outermost(files)
    guard let anchor = self.anchor, !files.isEmpty else {
      return
    }
    // With its icon where the press was.
    let point = anchor.convert(event.locationInWindow, from: nil)
    let serverItems = self.model.map { model in
      files.map { DraggedServerItem(server: model.id, path: $0.path, isFolder: $0.isFolder) }
    } ?? []
    let items = files.enumerated().map { index, file in
      let type = file.isFolder ? UTType.folder : FileIconView.contentType(filename: file.name, fileType: file.type)
      let promise = ServerItemPromiseProvider(fileType: type.identifier, delegate: self)
      promise.userInfo = file
      if index < serverItems.count {
        promise.serverItem = try? JSONEncoder().encode(serverItems[index])
      }

      let icon = NSDraggingImageComponent(key: .icon)
      icon.contents = Self.icon(for: file, type: type)
      let name = Self.label(for: file.name)
      let label = NSDraggingImageComponent(key: .label)
      label.contents = name
      let size = CGSize(width: Self.iconSize + 4 + name.size.width, height: max(Self.iconSize, name.size.height))
      icon.frame = CGRect(x: 0, y: (size.height - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
      label.frame = CGRect(x: Self.iconSize + 4, y: (size.height - name.size.height) / 2, width: name.size.width, height: name.size.height)

      let item = NSDraggingItem(pasteboardWriter: promise)
      item.draggingFrame = CGRect(origin: CGPoint(x: point.x - Self.iconSize / 2, y: point.y - size.height / 2), size: size)
      item.imageComponentsProvider = { [icon, label] in [icon, label] }
      return item
    }

    Self.dragging = serverItems
    let session = anchor.beginDraggingSession(with: items, event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
    session.draggingFormation = items.count > 1 ? .pile : .none
  }

  private static func icon(for file: FileInfo, type: UTType) -> NSImage {
    if file.isFolder, let folder = NSImage(named: file.isAdminDropboxFolder ? "Admin Drop Box Large" : file.isDropboxFolder ? "Drop Box Large" : "Folder Large") {
      return folder
    }
    return NSWorkspace.shared.icon(for: type)
  }

  /// Its name, white on the selection's color, as a selected file's is in the Finder.
  private static func label(for name: String) -> NSImage {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
      .foregroundColor: NSColor.alternateSelectedControlTextColor,
    ]
    let text = name as NSString
    let textSize = text.size(withAttributes: attributes)
    let padding = CGSize(width: 6, height: 2)
    let size = CGSize(width: ceil(min(textSize.width, 300)) + 2 * padding.width, height: ceil(textSize.height) + 2 * padding.height)
    return NSImage(size: size, flipped: false) { rect in
      NSColor.selectedContentBackgroundColor.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
      text.draw(with: rect.insetBy(dx: padding.width, dy: padding.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
      return true
    }
  }

  /// Downloads it where it's been dropped, in its turn, after any other download, and says when
  /// it's there, or why it isn't.
  private func download(_ file: FileInfo?, to url: URL, completion: @escaping (Error?) -> Void) {
    guard let file, let model = self.model else {
      completion(CocoaError(.fileWriteUnknown))
      return
    }
    // Where it's dropped can be somewhere it's let in only for this.
    let accessing = url.startAccessingSecurityScopedResource()
    model.enqueueDownload(file, to: url) { error in
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
      // Stopped from the transfers list, or the Finder, which isn't an error to show.
      completion(error is CancellationError ? CocoaError(.userCancelled) : error)
    }
  }
}

extension FileDragOut: NSDraggingSource {
  /// Copied to wherever it's dropped outside the app, and in it, moved, to another folder of the
  /// same server's, the only place in it that takes them, as it isn't a file yet, to upload.
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    context == .outsideApplication ? .copy : .move
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    Self.dragging = []
  }
}

/// A file or folder dragged out, promised to wherever it's dropped, and for a folder of the same
/// server's files, said for what it is there, to move it.
final class ServerItemPromiseProvider: NSFilePromiseProvider {
  var serverItem: Data?

  override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    super.writableTypes(for: pasteboard) + (self.serverItem == nil ? [] : [NSPasteboard.PasteboardType(UTType.hotlineServerItem.identifier)])
  }

  override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    type.rawValue == UTType.hotlineServerItem.identifier ? self.serverItem : super.pasteboardPropertyList(forType: type)
  }
}

extension FileDragOut: NSFilePromiseProviderDelegate {
  /// Its name, with a / as the : the Finder shows as one, as a name on disk can't have a / in it.
  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    ((filePromiseProvider.userInfo as? FileInfo)?.name ?? "Untitled").replacingOccurrences(of: "/", with: ":")
  }

  /// Asked for on the main queue, as everything it's written with is there.
  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    .main
  }

  nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
    MainActor.assumeIsolated {
      self.download(filePromiseProvider.userInfo as? FileInfo, to: url, completion: completionHandler)
    }
  }
}

/// Under the files, where drags out of them start from, in the same place, so a press's place can
/// be matched up with theirs, and in nothing's way, as it takes no clicks itself.
final class FileDragAnchorView: NSView {
  fileprivate weak var owner: FileDragOut?

  override var isFlipped: Bool {
    true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    self.owner?.anchorMoved(toWindow: self.window != nil)
  }
}

/// The view drags out of the files start from, under them.
struct FileDragAnchor: NSViewRepresentable {
  let dragOut: FileDragOut

  func makeNSView(context: Context) -> FileDragAnchorView {
    let view = FileDragAnchorView()
    view.owner = self.dragOut
    self.dragOut.anchor = view
    return view
  }

  func updateNSView(_ view: FileDragAnchorView, context: Context) {
  }

  static func dismantleNSView(_ view: FileDragAnchorView, coordinator: ()) {
    view.owner?.anchorMoved(toWindow: false)
  }
}

extension EnvironmentValues {
  /// Where the files shown can be dragged out from.
  @Entry var fileDragOut: FileDragOut? = nil
}

extension View {
  /// Something that can be dragged out of the files to the Finder, from where it's shown.
  func fileDragSource(_ file: FileInfo) -> some View {
    self.modifier(FileDragSource(file: file))
  }

  /// Somewhere in a row a press goes to as it is, as a folder's arrow, which opens it, without
  /// selecting it, or dragging it.
  func fileDragPassThrough() -> some View {
    self.modifier(FileDragSource(file: nil))
  }

  /// The files under it can be dragged out, to the Finder, as `fileDragSource` says what they are.
  func fileDragOut(_ dragOut: FileDragOut) -> some View {
    self
      .background {
        FileDragAnchor(dragOut: dragOut)
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragOut.anchorFrame = frame
          }
      }
      .environment(\.fileDragOut, dragOut)
  }
}

private struct FileDragSource: ViewModifier {
  @Environment(\.fileDragOut) private var dragOut
  /// This row's own, and not its file's, which a row coming in can have too.
  @State private var mark = UUID()
  /// Where it was last, to say again when it's shown again in the same place, which isn't a change
  /// to be told of, as a list does with its rows when it adds them again. Kept where keeping it
  /// doesn't draw the row again, as it changes with every scroll.
  @State private var last = LastFrame()
  /// What's dragged from here, or nothing, where presses are left alone.
  let file: FileInfo?

  final class LastFrame {
    var frame: CGRect?
  }

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
        self.last.frame = frame
        self.dragOut?.frames[self.mark] = (self.file, frame)
      }
      .onAppear {
        if let frame = self.last.frame {
          self.dragOut?.frames[self.mark] = (self.file, frame)
        }
      }
      .onDisappear {
        self.dragOut?.frames[self.mark] = nil
      }
  }
}
