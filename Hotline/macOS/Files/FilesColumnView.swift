#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Files in columns, as the Finder shows them: what's at the top, or what a search found, then
/// what's in each folder on the way to the one you're in, with the one gone into selected in each,
/// and after the column you're in, what's selected there, alone: what's in a folder, or a file's
/// details. The column you're in is the folder you're in, for all that goes by it, like Back,
/// uploading and new folders, and what's selected in it is what's selected.
///
/// The keys go up and down a column, as a list's do, right, into the folder selected, and left,
/// back out of it. A click in any column selects there, and goes to it. What's in a folder that's
/// been listed shows at once, and one that hasn't been is listed once it's stayed selected a
/// moment, so going down a column of folders doesn't ask the server for each one on the way.
struct FilesColumnView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.serverTheme) private var theme
  @Environment(FileDropTarget.self) private var dropTarget: FileDropTarget?
  @Environment(FileRename.self) private var rename: FileRename?

  @Binding var selection: Set<FileInfo>
  @Binding var folderPath: [String]

  var actions: FileActions
  var isShowingSearchResults: Bool
  /// Asks for the keys to go to the column you're in, each time it changes.
  var focusRequest: Int
  /// What can be done with files and folders, for a menu on them, or on nothing, between them.
  var menu: ([FileInfo]) -> AnyView
  /// Opens them, as a double click does.
  var open: ([FileInfo]) -> Void
  /// Renames what's selected, as Return does, if it's one thing you can rename.
  var renameSelection: () -> Void

  /// The column that has the keys, by where it is from the left.
  @FocusState private var focusedColumn: Int?
  /// How wide each column's been made on its own, by dragging the line after it, or as wide as its
  /// names, with a double click, by where it is from the left, whatever folder it shows, as the
  /// Finder has it.
  @State private var widths: [Int: CGFloat] = [:]
  /// How wide the rest are, as they were last made all at once, by dragging with ⌥, which is kept
  /// for next time.
  @State private var standardWidth = CGFloat(Prefs.shared.filesColumnWidth)
  /// The widths as they were when the line after a column began to be dragged, to work out how wide
  /// to make them from, wherever it's dragged, with ⌥ or without, as that can change on the way.
  @State private var resizeStart: (widths: [Int: CGFloat], standard: CGFloat)? = nil
  /// Where the rows are, in the window, for a drop to find what it's over, as each row's shown in a
  /// view of its own, in its list, which a coordinate space of the columns' own doesn't reach.
  @State private var places = FilePlaces(space: nil)
  /// Where the columns are, in the window, for a drop between rows to go into the folder its column
  /// shows, and where all of them are, which a drop on them is measured from.
  @State private var columnPlaces = FileColumnPlaces()
  /// Folders that couldn't be listed, as a drop box can't be, by most, to say so in their columns,
  /// rather than look as if they're loading.
  @State private var unlistable: Set<[String]> = []
  /// A folder gone into with the keys before what's in it was listed, to select the first of what's
  /// in it once it is, as the Finder does.
  @State private var selectsFirst: [String]? = nil
  /// Showing what's in a folder something's been dragged over a moment.
  @State private var springLoad: Task<Void, Never>? = nil

  /// How narrow a column can be made, and how wide.
  static let narrowest: CGFloat = 120
  static let widest: CGFloat = 640
  /// How much wider a row is than its name: its icon and the space after it, a folder's arrow and
  /// the space before it, and the room a list keeps around a row, for a column made as wide as its
  /// widest name.
  private static let rowRoom: CGFloat = 16 + 6 + 12 + 8 + 2 * 20

  var body: some View {
    let columns = self.pathColumns
    let trailing = self.trailing(after: columns)
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          ForEach(columns) { column in
            self.list(for: column)
          }
          switch trailing {
          case .folder(let column):
            self.list(for: column)
          case .file(let file):
            let index = columns.count
            FileColumnDetails(file: file, actions: self.actions)
              .frame(width: self.width(of: index))
              .frame(maxHeight: .infinity)
              .id(Self.detailsID)
            FileColumnDivider { distance, all, done in
              self.resize(index, by: distance, all: all, done: done)
            } fit: {
            } ended: {
              self.resizeStart = nil
            }
          case nil:
            EmptyView()
          }
        }
        .frame(maxHeight: .infinity)
      }
      // The newest column, whole, as it opens, and the one you're in, as you go back out.
      .onChange(of: Self.lastID(of: columns, trailing: trailing)) { _, id in
        withAnimation(.easeInOut(duration: 0.2)) {
          proxy.scrollTo(id, anchor: .trailing)
        }
      }
      .onAppear {
        proxy.scrollTo(Self.lastID(of: columns, trailing: trailing), anchor: .trailing)
      }
    }
    // Behind the columns and past them, as the lists' own would be, without a theme, which has its
    // own background behind them.
    .background(self.theme == nil ? Color(nsColor: .controlBackgroundColor) : Color.clear)
    // Into a folder it's over, or the folder of the column it's in, which shows it, and after a
    // moment over a folder, what's in it, in the column after, for one in there in turn, and so on
    // down: what's uploaded, or moved there from elsewhere on the server. Where it is is said in
    // the columns' own place, and where the rows and columns are in the window's, so it's said there
    // too.
    .onDrop(of: [.fileURL, .hotlineServerItem], delegate: FileDrop(actions: self.actions, target: self.dropTarget ?? FileDropTarget(), place: { location in
      self.dropPlace(at: CGPoint(x: self.columnPlaces.frame.minX + location.x, y: self.columnPlaces.frame.minY + location.y))
    }))
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
      self.columnPlaces.frame = frame
    }
    .onChange(of: self.dropTarget?.folder) { _, folder in
      self.springLoad?.cancel()
      self.springLoad = nil
      // In the columns up to the one you're in, or in the one after it, for what's in a folder
      // opened this way, to go on down.
      var shown = columns
      if case .folder(let column)? = trailing {
        shown.append(column)
      }
      guard let folder, let (file, column) = self.folderShown(at: folder, in: shown), !self.selected(in: column).contains(file) else {
        return
      }
      self.springLoad = Task {
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else {
          return
        }
        self.enter(column, selecting: [file])
      }
    }
    // What's in the folder selected, once it's stayed selected a moment, if it hasn't been listed.
    .task(id: self.folderToList(after: trailing)) {
      guard let path = self.folderToList(after: trailing) else {
        return
      }
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else {
        return
      }
      await self.list(path)
    }
    // What's in the folders on the way to the one you're in, which you've come to by a link, say,
    // without going through them, one at a time. The one you're in is listed by the files.
    .task(id: self.unlistedOnTheWay(in: columns)) {
      for path in self.unlistedOnTheWay(in: columns) {
        guard !Task.isCancelled else {
          return
        }
        await self.list(path)
      }
    }
    .onChange(of: self.selection) { _, selection in
      self.follow(selection)
    }
    .onChange(of: self.folderPath) { _, path in
      if self.selectsFirst != path {
        self.selectsFirst = nil
      }
      // The keys, if the columns have them, to the column you're in now.
      if self.focusedColumn != nil {
        self.focusActive()
      }
    }
    .onChange(of: columns.last?.files.first) { _, first in
      guard let first, self.selectsFirst == self.folderPath, self.selection.isEmpty else {
        return
      }
      self.selectsFirst = nil
      self.selection = [first]
    }
    .onChange(of: self.focusRequest) {
      self.focusActive()
    }
    .onChange(of: self.focusedColumn) { _, index in
      self.focused(index)
    }
    .onAppear {
      self.focusActive()
    }
    // None of the keys while a name's being written, where they're for moving in it, typing a
    // space, and giving the name with Return.
    .onKeyPress(.rightArrow) {
      self.isRenaming ? .ignored : self.goIn()
    }
    .onKeyPress(.leftArrow) {
      self.isRenaming ? .ignored : self.goOut()
    }
    .onKeyPress(.space) {
      guard !self.isRenaming, let file = self.selectedAlone, file.isPreviewable else {
        return .ignored
      }
      self.actions.previewFile(file)
      return .handled
    }
    .onKeyPress(.return) {
      guard !self.isRenaming else {
        return .ignored
      }
      self.renameSelection()
      return .handled
    }
    .onKeyPress(.downArrow, phases: .down) { press in
      guard !self.isRenaming, press.modifiers.contains(.command) else {
        return .ignored
      }
      let selected = self.selectedFiles
      guard !selected.isEmpty else {
        return .ignored
      }
      self.open(selected)
      return .handled
    }
    .onKeyPress(.upArrow, phases: .down) { press in
      guard !self.isRenaming, press.modifiers.contains(.command) else {
        return .ignored
      }
      return self.goOut()
    }
  }

  // MARK: - Columns

  /// The columns up to the one you're in: what's at the top, and what's in each folder on the way,
  /// or what a search found.
  private var pathColumns: [FileColumn] {
    if self.isShowingSearchResults {
      return [FileColumn(index: 0, path: nil, files: self.model.fileSearchResults, listed: true)]
    }
    var columns = [FileColumn(index: 0, path: [], files: self.model.files, listed: self.model.filesLoaded)]
    var files = self.model.files
    for depth in self.folderPath.indices {
      let path = Array(self.folderPath[...depth])
      // As it's known, which a folder on the way to one gone to by a link might not be yet.
      let folder = files.first { $0.isFolder && $0.name == path.last }
      files = folder?.children ?? []
      columns.append(FileColumn(index: depth + 1, path: path, files: files, listed: folder?.loaded ?? false))
    }
    return columns
  }

  /// What's after the column you're in, for what's selected there, alone: what's in a folder, or a
  /// file's details.
  private func trailing(after columns: [FileColumn]) -> FileColumnTrailing? {
    guard let active = columns.last else {
      return nil
    }
    let selected = active.files.filter(self.selection.contains)
    guard selected.count == 1, let file = selected.first else {
      return nil
    }
    if file.isFolder {
      return .folder(FileColumn(index: active.index + 1, path: file.path, files: file.children ?? [], listed: file.loaded))
    }
    return .file(file)
  }

  private static let detailsID = "details"

  /// The last column shown, to keep in view.
  private static func lastID(of columns: [FileColumn], trailing: FileColumnTrailing?) -> String {
    switch trailing {
    case .folder(let column):
      return column.id
    case .file:
      return Self.detailsID
    case nil:
      return columns.last?.id ?? ""
    }
  }

  /// Where the column you're in is, from the left.
  private var activeIndex: Int {
    self.isShowingSearchResults ? 0 : self.folderPath.count
  }

  /// A column's list, and the line after it, which makes it wider or narrower.
  @ViewBuilder
  private func list(for column: FileColumn) -> some View {
    FileColumnList(
      column: column,
      selection: Binding {
        self.selected(in: column)
      } set: { files in
        self.select(files, in: column)
      },
      isActive: column.index == self.activeIndex,
      isUnlistable: column.path.map(self.unlistable.contains) ?? false,
      places: self.places,
      focus: self.$focusedColumn,
      menu: { files in
        self.menu(files, in: column)
      },
      open: self.open
    )
    .frame(width: self.width(of: column.index))
    .frame(maxHeight: .infinity)
    .fileColumnPlace(column.path, in: self.columnPlaces)
    // Where what's dragged would go, when it's this column's folder.
    .overlay {
      if let path = column.path, self.dropTarget?.folder == path {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color(nsColor: self.theme?.selection ?? .controlAccentColor), lineWidth: 2)
          .padding(3)
          .allowsHitTesting(false)
      }
    }
    .id(column.id)

    FileColumnDivider { distance, all, done in
      self.resize(column.index, by: distance, all: all, done: done)
    } fit: {
      self.fit(column.index, to: column.files)
    } ended: {
      self.resizeStart = nil
    }
  }

  // MARK: - Selecting

  /// What's selected in a column: in the column you're in, what's selected; in one on the way to
  /// it, the folder gone into from it; and in what's in the folder selected, nothing yet.
  private func selected(in column: FileColumn) -> Set<FileInfo> {
    let active = self.activeIndex
    if column.index == active {
      return self.selection
    }
    guard column.index < active, column.index < self.folderPath.count else {
      return []
    }
    let name = self.folderPath[column.index]
    return Set(column.files.first { $0.isFolder && $0.name == name }.map { [$0] } ?? [])
  }

  /// Selects these in a column, as its list asks, which is where you are then: the column you're
  /// in, one on the way to it, which you go back to, or what's in the folder selected, which you go
  /// into. Not what a list asks for when it only says again what it shows, as one does when it's
  /// drawn anew, as for a server's theme, which would take you back to a column on the way.
  private func select(_ files: Set<FileInfo>, in column: FileColumn) {
    guard files != self.selected(in: column) else {
      return
    }
    self.enter(column, selecting: files)
  }

  /// Goes to a column, with these selected in it.
  private func enter(_ column: FileColumn, selecting files: Set<FileInfo>) {
    if let path = column.path, path != self.folderPath {
      self.folderPath = path
    }
    if files != self.selection {
      self.selection = files
    }
  }

  /// Clicked into a column on the way to where you are, on the folder selected in it, which its list
  /// doesn't say, as what it has selected is the same: you're there now, with it selected, as in the
  /// Finder. Only for a click, as the keys can be given to a column for other reasons.
  private func focused(_ index: Int?) {
    guard let index, index < self.activeIndex, let event = NSApp.currentEvent?.type, event == .leftMouseDown || event == .leftMouseUp else {
      return
    }
    let columns = self.pathColumns
    guard columns.indices.contains(index) else {
      return
    }
    self.enter(columns[index], selecting: self.selected(in: columns[index]))
  }

  /// A selection made somewhere other than the column you're in, as a press on a row selects it,
  /// before its column has the press, or as something's renamed from a menu on it, is where you
  /// are then.
  private func follow(_ selection: Set<FileInfo>) {
    guard !self.isShowingSearchResults, let first = selection.first else {
      return
    }
    let folder = Array(first.path.dropLast())
    if folder != self.folderPath, selection.allSatisfy({ Array($0.path.dropLast()) == folder }) {
      self.folderPath = folder
    }
  }

  /// What's selected, in the column you're in, in the order it's shown.
  private var selectedFiles: [FileInfo] {
    (self.pathColumns.last?.files ?? []).filter(self.selection.contains)
  }

  /// What's selected, when it's one thing.
  private var selectedAlone: FileInfo? {
    let selected = self.selectedFiles
    return selected.count == 1 ? selected.first : nil
  }

  /// Whether a name's being written, in place of one of the rows' names.
  private var isRenaming: Bool {
    self.rename?.file != nil
  }

  // MARK: - Keys

  /// Into the folder selected, alone, selecting the first of what's in it, or once it's listed, if
  /// it hasn't been yet, as the Finder does. Not into one that's empty, as there's nothing there to
  /// select.
  private func goIn() -> KeyPress.Result {
    guard let folder = self.selectedAlone, folder.isFolder else {
      return .ignored
    }
    let first = folder.children?.first
    guard !folder.loaded || first != nil else {
      return .handled
    }
    self.folderPath = folder.path
    if let first {
      self.selection = [first]
    }
    else {
      self.selection = []
      self.selectsFirst = folder.path
    }
    return .handled
  }

  /// Back out of the folder you're in, to the column before, with it selected, as the files have it
  /// whenever you go back. Not from a search's results, which aren't in a folder.
  private func goOut() -> KeyPress.Result {
    guard !self.folderPath.isEmpty, !self.isShowingSearchResults else {
      return .ignored
    }
    self.folderPath.removeLast()
    return .handled
  }

  /// The keys, to the column you're in, on the next turn, once its list is there, as a new one isn't
  /// yet.
  private func focusActive() {
    DispatchQueue.main.async {
      self.focusedColumn = self.activeIndex
    }
  }

  // MARK: - Listing

  /// The folder selected, alone, if what's in it hasn't been listed, and can be.
  private func folderToList(after trailing: FileColumnTrailing?) -> [String]? {
    guard case .folder(let column)? = trailing, !column.listed, let path = column.path, !self.unlistable.contains(path) else {
      return nil
    }
    return path
  }

  /// The folders on the way to the one you're in that haven't been listed, and can be.
  private func unlistedOnTheWay(in columns: [FileColumn]) -> [[String]] {
    columns.dropLast().compactMap { column in
      guard let path = column.path, !path.isEmpty, !column.listed, !self.unlistable.contains(path) else {
        return nil
      }
      return path
    }
  }

  /// Lists what's in a folder, without saying so when it can't be, as it's only being looked into,
  /// and said in its column instead.
  private func list(_ path: [String]) async {
    let listed = try? await self.model.getFileList(path: path, suppressErrors: true)
    if listed == nil {
      self.unlistable.insert(path)
    }
  }

  // MARK: - Menus

  /// The files' menu, for what it's on in a column, or between its rows, for the folder the column
  /// shows, which you're in then.
  private func menu(_ files: [FileInfo], in column: FileColumn) -> AnyView {
    AnyView(
      self.menu(files)
        .onAppear {
          if files.isEmpty, column.path != nil, column.index != self.activeIndex {
            self.enter(column, selecting: [])
          }
        }
    )
  }

  // MARK: - Widths

  /// How wide a column is: as it's been made on its own, or else as the rest are.
  private func width(of index: Int) -> CGFloat {
    self.widths[index] ?? self.standardWidth
  }

  /// Makes a column wider or narrower by as far as the line after it's been dragged, or with ⌥, all
  /// of them, each by as much of that as keeps the line under the pointer, as all of them up to it
  /// move it, and any made wider or narrower on their own as wide as the rest. From how wide they
  /// were as the drag began, whichever it is, as ⌥ can be pressed or let go on the way. Once it's let
  /// go, all of them at once is kept for next time.
  private func resize(_ index: Int, by distance: CGFloat, all: Bool, done: Bool) {
    let start = self.resizeStart ?? (widths: self.widths, standard: self.standardWidth)
    if self.resizeStart == nil {
      self.resizeStart = start
    }
    let resized = Self.resized(index, by: distance, all: all, from: start, rounded: done)
    self.widths = resized.widths
    self.standardWidth = resized.standard
    if done {
      if all {
        Prefs.shared.filesColumnWidth = Double(resized.standard)
      }
      self.resizeStart = nil
    }
  }

  /// How wide the columns are, once the line after one's been dragged as far, from how wide they
  /// were as the drag began: that column, wider or narrower by as much, or with ⌥, all of them, each
  /// by as much of it as keeps the line under the pointer, as all of them up to it move it, with any
  /// made wider or narrower on their own as wide as the rest.
  static func resized(_ index: Int, by distance: CGFloat, all: Bool, from start: (widths: [Int: CGFloat], standard: CGFloat), rounded: Bool) -> (widths: [Int: CGFloat], standard: CGFloat) {
    let startWidth = { (column: Int) in start.widths[column] ?? start.standard }
    if all {
      let before = (0...index).reduce(CGFloat(0)) { $0 + startWidth($1) }
      return (widths: [:], standard: Self.clamped((before + distance) / CGFloat(index + 1), rounded: rounded))
    }
    var widths = start.widths
    widths[index] = Self.clamped(startWidth(index) + distance, rounded: rounded)
    return (widths: widths, standard: start.standard)
  }

  /// Makes a column as wide as its widest name, as a double click on the line after it does.
  private func fit(_ index: Int, to files: [FileInfo]) {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let widest = files.lazy.map { ($0.name.hidingOffensiveWords as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    self.widths[index] = Self.clamped(ceil(widest) + Self.rowRoom, rounded: true)
  }

  /// A width a column can be, and once it's settled, a whole one.
  private static func clamped(_ width: CGFloat, rounded: Bool) -> CGFloat {
    let width = min(max(width, Self.narrowest), Self.widest)
    return rounded ? width.rounded() : width
  }

  // MARK: - Dropping

  /// What's dropped at a point goes into: a folder it's over, or else the folder of the column it's
  /// in, or the one you're in.
  private func dropPlace(at point: CGPoint) -> (folder: [String], last: [String]?) {
    if let file = self.places.file(at: point), file.isFolder {
      return (file.path, nil)
    }
    if let path = self.columnPlaces.path(at: point) {
      return (path, nil)
    }
    return (self.folderPath, nil)
  }

  /// A folder, by where it is, shown in a column, and the column.
  private func folderShown(at path: [String], in columns: [FileColumn]) -> (FileInfo, FileColumn)? {
    for column in columns {
      if let file = column.files.first(where: { $0.isFolder && $0.path == path }) {
        return (file, column)
      }
    }
    return nil
  }
}

// MARK: - Column

/// What a column shows: what's in a folder, or what a search found.
private struct FileColumn: Identifiable {
  /// Where it is, from the left.
  let index: Int
  /// The folder it shows, by where it is, or nil for what a search found.
  let path: [String]?
  let files: [FileInfo]
  /// Whether what's in it has been listed.
  let listed: Bool

  var id: String {
    self.path.map { $0.description } ?? "search"
  }
}

/// What's after the column you're in, for what's selected there, alone.
private enum FileColumnTrailing {
  /// What's in a folder.
  case folder(FileColumn)
  /// A file's details.
  case file(FileInfo)
}

/// A column's list: what's in a folder, or what a search found, with what's selected in it, drawn
/// as the system draws a list in use in the column you're in, and as one that isn't in the rest.
private struct FileColumnList: View {
  let column: FileColumn
  @Binding var selection: Set<FileInfo>
  /// Whether it's the column you're in.
  let isActive: Bool
  /// Whether what's in its folder couldn't be listed.
  let isUnlistable: Bool
  let places: FilePlaces
  let focus: FocusState<Int?>.Binding
  let menu: ([FileInfo]) -> AnyView
  let open: ([FileInfo]) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      List(self.column.files, id: \.self, selection: self.$selection) { file in
        FileColumnRow(file: file, places: self.places)
      }
      .listStyle(.inset)
      .alternatingRowBackgrounds(.disabled)
      .scrollContentBackground(.hidden)
      .environment(\.defaultMinListRowHeight, 24)
      .serverThemedList(selected: self.selection, in: self.column.files)
      .environment(\.serverListActive, self.isActive)
      .focused(self.focus, equals: self.column.index)
      .contextMenu(forSelectionType: FileInfo.self) { items in
        self.menu(self.column.files.filter(items.contains))
      } primaryAction: { items in
        self.open(self.column.files.filter(items.contains))
      }
      .overlay {
        if !self.column.listed {
          if self.isUnlistable {
            Text("Couldn't Load Folder")
              .foregroundStyle(.secondary)
              .padding()
          }
          else {
            FileColumnSpinner()
          }
        }
      }
      .accessibilityLabel(self.column.path.map { $0.last ?? "Files" } ?? "Search Results")
      // Its selection, when it's one thing, kept in view, as it changes, and as it's shown, as a
      // column on the way to where you are is, scrolled to the folder gone into from it.
      .onChange(of: self.selection) {
        self.reveal(with: proxy)
      }
      .onAppear {
        self.reveal(with: proxy)
      }
    }
  }

  private func reveal(with proxy: ScrollViewProxy) {
    guard self.selection.count == 1, let file = self.selection.first else {
      return
    }
    proxy.scrollTo(file, anchor: nil)
  }
}

