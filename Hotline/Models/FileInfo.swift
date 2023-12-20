import SwiftUI

@Observable class FileInfo: Identifiable, Hashable {
  let id: UUID
  
  let path: [String]
  let name: String
  
  let type: String
  let creator: String
  let fileSize: UInt
  
  let isFolder: Bool
  var expanded: Bool = false
  var children: [FileInfo]? = nil
  
  init(hotlineFile: HotlineFile) {
    self.id = UUID()
    self.path = hotlineFile.path
    self.name = hotlineFile.name
    self.type = hotlineFile.type
    self.creator = hotlineFile.creator
    self.fileSize = UInt(hotlineFile.fileSize)
    self.isFolder = hotlineFile.isFolder
    if self.isFolder {
      self.children = []
    }
  }
  
  static func == (lhs: FileInfo, rhs: FileInfo) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
