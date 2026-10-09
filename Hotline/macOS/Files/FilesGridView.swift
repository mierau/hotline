import SwiftUI
import AppKit

private let gridColumnSpacing: CGFloat = 12
private let gridPadding: CGFloat = 24
private let gridColumnMin: CGFloat = 100
private let gridColumnMax: CGFloat = 120

struct FileGridItemView: View {
  @Environment(\.serverTheme) private var theme
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(FileRename.self) private var rename: FileRename?
  @Environment(\.fileNamePlaces) private var namePlaces
  let file: FileInfo
  let isSelected: Bool
  let isDragTarget: Bool
  /// Where its icon and name are, for the grid.
  let places: FilePlaces

  var body: some View {
    VStack(spacing: 2) {
      Group {
        if self.file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .resizable()
            .scaledToFit()
        }
        else if self.file.isFolder {
          if self.file.isAdminDropboxFolder {
            Image("Admin Drop Box Large")
              .resizable()
              .scaledToFit()
          }
          else if self.file.isDropboxFolder {
            Image("Drop Box Large")
              .resizable()
              .scaledToFit()
          }
          else {
            Image("Folder Large")
              .resizable()
              .scaledToFit()
          }
        }
        else {
          FileIconView(filename: self.file.name, fileType: self.file.type)
        }
      }
      .frame(width: 48, height: 48)
      .padding(4)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(self.isSelected ? Color(nsColor: .tertiaryLabelColor).opacity(0.3) : Color.clear)
      )
      // Where what's dragged over it would go, in the color the list shows it in.
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(nsColor: self.theme?.selection ?? .controlAccentColor).opacity(0.15))
          .opacity(self.isDragTarget ? 1 : 0)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(Color(nsColor: self.theme?.selection ?? .controlAccentColor), lineWidth: 2)
          .opacity(self.isDragTarget ? 1 : 0)
      )
      // A press on its icon, or its name, and not beside them, is a press on it, as in the Finder,
      // and a drag from them is of it.
      .fileDragSource(self.file)
      .filePlace(self.file, in: self.places)

      if let rename = self.rename, rename.file == self.file {
        FileNameField(rename: rename, file: self.file, alignment: .center)
          .font(.subheadline)
          .filePlace(self.file, in: self.places)
          .frame(width: 100, alignment: .center)
      }
      else {
        Text(self.rename?.name(of: self.file) ?? self.file.name)
          .font(.subheadline)
          .lineLimit(2)
          .truncationMode(.middle)
          .multilineTextAlignment(.center)
          .foregroundStyle(self.isSelected && self.emphasized ? Color.white : Color.primary)
          .padding(.horizontal, 4)
          .padding(.vertical, 1)
          // Selected, in the window in front, in the selection's color, and in other windows, in the
          // system's gray, as the Finder's names are.
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(self.isSelected ? Color(nsColor: self.emphasized ? self.theme?.selection ?? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor) : Color.clear)
          )
          .fileDragSource(self.file)
          .filePlace(self.file, in: self.places)
          // Where its name is, for a click on it, once it's selected, to rename it.
          .filePlace(self.file, in: self.namePlaces)
          .frame(width: 90, alignment: .center)
          .help(self.file.name.count > 10 ? self.file.name : "")
      }
    }
    .opacity(self.file.isUnavailable ? 0.5 : 1.0)
    .frame(width: 100, height: 90, alignment: .top)
  }

  /// In the window in front.
  private var emphasized: Bool {
    self.controlActiveState == .key
  }
}

/// Where each file is shown, in the icons or the list, as each icon and its name, or each row, says,
/// by its own mark, in the coordinate space named `space`, or else the window's, to find what a press
/// or a drop is over, and what a selection rectangle touches. Kept where keeping it doesn't draw them
/// again, as it changes with every scroll.
final class FilePlaces {
  let space: String?

  fileprivate var frames: [UUID: (file: FileInfo, frame: CGRect)] = [:]