/// A file or folder in a column: its icon, its name, or a field to rename it in, and for a folder,
/// an arrow, as what's in it opens to the right.
private struct FileColumnRow: View {
  @Environment(FileRename.self) private var rename: FileRename?
  @Environment(\.fileNamePlaces) private var namePlaces
  @Environment(FileDropTarget.self) private var dropTarget: FileDropTarget?
  let file: FileInfo
  /// Where it is, in the columns, for what's dropped on it.
  let places: FilePlaces

  var body: some View {
    HStack(spacing: 6) {
      FileColumnIcon(file: self.file, large: false)
        .frame(width: 16, height: 16)

      if let rename = self.rename, rename.file == self.file {
        FileNameField(rename: rename, file: self.file)
      }
      else {
        let name = self.rename?.name(of: self.file) ?? self.file.name.hidingOffensiveWords
        Text(name)
          .lineLimit(1)
          .truncationMode(.middle)
          .opacity(self.file.isUnavailable ? 0.5 : 1)
          // Where its name is, for a click on it, once it's selected, to rename it.
          .filePlace(self.file, in: self.namePlaces)
          .help(name.count > 24 ? name : "")
      }

      Spacer(minLength: 0)

      // What's in it on its way, as when it's been clicked, by its arrow.
      if self.file.isFolder && self.file.isListing {
        ProgressView()
          .controlSize(.mini)
          .accessibilityLabel("Loading")
      }

      if self.file.isFolder {
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.leading, 2)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Where it is, for what's dropped on it to go into it, if it's a folder, or else the folder its
    // column shows.
    .filePlace(self.file, in: self.places)
    // Where what's dragged over it would go, when it's a folder.
    .background {
      if self.file.isFolder, self.dropTarget?.folder == self.file.path {
        FileDropHighlight(above: false, below: false)
          .padding(.horizontal, -6)
          .padding(.vertical, -2)
      }
    }
    // Inside the row's theming, which sets what the list draws for the row, from the outside.
    .fileDragSource(self.file)
    .serverThemedRow(for: self.file)
  }
}

/// A file's icon, or a folder's, small, as in a row, or large, as in its details: a drop box's, or a
/// server bookmark's globe, as the rest of the files show them.
private struct FileColumnIcon: View {
  let file: FileInfo
  let large: Bool

