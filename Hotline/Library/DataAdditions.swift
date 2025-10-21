import Foundation

extension Data {
  func saveAsFileToDownloads(filename: String, bounceDock: Bool = true) -> Bool {
    let folderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    let filePath = folderURL.generateUniqueFilePath(filename: filename)
    if FileManager.default.createFile(atPath: filePath, contents: nil) {
      if let h = FileHandle(forWritingAtPath: filePath) {
        try? h.write(contentsOf: self)
        try? h.close()
        if bounceDock {
          #if os(macOS)
          var downloadURL = URL(filePath: filePath)
          downloadURL.resolveSymlinksInPath()
          DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: downloadURL.path)
          #endif
        }
        return true
      }
    }
    return false
  }
}
