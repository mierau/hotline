import UniformTypeIdentifiers

struct PreviewFileInfo: Identifiable, Codable {
  var id: UInt32
  var address: String
  var port: Int
  var size: Int
  var name: String
  
  var type: String? = nil
  var creator: String? = nil

  /// An archive, which is shown by what's in it, read from the server a little at a time, rather
  /// than downloaded: through which connection, and where on the server it is.
  var isArchive: Bool = false
  var hotlineID: UUID? = nil
  var path: [String]? = nil
  
  var previewType: FilePreviewType {
    #if os(macOS)
    if PICTImage.isPICT(name: self.name, hfsType: self.type) {
      return .pict
    }
    #endif

    let fileExtension = (self.name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      if fileType.isSubtype(of: .image) {
        return .image
      }
      else if fileType.isSubtype(of: .text) {
        return .text
      }
    }
    return .unknown
  }
}

extension PreviewFileInfo: Equatable {
  static func == (lhs: PreviewFileInfo, rhs: PreviewFileInfo) -> Bool {
    return lhs.id == rhs.id
  }
}

extension PreviewFileInfo: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
