import SwiftUI

/// What's in an archive on the server, from its list, without the archive itself: a tree of its
/// files and folders to look through, with the keyboard too, under a line saying that's what it
/// is. As they aren't here, none of them can be opened.
struct FilePreviewArchiveView: View {
  let kind: ArchiveKind
  private let items: [ArchiveItem]
  /// Only for moving around, with the arrow keys.
  @State private var selection: ArchiveItem.ID?
  @FocusState private var listFocused: Bool

  init(kind: ArchiveKind, entries: [ArchiveEntry]) {
    self.kind = kind
    self.items = ArchiveItem.tree(entries)
  }

  var body: some View {
    VStack(spacing: 0) {
      Label("Previewing \(self.kind.name) contents", systemImage: "eye")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)

      Divider()

      if self.items.isEmpty {
        Text("This archive is empty.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      else {
        List(self.items, children: \.children, selection: self.$selection) { item in
          ArchiveItemRow(item: item)
        }
        .environment(\.defaultMinListRowHeight, 28)
        .listStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
        .focused(self.$listFocused)
        // Ready for the arrow keys as soon as it's shown.
        .onAppear {
          self.listFocused = true
        }
      }
    }
    .frame(minWidth: 380, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
  }

  static func byteCount(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
  }
}

/// A file or folder in an archive, as the Files list shows one on the server.
private struct ArchiveItemRow: View {
  let item: ArchiveItem

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      Group {
        if self.item.isFolder {
          Image("Folder")
            .resizable()
            .scaledToFit()
        }
        else {
          FileIconView(filename: self.item.name, fileType: self.item.type)
        }
      }
      .frame(width: 16, height: 16)
      Text(self.item.name)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Group {
        if self.item.isFolder {
          let count = self.item.children?.count ?? 0
          Text(count == 0 ? "Empty" : "^[\(count) \("file")](inflect: true)")
        }
        else {
          Text(FilePreviewArchiveView.byteCount(self.item.size))
        }
      }
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
  }
}

/// Something in an archive, with what's in it, if it's a folder.
struct ArchiveItem: Identifiable {
  /// Its place in the archive.
  let id: String
  let name: String
  let isFolder: Bool
  let size: UInt64
  /// A Mac file's type code, which says what it is when its name doesn't.
  let type: String?
  /// Nil for a file, or a folder with nothing in it, which has nothing to show.
  let children: [ArchiveItem]?

  /// The tree of what's in an archive, from its list, which needn't list each folder there's
  /// something in. In the order the Finder sorts names.
  static func tree(_ entries: [ArchiveEntry]) -> [ArchiveItem] {
    self.items(entries.map { (components: $0.path.split(separator: "/").map(String.init), entry: $0) }, in: "")
  }

  private static func items(_ entries: [(components: [String], entry: ArchiveEntry)], in folder: String) -> [ArchiveItem] {
    let byName = Dictionary(grouping: entries.filter { !$0.components.isEmpty }) { $0.components[0] }
    return byName.map { name, group in
      let path = folder.isEmpty ? name : "\(folder)/\(name)"
      let inside = group.filter { $0.components.count > 1 }.map { (components: Array($0.components.dropFirst()), entry: $0.entry) }
      if inside.isEmpty, let file = group.first?.entry, !file.isFolder {
        return ArchiveItem(id: path, name: name, isFolder: false, size: file.size, type: file.type, children: nil)
      }
      let children = self.items(inside, in: path)
      return ArchiveItem(id: path, name: name, isFolder: true, size: 0, type: nil, children: children.isEmpty ? nil : children)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
