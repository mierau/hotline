import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct BookmarkDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data, UTType(filenameExtension: "hlbm")!] }
  static var writableContentTypes: [UTType] { [.data, UTType(filenameExtension: "hlbm")!] }

  var bookmark: Bookmark
  
  init(bookmark: Bookmark) {
    self.bookmark = bookmark
  }
  
  init(configuration: ReadConfiguration) throws {
    guard configuration.file.isRegularFile,
          let data = configuration.file.regularFileContents,
          let fileName = configuration.file.preferredFilename,
          let bookmark = Bookmark(fileData: data, name: (fileName as NSString).deletingPathExtension)
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.bookmark = bookmark
  }
  
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let wrapper = FileWrapper(regularFileWithContents: self.bookmark.bookmarkFileData()!)
    wrapper.fileAttributes[FileAttributeKey.hfsCreatorCode.rawValue] = "HTLC".fourCharCode()
    wrapper.fileAttributes[FileAttributeKey.hfsTypeCode.rawValue] = "HTbm".fourCharCode()
    return wrapper
  }
}
