import SwiftUI
import AppKit

@MainActor
struct FileActions {
  let model: HotlineState
  let openWindow: OpenWindowAction

  func downloadFile(_ file: FileInfo) {
    if file.isFolder {
      model.downloadFolder(file.name, path: file.path)
    }
    else {
      model.downloadFile(file.name, path: file.path)
    }
  }

  func previewFile(_ file: FileInfo) {
    guard file.isPreviewable else {
      return
    }

    model.previewFile(file.name, path: file.path) { info in
      if let info = info {
        var extendedInfo = info
        extendedInfo.creator = file.creator
        extendedInfo.type = file.type
        openPreviewWindow(extendedInfo)
      }
    }
  }

  func deleteFile(_ file: FileInfo) async {
    var parentPath: [String] = []
    if file.path.count > 1 {
      parentPath = Array(file.path[0..<file.path.count-1])
    }

    do {
      try await model.deleteFile(file.name, path: file.path)
      try await model.getFileList(path: parentPath)
    }
    catch {
      print("Error deleting file: \(error)")
    }
  }

  func getFileInfo(_ file: FileInfo) async -> FileDetails? {
    return try? await model.getFileDetails(file.name, path: file.path)
  }

  func upload(file fileURL: URL, to path: [String]) {
    var fileIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &fileIsDirectory) else {
      return
    }

    if fileIsDirectory.boolValue {
      model.uploadFolder(url: fileURL, path: path, complete: { _ in
        Task {
          try? await model.getFileList(path: path)
        }
      })
    }
    else {
      model.uploadFile(url: fileURL, path: path) { _ in
        Task {
          try? await model.getFileList(path: path)
        }
      }
    }
  }

  func newFolder(name: String, parent: FileInfo?) {
    Task {
      var parentFolder: FileInfo? = nil
      if parent?.isFolder == true {
        parentFolder = parent
      }

      let path: [String] = parentFolder?.path ?? []
      do {
        if try await model.newFolder(name: name, parentPath: path) {
          try await model.getFileList(path: path)
        }
      }
      catch {
        // The server didn't make it, so there's nothing new to list.
      }
    }
  }

  func copyFileLink(_ file: FileInfo) {
    guard let server = self.model.server else { return }

    var components = URLComponents()
    components.scheme = "hotline"
    components.host = server.address
    components.port = server.port == HotlinePorts.DefaultServerPort ? nil : server.port
    var pathComponentAllowed = CharacterSet.urlPathAllowed
    pathComponentAllowed.remove(charactersIn: "/")
    let path = file.path.map {
      $0.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed) ?? $0
    }.joined(separator: "/")
    // A link to a folder ends in a slash, which is how chat knows to show it as one.
    components.percentEncodedPath = "/files/" + path + (file.isFolder ? "/" : "")

    guard let urlString = components.string else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(urlString, forType: .string)
  }

  private func openPreviewWindow(_ previewInfo: PreviewFileInfo) {
    // PICTs too, which the preview draws itself, as Quick Look can't draw most of them.
    openWindow(id: "preview-quicklook", value: previewInfo)
  }
}
