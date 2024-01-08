import UniformTypeIdentifiers

enum PreviewFileType: Equatable {
  case unknown
  case image
  case text
}

struct PreviewFileInfo: Identifiable, Codable {
  var id: UInt32
  var address: String
  var port: Int
  var size: Int
  var name: String
  
  var previewType: FilePreviewType {
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
