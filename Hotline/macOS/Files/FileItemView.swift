import SwiftUI

struct FileItemView: View {
  @Environment(Hotline.self) private var model: Hotline
  
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
      
      Text(file.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(file.isUnavailable ? 0.5 : 1.0)

      Spacer()
      if !file.isUnavailable {
        Text(formattedFileSize(file.fileSize))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
