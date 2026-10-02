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

  func upload(file fileURL: URL, to path: [String], complete: (() -> Void)? = nil) {
    var fileIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &fileIsDirectory) else {
      complete?()
      return
    }

    if fileIsDirectory.boolValue {
      model.uploadFolder(url: fileURL, path: path, complete: { _ in
        complete?()
        Task {
          try? await model.getFileList(path: path)
        }
      })
    }
    else {
      model.uploadFile(url: fileURL, path: path) { _ in
        complete?()
        Task {
          try? await model.getFileList(path: path)
        }
      }
    }
  }

  /// Uploads every file URL carried by a set of dropped item providers to `path`.
  /// Returns false when none of the providers carry anything we can load.
  func upload(droppedItems items: [NSItemProvider], to path: [String]) -> Bool {
    var handled = false

    for item in items {
      guard let identifier = item.registeredTypeIdentifiers.first else {
        continue
      }

      handled = true
      item.loadItem(forTypeIdentifier: identifier, options: nil) { (urlData, error) in
        DispatchQueue.main.async {
          guard let urlData = urlData as? Data,
                let fileURL = URL(dataRepresentation: urlData, relativeTo: nil, isAbsolute: true) else {
            return
          }

          // Access has to outlive the transfer, so it is released by the upload's
          // completion rather than when this block returns.
          let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
          self.upload(file: fileURL, to: path) {
            if didStartAccessing {
              fileURL.stopAccessingSecurityScopedResource()
            }
          }
        }
      }
    }

    return handled
  }

  func newFolder(name: String, parent: FileInfo?) {
    Task {
      var parentFolder: FileInfo? = nil
      if parent?.isFolder == true {
        parentFolder = parent
      }

      let path: [String] = parentFolder?.path ?? []
      if try await model.newFolder(name: name, parentPath: path) {
        try await model.getFileList(path: path)
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
    components.percentEncodedPath = "/files/" + file.path.map {
      $0.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed) ?? $0
    }.joined(separator: "/")

    guard let urlString = components.string else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(urlString, forType: .string)
  }

  private func openPreviewWindow(_ previewInfo: PreviewFileInfo) {
    switch previewInfo.previewType {
    case .image:
      openWindow(id: "preview-quicklook", value: previewInfo)
    case .text:
      openWindow(id: "preview-quicklook", value: previewInfo)
    case .unknown:
      openWindow(id: "preview-quicklook", value: previewInfo)
    }
  }
}
