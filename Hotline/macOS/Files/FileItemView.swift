import SwiftUI

struct FileItemView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(FileDropTarget.self) private var dropTarget: FileDropTarget?
  @Environment(\.filePlaces) private var places
  @Environment(FileRename.self) private var rename: FileRename?
  @Environment(\.fileNamePlaces) private var namePlaces
  @Environment(\.openWindow) private var openWindow
  @Environment(\.modelContext) private var modelContext
  
  var file: FileInfo
  let depth: Int
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Spacer()
        .frame(width: CGFloat(depth * (12 + 2)))
      
      Spacer()
        .frame(width: 10)
        .padding(.leading, 4)
        .padding(.trailing, 8)
      
      HStack(alignment: .center) {
        if file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .frame(width: 16, height: 16)
            .opacity(0.5)
        }
        else if file.isServerBookmark {
          // As servers are in the Servers window.
          Image("Server")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else {
          FileIconView(filename: file.name, fileType: file.type)
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 16)
      .padding(.trailing, 6)
      
      if let rename = self.rename, rename.file == self.file {
        // As wide as the name, as it's typed, as the Finder's is.
        FileNameField(rename: rename, file: self.file)
          .fixedSize(horizontal: true, vertical: false)
      }
      else {
        Text(self.rename?.name(of: self.file) ?? self.file.name)
          .lineLimit(1)
          .truncationMode(.tail)
          .opacity(file.isUnavailable ? 0.5 : 1.0)
          // Where its name is, for a click on it, once it's selected, to rename it.
          .filePlace(self.file, in: self.namePlaces)
      }

      Spacer()
      if file.isServerBookmark && !file.isUnavailable {
        self.serverBookmarkButtons
      }
      else if !file.isUnavailable {
        Text(formattedFileSize(file.fileSize))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Where it is in the list, for what's dropped on it to go into the folder it's in.
    .filePlace(self.file, in: self.places)
    // Shown with the folder it's in, and what else is shown in it, where what's dragged over it, or
    // them, would go, out to the row's edges, to meet the rows above and below.
    .background {
      if let joins = self.dropTarget?.shows(self.file.path) {
        FileDropHighlight(above: joins.above, below: joins.below)
          .padding(.horizontal, -6)
          .padding(.vertical, -4)
      }
    }
    // Inside the row's theming, which sets what the list draws for the row, from the outside.
    .fileDragSource(self.file)
    .serverThemedRow(for: self.file)

    if file.expanded {
      ForEach(file.children!, id: \.self) { childFile in
        if childFile.isFolder {
          FolderItemView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
        else {
          FileItemView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
      }
    }
  }
  
  /// For a server bookmark someone's put up: keep it with your own, or connect to it, in place of
  /// its size, which doesn't matter for one. A press on them is for them, not the row.
  private var serverBookmarkButtons: some View {
    let actions = FileActions(model: self.model, openWindow: self.openWindow)
    return HStack(spacing: 8) {
      Button("Connect") {
        actions.connect(toServerIn: self.file)
      }
      .buttonStyle(FileRowCapsuleButtonStyle())
      .help("Connect to Server")

      Button {
        actions.addToBookmarks(self.file, context: self.modelContext)
      } label: {
        Image(systemName: "bookmark.fill")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help("Add to Bookmarks")
    }
    .disabled(!actions.canDownload([self.file]))
    .fileDragPassThrough()
    .padding(.trailing, 6)
  }

  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt) -> String {
    FileItemView.byteFormatter.allowedUnits = [.useAll]
    FileItemView.byteFormatter.countStyle = .file
    return FileItemView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
}

/// A small capsule of a button in a file's row, in the gray of what's beside it, and no taller than
/// the row, as a bordered button at a size that has room for its words would be.
private struct FileRowCapsuleButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 8)
      .frame(height: 18)
      .background(.fill.secondary.opacity(configuration.isPressed ? 2 : 1), in: .capsule)
      .foregroundStyle(self.isEnabled ? .secondary : .tertiary)
      .contentShape(.capsule)
      // Taller than the row's words, into the room around them, without the row growing for it.
      .padding(.vertical, -1)
  }
}

#Preview("Server bookmark files") {
  let bookmark = FileInfo(hotlineFile: HotlineFile(type: "HTbm", creator: "HTLC", fileSize: 460, fileName: "The Mobius Strip"))
  let other = FileInfo(hotlineFile: HotlineFile(type: "TEXT", creator: "ttxt", fileSize: 1_000, fileName: "About This Area"))
  let model = HotlineState()
  model.access = [.canDownloadFiles]
  return VStack(alignment: .leading, spacing: 12) {
    List {
      FileItemView(file: bookmark, depth: 0)
      FileItemView(file: other, depth: 0)
    }
    .frame(height: 70)
    HStack(spacing: 12) {
      FileGridItemView(file: bookmark, isSelected: false, isDragTarget: false, places: FilePlaces(space: nil))
      FileGridItemView(file: other, isSelected: false, isDragTarget: false, places: FilePlaces(space: nil))
    }
  }
  .padding()
  .frame(width: 360)
  .environment(model)
}
