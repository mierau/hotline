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
  /// than downloaded: which kind, through which connection, and where on the server it is.
  var archiveKind: ArchiveKind? = nil
  var hotlineID: UUID? = nil
  var path: [String]? = nil

  /// A picture linked in chat, which comes from the web rather than from a Hotline server.
  var webURL: URL? = nil

  var isArchive: Bool {
    self.archiveKind != nil
  }
  
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

  /// A picture, a PICT among them, or a video, going by its name, or its type for a PICT.
  var isPictureOrVideo: Bool {
    switch self.previewType {
    case .image, .pict:
      return true
    case .text, .unknown:
      return UTType(filenameExtension: (self.name as NSString).pathExtension)?.conforms(to: .movie) == true
    }
  }
}

extension PreviewFileInfo {
  /// A picture linked in chat, named for the end of its address, which is all there is to go on,
  /// and known by its address, so opening it again brings its window back.
  init(webImage url: URL) {
    let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    self.init(id: UInt32(truncatingIfNeeded: url.absoluteString.hashValue), address: url.host() ?? "", port: url.port ?? 443, size: 0, name: name.isEmpty || name == "/" ? "Image" : name)
    self.webURL = url
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
