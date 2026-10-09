import SwiftUI

struct FolderItemView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.serverTheme) private var theme
  @Environment(\.openWindow) private var openWindow
  @Environment(FileDropTarget.self) private var dropTarget: FileDropTarget?
  @Environment(\.filePlaces) private var places
  @Environment(FileRename.self) private var rename: FileRename?
  @Environment(\.fileNamePlaces) private var namePlaces
  
  @State var loading = false
  /// Listing what's in it again, since it was last opened.
  @State private var listing: Task<Void, Never>? = nil
  
  var file: FileInfo
  let depth: Int

  /// How much is in it: as its own listing has it, once it's been listed, which is as up to date as
  /// what's shown in it, or else as the folder it's in has it.
  private var count: Int {
    self.file.loaded ? self.file.children?.count ?? 0 : Int(self.file.fileSize)
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Spacer()
        .frame(width: CGFloat(depth * (12 + 2)))
      
      Button {
        if file.isFolder {
          file.expanded.toggle()
        }
      } label: {
        Text(Image(systemName: file.expanded ? "chevron.down" : "chevron.right"))
          .fontWeight(.semibold)
          .font(.system(size: 10))
          .foregroundStyle(.serverDisclosure)
      }
      .buttonStyle(.plain)
      .frame(width: 10)
      .padding(.leading, 4)
      .padding(.trailing, 8)
      // Opening it, not selecting or dragging it.
      .fileDragPassThrough()
      
      HStack(alignment: .center) {
        if file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .frame(width: 16, height: 16)
            .opacity(0.5)
        }
        else if file.isAdminDropboxFolder {
          Image("Admin Drop Box")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else if file.isDropboxFolder {
          Image("Drop Box")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else {
          Image("Folder")
            .resizable()
            .scaledToFit()
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
          .foregroundStyle(Color.primary)
          .opacity(file.isUnavailable ? 0.5 : 1.0)
          // Where its name is, for a click on it, once it's selected, to rename it.
          .filePlace(self.file, in: self.namePlaces)
      }
      
      if loading {
        ProgressView().controlSize(.mini).padding([.leading, .trailing], 5)
      }
      Spacer()
      if !file.isUnavailable {
        Text(self.count == 0 ? "Empty" : "^[\(self.count) \("file")](inflect: true)")
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Where it is in the list, for what's dropped on it to go into it.
    .filePlace(self.file, in: self.places)
    // Where what's dragged over it, or what's shown in it, would go, out to the row's edges, to meet
    // the rows above and below it that show it too.
    .background {
      if let joins = self.dropTarget?.shows(self.file.path) {
        FileDropHighlight(above: joins.above, below: joins.below)
          .padding(.horizontal, -6)
          .padding(.vertical, -4)
      }
    }
    // Opened, what's in it, listed again, and shown once it's come, and not what was in it when it
    // was last open until then, which would only go as the new listing came in, in its place.
    .onChange(of: file.expanded) {
      self.listing?.cancel()
      self.loading = file.expanded
      if file.expanded {
        self.listing = Task {
          let _ = try? await model.getFileList(path: file.path)
          if !Task.isCancelled {
            self.loading = false
          }
        }
      }
    }
    // Inside the row's theming, which sets what the list draws for the row, from the outside.
    .fileDragSource(self.file)
    .serverThemedRow(for: self.file)
    
    if file.expanded && !self.loading {
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
}
