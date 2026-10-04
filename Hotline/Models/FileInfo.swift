import SwiftUI
import UniformTypeIdentifiers

@Observable class FileInfo: Identifiable, Hashable {
  let id: UUID
  
  let path: [String]
  let name: String
  
  let type: String
  let creator: String
  let fileSize: UInt
  
  let isFolder: Bool
  let isUnavailable: Bool
  
  var isDropboxFolder: Bool {
    guard self.isFolder else {
      return false
    }

    if self.name.range(of: "upload", options: [.caseInsensitive]) != nil {
      return true
    }

    if self.name.range(of: "dropbox", options: [.caseInsensitive]) != nil {
      return true
    }

    if self.name.range(of: "drop box", options: [.caseInsensitive]) != nil {
      return true
    }

    return false
  }
  
  var isAdminDropboxFolder: Bool {
    self.isDropboxFolder && (self.name.range(of: "admin", options: [.caseInsensitive]) != nil)
  }
  
  var isAppBundle: Bool {
    guard self.isFolder else {
      return false
    }
    return self.name.lowercased().hasSuffix(".app")
  }
  
  var expanded: Bool = false
  var children: [FileInfo]? = nil

  /// Whether this folder's contents were fetched from the server
  /// (as opposed to being a placeholder created by ensureIntermediateFolders).
  var loaded: Bool = false
  
  var isPreviewable: Bool {
    var fileExtension = (self.name as NSString).pathExtension.lowercased()
    if fileExtension.isEmpty && !self.type.isEmpty {
      let type = self.type.lowercased()
      if let ext = FileManager.HFSTypeToExtension[type] {
        fileExtension = ext
      }
    }
    
    if let fileType = UTType(filenameExtension: fileExtension) {
      if fileType.canBePreviewedByQuickLook {
        return true
      }
      
      if fileType.isSubtype(of: .image) {
        return true
      }
      else if fileType.isSubtype(of: .pdf) || fileExtension == "pdf" {
        return true
      }
      else if fileType.isSubtype(of: .audio) {
        return true
      }
      else if fileType.isSubtype(of: .video) {
        return true
      }
      else if fileType.isSubtype(of: .text) {
        return true
      }
    }
    return false
  }
  
  var isImage: Bool {
    let fileExtension = (self.name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      if fileType.isSubtype(of: .image) {
        return true
      }
    }
    return false
  }
  
  init(hotlineFile: HotlineFile) {
    self.id = UUID()
    self.path = hotlineFile.path
    self.name = hotlineFile.name
    self.type = hotlineFile.type
    self.creator = hotlineFile.creator
    self.fileSize = UInt(hotlineFile.fileSize)
    self.isFolder = hotlineFile.isFolder
    self.isUnavailable = (!self.isFolder && (self.fileSize == 0))

    print(self.name, self.type, self.creator, self.isUnavailable)
    if self.isFolder {
      self.children = []
    }
  }

  /// A file or folder known only from a link to it, as in chat, without its type, creator, or size.
  init(linkedName name: String, path: [String], isFolder: Bool) {
    self.id = UUID()
    self.path = path
    self.name = name
    self.type = ""
    self.creator = ""
    self.fileSize = 0
    self.isFolder = isFolder
    self.isUnavailable = false
    if isFolder {
      self.children = []
    }
  }

  /// Creates a placeholder folder node for building intermediate tree paths.
  init(folderName: String, path: [String]) {
    self.id = UUID()
    self.path = path
    self.name = folderName
    self.type = ""
    self.creator = ""
    self.fileSize = 0
    self.isFolder = true
    self.isUnavailable = false
    self.children = []
  }
  
  static func == (lhs: FileInfo, rhs: FileInfo) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
