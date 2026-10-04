import Foundation
import Network

@MainActor
public class HotlineFilePreviewClient {
  private let serverAddress: String
  private let serverPort: UInt16
  private let referenceNumber: UInt32
  private let fileName: String
  private let transferSize: UInt32
  private let fileType: String?
  private let fileCreator: String?

  private var downloadClient: HotlineFileDownloadClient?
  private var previewTask: Task<URL, Error>?
  private var temporaryFileURL: URL?
  
  public init(
    fileName: String,
    address: String,
    port: UInt16,
    reference: UInt32,
    size: UInt32,
    fileType: String? = nil,
    fileCreator: String? = nil
  ) {
    self.fileName = fileName
    self.serverAddress = address
    self.serverPort = port
    self.referenceNumber = reference
    self.transferSize = size
    self.fileType = fileType
    self.fileCreator = fileCreator
  }

  // MARK: - API

  /// Download file to temporary location for preview
  /// - Parameter progressHandler: Optional progress callback
  /// - Returns: URL to temporary file for preview
  public func preview(
    progress progressHandler: (@Sendable (HotlineTransferProgress) -> Void)? = nil
  ) async throws -> URL {
    self.previewTask?.cancel()

    let task = Task<URL, Error> {
      try await performPreview(progressHandler: progressHandler)
    }
    self.previewTask = task

    do {
      let url = try await task.value
      self.previewTask = nil
      return url
    } catch {
      print("HotlineFilePreviewClient[\(referenceNumber)]: Failed to preview file: \(error)")
      self.previewTask = nil
      progressHandler?(.error(error))
      throw error
    }
  }

  /// Cancel the current preview download
  public func cancel() {
    self.previewTask?.cancel()
    self.previewTask = nil
    self.downloadClient?.cancel()
  }

  /// Manually cleanup temporary file
  /// Call this when preview is complete and you no longer need the file
  public func cleanup() {
    self.cleanupTempFile()
  }

  // MARK: - Implementation

  private func performPreview(
    progressHandler: (@Sendable (HotlineTransferProgress) -> Void)?
  ) async throws -> URL {

    // Create temporary file path in system temp directory.
    // If the file has no extension but we know the type code,
    // add the appropriate extension so QuickLook can identify it.
    var previewFileName = self.fileName
    if (previewFileName as NSString).pathExtension.isEmpty,
       let fileType = self.fileType?.lowercased(),
       let ext = FileManager.HFSTypeToExtension[fileType] {
      previewFileName = "\(previewFileName).\(ext)"
    }
    // In a folder of its own, so it keeps its name, which is the one it goes by when it's shared or
    // dragged out of a preview, without meeting another file of the same name.
    let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    let tempFileURL = tempFolder.appendingPathComponent(previewFileName)
    self.temporaryFileURL = tempFileURL

    progressHandler?(.connecting)

    // Connect to transfer server
    let socket = try await NetSocket.connect(
      host: self.serverAddress,
      port: self.serverPort + 1
    )
    defer { Task { await socket.close() } }

    // Send HTXF magic header
    try await socket.write(Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero
      UInt32.zero
    })

    progressHandler?(.connected)

    // Create temp file
    var attributes: [FileAttributeKey: Any] = [:]
    if let creator = self.fileCreator, !creator.isBlank {
      attributes[.hfsCreatorCode] = creator.fourCharCode() as NSNumber
    }
    if let type = self.fileType, !type.isBlank {
      attributes[.hfsTypeCode] = type.fourCharCode() as NSNumber
    }
    guard FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: attributes) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    let fileHandle = try FileHandle(forWritingTo: tempFileURL)
    defer { try? fileHandle.close() }

    // Read the first 4 bytes to detect whether the server sends a
    // Flattened File Object (starts with "FILP") or raw file bytes.
    let magic = try await socket.read(4)
    let isFILP = magic.count == 4
      && magic[magic.startIndex] == 0x46       // 'F'
      && magic[magic.startIndex + 1] == 0x49   // 'I'
      && magic[magic.startIndex + 2] == 0x4C   // 'L'
      && magic[magic.startIndex + 3] == 0x50   // 'P'

    if isFILP {
      // Flattened File Object — read the rest of the header and
      // extract just the data fork (the actual file content).
      let restOfHeader = try await socket.read(HotlineFileHeader.DataSize - 4)
      let headerData = magic + restOfHeader
      guard let header = HotlineFileHeader(from: headerData) else {
        throw HotlineTransferClientError.failedToTransfer
      }

      for _ in 0..<Int(header.forkCount) {
        let forkHeaderData = try await socket.read(HotlineFileForkHeader.DataSize)
        guard let forkHeader = HotlineFileForkHeader(from: forkHeaderData) else {
          throw HotlineTransferClientError.failedToTransfer
        }

        let forkSize = Int(forkHeader.dataSize)

        if forkHeader.isDataFork {
          let updates = await socket.receiveFile(to: fileHandle, length: forkSize)
          for try await p in updates {
            progressHandler?(.transfer(
              name: previewFileName,
              size: p.sent,
              total: forkSize,
              progress: forkSize > 0 ? Double(p.sent) / Double(forkSize) : 0.0,
              speed: p.bytesPerSecond,
              estimate: p.estimatedTimeRemaining
            ))
          }
        } else {
          try await socket.skip(forkSize)
        }
      }
    } else {
      // Raw file bytes — write the 4 bytes we already read, then
      // stream the remainder directly to the temp file.
      fileHandle.write(magic)

      let remaining = Int(self.transferSize) - 4
      if remaining > 0 {
        let updates = await socket.receiveFile(to: fileHandle, length: remaining)
        for try await p in updates {
          let totalSent = p.sent + 4
          let totalSize = Int(self.transferSize)
          progressHandler?(.transfer(
            name: previewFileName,
            size: totalSent,
            total: totalSize,
            progress: totalSize > 0 ? Double(totalSent) / Double(totalSize) : 0.0,
            speed: p.bytesPerSecond,
            estimate: p.estimatedTimeRemaining
          ))
        }
      }
    }

    progressHandler?(.completed(url: tempFileURL))

    return tempFileURL
  }

  private func cleanupTempFile() {
    guard let tempURL = self.temporaryFileURL else { return }
    self.temporaryFileURL = nil
    
    // Delete the temp file
    Self.removeDownload(at: tempURL)
    
    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Cleaned up temp file")
  }

  /// Deletes a file this downloaded, and the folder of its own it was put in. For a file that's
  /// kept after the preview's done with it, rather than cleaned up with it.
  public static func removeDownload(at url: URL) {
    let folder = url.deletingLastPathComponent()
    // Only ever one of those folders, never the temporary folder they're in.
    guard UUID(uuidString: folder.lastPathComponent) != nil,
          folder.deletingLastPathComponent().resolvingSymlinksInPath().path(percentEncoded: false) == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path(percentEncoded: false) else {
      try? FileManager.default.removeItem(at: url)
      return
    }
    try? FileManager.default.removeItem(at: folder)
  }
}
