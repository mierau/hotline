import Foundation

extension URL {
  func generateUniqueFilePath(filename base: String) -> String {
    let fileManager = FileManager.default
    var finalName = base
    var counter = 2
    
    // Helper function to generate a new filename with a counter
    func makeFileName() -> String {
      let baseName = (base as NSString).deletingPathExtension
      let extensionName = (base as NSString).pathExtension
      return extensionName.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(extensionName)"
    }
    
    // Check if file exists and append counter until a unique name is found
    var filePath = self.appending(component: finalName).path(percentEncoded: false)
    while fileManager.fileExists(atPath: filePath) {
      finalName = makeFileName()
      filePath = self.appending(component: finalName).path(percentEncoded: false)
      counter += 1
    }
    
    return filePath
  }
  
//  private func prepareDownloadFile(name: String) -> Bool {
//    let folderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
//    let filePath = findUniqueFilePath(base: name, at: folderURL)
//    
//    if FileManager.default.createFile(atPath: filePath, contents: nil) {
//      if let h = FileHandle(forWritingAtPath: filePath) {
//        self.filePath = filePath
//        self.fileHandle = h
//        self.fileProgress?.fileURL = URL(filePath: filePath).resolvingSymlinksInPath()
//        return true
//      }
//    }
//    
//    return false
//  }
}