  init(space: String?) {
    self.space = space
  }

  /// What a point is on, if it's on anything, or within `slop` of it.
  func file(at point: CGPoint, slop: CGSize = .zero) -> FileInfo? {
    self.frames.values.first { $0.frame.insetBy(dx: -slop.width, dy: -slop.height).contains(point) }?.file
  }

  /// What a rectangle touches.
  func files(in rect: CGRect) -> Set<FileInfo> {
    Set(self.frames.values.filter { $0.frame.intersects(rect) }.map(\.file))
  }
}

private struct FilePlace: ViewModifier {
  let file: FileInfo
  let places: FilePlaces?
  /// This one's own, and not its file's, which an icon and its name both have.
  @State private var mark = UUID()
  /// Where it was last, to say again when it's shown again in the same place, which isn't a change
  /// to be told of.
  @State private var last = LastFrame()

  final class LastFrame {
    var frame: CGRect?
  }

  func body(content: Content) -> some View {
    if let places = self.places {
      content
        .onGeometryChange(for: CGRect.self) { proxy in places.space.map { proxy.frame(in: .named($0)) } ?? proxy.frame(in: .global) } action: { frame in
          self.last.frame = frame
          places.frames[self.mark] = (self.file, frame)
        }
        .onAppear {
          if let frame = self.last.frame {
            places.frames[self.mark] = (self.file, frame)
          }
        }
        .onDisappear {
          places.frames[self.mark] = nil
        }
    }
    else {
      content
    }
  }
}

extension View {
  /// Where a file's shown, or part of where, as an icon's name is, for `places` to know.
  func filePlace(_ file: FileInfo, in places: FilePlaces?) -> some View {
    self.modifier(FilePlace(file: file, places: places))
  }
}

extension EnvironmentValues {
  /// Where the list's rows say where they are.
  @Entry var filePlaces: FilePlaces? = nil
  /// Where the files' names are shown, in the list or the icons, for a click on one to rename it.
  @Entry var fileNamePlaces: FilePlaces? = nil
}

/// What a press in the grid is doing, until it's let go.
private enum GridPress {
  /// On an icon, which is to be the only one selected once it's let go, if it's a click on one of
  /// several selected, kept selected until then, in case it's a drag of them all.
  case icon(FileInfo, selectsAlone: Bool)
  /// Between them, drawing a selection rectangle from where it started, around what was selected
  /// already, with ⇧ or ⌘, which it adds to, or with ⌘, turns on and off.
  case marquee(from: CGPoint, kept: Set<FileInfo>, toggles: Bool)
  /// Done with as soon as it was pressed, as a double click, or a click with ⌘ or ⇧, is.
  case done
}

