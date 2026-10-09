import SwiftUI

struct FileItemView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(FileDropTarget.self) private var dropTarget: FileDropTarget?
  @Environment(\.filePlaces) private var places
  @Environment(FileRename.self) private var rename: FileRename?
  @Environment(\.fileNamePlaces) private var namePlaces
  
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
      if !file.isUnavailable {
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
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt) -> String {
    FileItemView.byteFormatter.allowedUnits = [.useAll]
    FileItemView.byteFormatter.countStyle = .file
    return FileItemView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
}