  var body: some View {
    if self.file.isUnavailable {
      Image(systemName: "questionmark.app.fill")
        .resizable()
        .scaledToFit()
        .opacity(0.5)
    }
    else if self.file.isFolder {
      let name = self.file.isAdminDropboxFolder ? "Admin Drop Box" : self.file.isDropboxFolder ? "Drop Box" : "Folder"
      Image(self.large ? "\(name) Large" : name)
        .resizable()
        .scaledToFit()
    }
    else if self.file.isServerBookmark {
      Image(self.large ? "Server Large" : "Server")
        .resizable()
        .scaledToFit()
    }
    else {
      FileIconView(filename: self.file.name, fileType: self.file.type)
    }
  }
}

/// A file selected alone, in a column of its own after it, as the Finder shows one: its icon, large,
/// its name, what kind of file it is and how big, and what can be done with it right there.
private struct FileColumnDetails: View {
  @Environment(\.modelContext) private var modelContext
  let file: FileInfo
  let actions: FileActions

  var body: some View {
    VStack(spacing: 8) {
      FileColumnIcon(file: self.file, large: true)
        .frame(width: 96, height: 96)
        .padding(.top, 28)
        .padding(.bottom, 4)

      Text(self.file.name.hidingOffensiveWords)
        .font(.headline)
        .multilineTextAlignment(.center)
        .lineLimit(5)
        .textSelection(.enabled)

      Text(self.summary)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      self.buttons
        .controlSize(.small)
        .padding(.top, 8)
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// What kind of file it is, and how big.
  private var summary: String {
    if self.file.isUnavailable {
      return "Unavailable"
    }
    if self.file.isServerBookmark {
      return "Server Bookmark"
    }
    let kind = FileIconView.contentType(filename: self.file.name, fileType: self.file.type).localizedDescription ?? "Document"
    let size = ByteCountFormatter.string(fromByteCount: Int64(self.file.fileSize), countStyle: .file)
    return "\(kind) – \(size)"
  }

  /// What can be done with it: a server bookmark, connected to, or kept with your own, and anything
  /// else, looked at, if it can be, and downloaded.
  @ViewBuilder
  private var buttons: some View {
    if self.file.isServerBookmark {
      HStack(spacing: 8) {
        Button("Connect") {
          self.actions.connect(toServerIn: self.file)
        }
        Button("Add to Bookmarks") {
          self.actions.addToBookmarks(self.file, context: self.modelContext)
        }
      }
      .disabled(!self.actions.canDownload([self.file]))
    }
    else if !self.file.isUnavailable {
      HStack(spacing: 8) {
        if self.file.isPreviewable {
          Button("Quick Look") {
            self.actions.previewFile(self.file)
          }
        }
        Button("Download") {
          self.actions.download([self.file])
        }
        .disabled(!self.actions.canDownload([self.file]))
      }
    }
  }
}

/// That what's in a column's folder is being listed, once it's taken long enough to say so, so a
/// folder that lists quickly doesn't flash it.
private struct FileColumnSpinner: View {
  @State private var shown = false

  var body: some View {
    ProgressView()
      .controlSize(.small)
      .opacity(self.shown ? 1 : 0)
      .task {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else {
          return
        }
        withAnimation(.easeIn(duration: 0.2)) {
          self.shown = true
        }
      }
  }
}

/// The line after a column, which is where it's made wider or narrower, by dragging, or with ⌥, all
/// of them, and as wide as its widest name, with a double click.
private struct FileColumnDivider: View {
  /// Makes it wider or narrower by as far as it's been dragged, or with ⌥, all of them, and says
  /// when it's let go.
  let resize: (_ distance: CGFloat, _ all: Bool, _ done: Bool) -> Void
  /// Makes it as wide as its widest name.
  let fit: () -> Void
  /// Says it's no longer being dragged, however that came about, as a drag that's cut short doesn't
  /// say it's let go.
  let ended: () -> Void

  /// Whether it's being dragged, which goes back by itself however the drag ends.
  @GestureState private var dragging = false

  var body: some View {
    // Wider than the line, to take hold of.
    Color.clear
      .frame(width: 5)
      .frame(maxHeight: .infinity)
      .overlay {
        ServerSplitLine(axis: .vertical)
      }
      .contentShape(.rect)
      .pointerStyle(.columnResize)
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .updating(self.$dragging) { _, dragging, _ in
            dragging = true
          }
          .onChanged { value in
            self.resize(value.translation.width, NSEvent.modifierFlags.contains(.option), false)
          }
          .onEnded { value in
            self.resize(value.translation.width, NSEvent.modifierFlags.contains(.option), true)
          }
      )
      .onChange(of: self.dragging) { _, dragging in
        if !dragging {
          self.ended()
        }
      }
      .onTapGesture(count: 2, perform: self.fit)
  }
}

// MARK: - Places

/// Where each column is, by the folder it shows, kept where keeping it doesn't draw them again, as it
/// changes with every scroll.
private final class FileColumnPlaces {
  fileprivate var frames: [UUID: (path: [String]?, frame: CGRect)] = [:]
  /// Where all of them are, in the window, which a drop on them is measured from.
  var frame: CGRect = .zero

  /// The folder of the column a point in the window is in, if it's in one that shows a folder.
  func path(at point: CGPoint) -> [String]? {
    self.frames.values.first { $0.frame.contains(point) }?.path ?? nil
  }
}

private struct FileColumnPlace: ViewModifier {
  let path: [String]?
  let places: FileColumnPlaces
  /// This one's own, and not its folder's, which a column coming in can have too.
  @State private var mark = UUID()

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
        self.places.frames[self.mark] = (self.path, frame)
      }
      .onDisappear {
        self.places.frames[self.mark] = nil
      }
  }
}

private extension View {
  /// Where a column is, for the folder it shows, for `places` to know.
  func fileColumnPlace(_ path: [String]?, in places: FileColumnPlaces) -> some View {
    self.modifier(FileColumnPlace(path: path, places: places))
  }
}
#endif