struct FilesGridView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.serverTheme) private var theme
  @Environment(FileDropTarget.self) private var dropTarget: FileDropTarget?

  @Binding var selection: Set<FileInfo>
  @Binding var folderPath: [String]

  var actions: FileActions
  var isShowingSearchResults: Bool
  /// A folder's been loading long enough to say so.
  var loading: Bool
  /// What can be done with files and folders, for a menu on them, or on nothing, between them.
  var menu: ([FileInfo]) -> AnyView
  /// Opens them, as a double click does.
  var open: ([FileInfo]) -> Void

  @State private var gridWidth: CGFloat = 0
  /// Opening a folder something's been dragged over a moment.
  @State private var springLoadTask: Task<Void, Never>? = nil
  /// Where the icons are, in the grid, which a press and a drop are measured in, as it's all in it.
  private static let space = "FilesGrid"
  @State private var places = FilePlaces(space: FilesGridView.space)
  /// What a press in the grid is doing, while it's down.
  @State private var press: GridPress? = nil
  @GestureState private var pressing: Bool = false
  /// The selection rectangle a press between the icons is drawing, where it is in the grid.
  @State private var marquee: CGRect? = nil
  /// The icon the keys go on from: the one last clicked, or gone to, and the one ⇧ selects from.
  @State private var cursor: FileInfo? = nil
  /// Selecting just the one a click was on, of several selected, once it's not a double click,
  /// which opens all of them, as in the Finder.
  @State private var selectAlone: Task<Void, Never>? = nil

  private var columnsPerRow: Int {
    let available = self.gridWidth - (gridPadding * 2)
    return max(1, Int((available + gridColumnSpacing) / (gridColumnMin + gridColumnSpacing)))
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: gridColumnMin, maximum: gridColumnMax), spacing: gridColumnSpacing)],
          alignment: .leading,
          spacing: 12
        ) {
          ForEach(self.currentItems, id: \.self) { file in
            self.gridItemView(for: file)
              .id(file.id)
          }
        }
        .padding(gridPadding)
      }
      // Where the keys have gone, kept in view.
      .onChange(of: self.cursor) { _, newValue in
        if let file = newValue {
          withAnimation {
            proxy.scrollTo(file.id, anchor: nil)
          }
        }
      }
    }
    .contentShape(Rectangle())
    // Every press in the grid: on an icon, to select it, or between them, to draw a selection
    // rectangle around what to select.
    .simultaneousGesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
        .updating(self.$pressing) { _, pressing, _ in
          pressing = true
        }
        .onChanged { value in
          if self.press == nil {
            self.pressed(at: value.startLocation)
          }
          self.dragged(to: value.location)
        }
        .onEnded { _ in
          self.released()
        }
    )
    // A press stopped without being let go is done with too.
    .onChange(of: self.pressing) { _, pressing in
      if !pressing {
        self.press = nil
        self.marquee = nil
      }
    }
    // In the server's theme, in its selection's color, or else in gray, as the Finder's is.
    .overlay(alignment: .topLeading) {
      if let marquee = self.marquee {
        let tint = self.theme?.selection.map { Color(nsColor: $0) }
        Rectangle()
          .fill(tint?.opacity(0.15) ?? Color.primary.opacity(0.08))
          .overlay {
            Rectangle()
              .strokeBorder(tint?.opacity(0.8) ?? Color.primary.opacity(0.3), lineWidth: 1)
          }
          .frame(width: marquee.width, height: marquee.height)
          .offset(x: marquee.minX, y: marquee.minY)
          .allowsHitTesting(false)
      }
    }
    .coordinateSpace(.named(Self.space))
    .contextMenu {
      self.menu([])
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      self.gridWidth = width
    }
    .focusable()
    .focusEffectDisabled()
    // Select All, from the Edit menu, and with ⌘A.
    .onCommand(#selector(NSResponder.selectAll(_:))) {
      self.selection = Set(self.currentItems)
    }
    // Into a folder it's over, which shows it, and opens after a moment, or else the folder you're in,
    // shown around all of it: what's uploaded, or moved there from elsewhere on the server.
    .onDrop(of: [.fileURL, .hotlineServerItem], delegate: FileDrop(actions: self.actions, target: self.dropTarget ?? FileDropTarget(), place: { self.dropPlace(at: $0) }))
    .onChange(of: self.dropTarget?.folder) { _, folder in
      self.springLoadTask?.cancel()
      self.springLoadTask = nil
      guard let folder, folder != self.folderPath, self.currentItems.contains(where: { $0.isFolder && $0.path == folder }) else {
        return
      }
      self.springLoadTask = Task {
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        self.folderPath = folder
      }
    }
    .overlay {
      if self.dropTarget?.isRoot == true {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color(nsColor: self.theme?.selection ?? .controlAccentColor), lineWidth: 2)
          .padding(4)
          .allowsHitTesting(false)
      }
    }
    .overlay {
      if self.loading || (!self.model.filesLoaded && self.folderPath.isEmpty) {
        VStack {
          ProgressView()
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
      }
    }
    .onKeyPress(.return) {
      let selected = self.selectedItems
      guard !selected.isEmpty else {
        return .ignored
      }
      self.open(selected)
      return .handled
    }
    .onKeyPress(.space) {
      let selected = self.selectedItems
      if selected.count == 1, let s = selected.first, s.isPreviewable {
        self.actions.previewFile(s)
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.rightArrow, phases: [.down, .repeat]) { press in
      self.moveSelectionHorizontally(by: 1, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(.leftArrow, phases: [.down, .repeat]) { press in
      self.moveSelectionHorizontally(by: -1, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
      if press.modifiers.contains(.command) {
        let selected = self.selectedItems
        guard !selected.isEmpty else {
          return .ignored
        }
        // Once, and not again for as long as it's held, which would download it again.
        if press.phase == .down {
          self.open(selected)
        }
        return .handled
      }
      return self.moveSelectionVertically(by: 1, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
      if press.modifiers.contains(.command) {
        if !self.folderPath.isEmpty && !self.isShowingSearchResults {
          self.folderPath.removeLast()
          return .handled
        }
        return .ignored
      }
      return self.moveSelectionVertically(by: -1, extending: press.modifiers.contains(.shift))
    }
  }

  @ViewBuilder
  private func gridItemView(for file: FileInfo) -> some View {
    FileGridItemView(file: file, isSelected: self.selection.contains(file), isDragTarget: file.isFolder && self.dropTarget?.folder == file.path, places: self.places)
      .padding(6)
      // For all of what's selected, if it's selected, or else for it alone, which it selects, as
      // in the Finder.
      .contextMenu {
        self.menu(self.selection.contains(file) ? self.selectedItems : [file])
          .onAppear {
            if !self.selection.contains(file) {
              self.selection = [file]
              self.cursor = file
            }
          }
      }
  }

  // MARK: Pressing

  /// A press on an icon selects it, at once, as in the Finder, or with ⌘, selects it or doesn't,
  /// or with ⇧, selects up to it, or a second time, opens it. Between them, it takes the selection
  /// away, but with ⌘ or ⇧, and starts a selection rectangle.
  private func pressed(at point: CGPoint) {
    self.selectAlone?.cancel()
    self.selectAlone = nil

    let event = NSApp.currentEvent
    let modifiers = event?.modifierFlags ?? []
    let items = self.currentItems
    guard let file = self.places.file(at: point), items.contains(file) else {
      if modifiers.isDisjoint(with: [.command, .shift]) {
        self.selection = []
      }
      self.press = .marquee(from: point, kept: self.selection, toggles: modifiers.contains(.command))
      return
    }

    self.press = .done
    if (event?.clickCount ?? 1) > 1 {
      self.open(self.selection.contains(file) ? self.selectedItems : [file])
    }
    else if modifiers.contains(.command) {
      if self.selection.contains(file) {
        self.selection.remove(file)
      }
      else {
        self.selection.insert(file)
      }
      self.cursor = file
    }
    else if modifiers.contains(.shift) {
      if let cursor = self.cursor, let from = items.firstIndex(of: cursor), let to = items.firstIndex(of: file) {
        self.selection.formUnion(items[min(from, to)...max(from, to)])
      }
      else {
        self.selection.insert(file)
        self.cursor = file
      }
    }
    else {
      let selectsAlone = self.selection.contains(file) && self.selection.count > 1
      if !selectsAlone {
        self.selection = [file]
      }
      self.cursor = file
      self.press = .icon(file, selectsAlone: selectsAlone)
    }
  }

  /// A press between the icons selects what's in its rectangle, as it's drawn, as well as what was
  /// selected already, with ⇧ or ⌘, or with ⌘, the other way round from how it was.
  private func dragged(to point: CGPoint) {
    guard case .marquee(let start, let kept, let toggles) = self.press else {
      return
    }
    let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
    // Not for a click, which hardly moves.
    guard self.marquee != nil || max(rect.width, rect.height) >= 2 else {
      return
    }
    self.marquee = rect
    let touched = self.places.files(in: rect).intersection(self.currentItems)
    let selection = toggles ? kept.symmetricDifference(touched) : kept.union(touched)
    if selection != self.selection {
      self.selection = selection
    }
  }

  /// A click on one of several selected selects it alone, once it's let go, and it's not the
  /// first of a double click, and a selection rectangle goes.
  private func released() {
    if case .icon(let file, selectsAlone: true) = self.press {
      self.selectAlone = Task {
        try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
        guard !Task.isCancelled else {
          return
        }
        self.selection = [file]
      }
    }
    self.press = nil
    self.marquee = nil
  }

  // MARK: Dropping

  /// What's dropped at a point goes into: a folder whose icon or name it's over, or else the folder
  /// you're in.
  private func dropPlace(at point: CGPoint) -> (folder: [String], last: [String]?) {
    if let file = self.places.file(at: point), file.isFolder, self.currentItems.contains(file) {
      return (file.path, nil)
    }
    return (self.folderPath, nil)
  }

  // MARK: Keys

  private func moveSelectionHorizontally(by offset: Int, extending: Bool) -> KeyPress.Result {
    let items = self.currentItems
    guard !items.isEmpty else { return .handled }

    guard let index = self.cursorIndex(in: items) else {
      self.go(to: items[0], extending: false)
      return .handled
    }

    let newIndex = index + offset
    guard newIndex >= 0, newIndex < items.count else {
      return .handled
    }

    // Don't wrap across rows
    let cols = self.columnsPerRow
    if index / cols != newIndex / cols {
      return .handled
    }

    self.go(to: items[newIndex], extending: extending)
    return .handled
  }

  private func moveSelectionVertically(by rows: Int, extending: Bool) -> KeyPress.Result {
    let items = self.currentItems
    let cols = self.columnsPerRow
    guard !items.isEmpty else { return .handled }

    guard let index = self.cursorIndex(in: items) else {
      self.go(to: items[0], extending: false)
      return .handled
    }

    let newIndex = index + (rows * cols)

    // Exact target exists
    if newIndex >= 0, newIndex < items.count {
      self.go(to: items[newIndex], extending: extending)
      return .handled
    }

    // Moving down: snap to last item if there's a partial row below
    if rows > 0, newIndex >= items.count {
      let lastIndex = items.count - 1
      // Only snap if the last item is on a row below the current one
      if lastIndex / cols > index / cols {
        self.go(to: items[lastIndex], extending: extending)
      }
      return .handled
    }

    return .handled
  }

  /// Where the keys go on from: the icon last clicked, or gone to, while it's selected, or else the
  /// first of what is.
  private func cursorIndex(in items: [FileInfo]) -> Int? {
    if let cursor = self.cursor, self.selection.contains(cursor), let index = items.firstIndex(of: cursor) {
      return index
    }
    return items.firstIndex(where: self.selection.contains)
  }

  /// Selects it alone, or with ⇧, as well as what's selected already.
  private func go(to file: FileInfo, extending: Bool) {
    if extending {
      self.selection.insert(file)
    }
    else {
      self.selection = [file]
    }
    self.cursor = file
  }

  // MARK: Items

  /// What's selected, in the order it's shown.
  private var selectedItems: [FileInfo] {
    self.currentItems.filter(self.selection.contains)
  }

  private var currentItems: [FileInfo] {
    if self.isShowingSearchResults {
      return self.model.fileSearchResults
    }

    if self.folderPath.isEmpty {
      return self.model.files
    }

    return self.findFolder(in: self.model.files, at: self.folderPath)?.children ?? []
  }

  private func findFolder(in files: [FileInfo], at path: [String]) -> FileInfo? {
    guard !path.isEmpty, !files.isEmpty else { return nil }

    let currentName = path[0]
    for file in files {
      if file.name == currentName {
        if path.count == 1 {
          return file
        }
        else if let children = file.children {
          return self.findFolder(in: children, at: Array(path[1...]))
        }
      }
    }
    return nil
  }
}
