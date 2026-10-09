import SwiftUI
import UniformTypeIdentifiers

struct FolderIconView: View {
  private var folderIcon: Image {
#if os(iOS)
    return Image(systemName: "folder.fill")
#elseif os(macOS)
    return Image(nsImage: NSWorkspace.shared.icon(for: UTType.folder))
#endif
  }
  
  var body: some View {
    self.folderIcon
      .resizable()
      .scaledToFit()
  }
}

struct FileIconView: View {
  let filename: String
  let fileType: String?
  
  #if os(iOS)
  private var fileIcon: Image {
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
  private var fileIcon: Image {
    Image(nsImage: NSWorkspace.shared.icon(for: Self.contentType(filename: self.filename, fileType: self.fileType)))
  }

  /// What a file is, by its extension, or without one, by its type code, as its icon shows.
  static func contentType(filename: String, fileType: String?) -> UTType {
    let fileExtension = (filename as NSString).pathExtension

    if !fileExtension.isEmpty,
       let uttype = UTType(filenameExtension: fileExtension) {
      return uttype
    }
    else if let fileType,
            let fileTypeExtension = FileManager.HFSTypeToExtension[fileType.lowercased()],
            let uttype = UTType(filenameExtension: fileTypeExtension) {
      return uttype
    }
    else {
      return .data
    }
  }
  #endif

  
  var body: some View {
    self.fileIcon
      .resizable()
      .scaledToFit()
  }
}
