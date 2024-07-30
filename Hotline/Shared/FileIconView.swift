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
  let fileType: String?
  
  #if os(iOS)
  private func fileIcon() -> Image {
    let fileExtension = (self.filename as NSString).pathExtension
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
  private func fileIcon() -> Image {
    let fileExtension = (self.filename as NSString).pathExtension
    
    if !fileExtension.isEmpty,
       let uttype = UTType(filenameExtension: fileExtension) {
      return Image(nsImage: NSWorkspace.shared.icon(for: uttype))
    }
    else if let fileType = self.fileType,
            let fileTypeExtension = FileManager.HFSTypeToExtension[fileType.lowercased()],
            let uttype = UTType(filenameExtension: fileTypeExtension) {
      return Image(nsImage: NSWorkspace.shared.icon(for: uttype))
    }
    else {
      return Image(nsImage: NSWorkspace.shared.icon(for: UTType.data))
    }
    
//    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (filename as NSString).pathExtension) ?? UTType.content))
  }
  #endif

  
  var body: some View {
    fileIcon()
      .resizable()
      .scaledToFit()
  }
}
