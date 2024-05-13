import SwiftUI
import UniformTypeIdentifiers

struct FolderIconView: View {
  private func folderIcon() -> Image {
#if os(iOS)
    return Image(systemName: "folder.fill")
#elseif os(macOS)
    return Image(nsImage: NSWorkspace.shared.icon(for: UTType.folder))
#endif
  }
  
  var body: some View {
    folderIcon()
      .resizable()
      .scaledToFit()
  }
}

struct FileIconView: View {
  let filename: String
  
  #if os(iOS)
  private func fileIcon(filename: String) -> Image {
    let fileExtension = (filename as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      if fileType.isSubtype(of: .movie) {
        return Image(systemName: "play.rectangle")
      }
      else if fileType.isSubtype(of: .image) {
        return Image(systemName: "photo")
      }
      else if fileType.isSubtype(of: .archive) {
        return Image(systemName: "doc.zipper")
      }
      else if fileType.isSubtype(of: .text) {
        return Image(systemName: "doc.text")
      }
      else {
        return Image(systemName: "doc")
      }
    }
    
    return Image(systemName: "doc")
  }
  #elseif os(macOS)
  private func fileIcon(filename: String) -> Image {
    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (filename as NSString).pathExtension) ?? UTType.content))
  }
  #endif

  
  var body: some View {
    fileIcon(filename: filename)
      .resizable()
      .scaledToFit()
  }
}
