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
  private let useTLS: Bool

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
    fileCreator: String? = nil,
    useTLS: Bool = false
  ) {
    self.fileName = fileName
    self.serverAddress = address
    self.serverPort = port
    self.referenceNumber = reference
    self.transferSize = size
    self.fileType = fileType
    self.fileCreator = fileCreator
    self.useTLS = useTLS
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

    // Create temporary file path directly in system temp directory
    let tempDir = FileManager.default.temporaryDirectory
    let uniqueFileName = "\(UUID().uuidString)_\(self.fileName)"
    let tempFileURL = tempDir.appendingPathComponent(uniqueFileName)
    self.temporaryFileURL = tempFileURL

    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Downloading to temp: \(tempFileURL.path)")

    progressHandler?(.connecting)

    // Connect to transfer server
    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Connecting to \(self.serverAddress):\(self.serverPort + 1)")
    let tlsPolicy: TLSPolicy = self.useTLS ? .enabled() : .disabled
    let socket = try await NetSocket.connect(
      host: self.serverAddress,
      port: self.serverPort + 1,
      tls: tlsPolicy
    )
    defer { Task { await socket.close() } }

    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Connected!")

    // Send magic header for raw data download
    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Sending magic header")
    try await socket.write(Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero
      UInt32.zero
    })

    progressHandler?(.connected)

    // Stream raw data directly to temp file with progress tracking
    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Streaming \(self.transferSize) bytes to temp file")

    let totalSize = Int(self.transferSize)

    // Create empty file (with HFS attributes if available)
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

    let updates = await socket.receiveFile(to: fileHandle, length: totalSize)
    for try await p in updates {
      progressHandler?(.transfer(
        name: uniqueFileName,
        size: p.sent,
        total: totalSize,
        progress: totalSize > 0 ? Double(p.sent) / Double(totalSize) : 0.0,
        speed: p.bytesPerSecond,
        estimate: p.estimatedTimeRemaining
      ))
    }

    progressHandler?(.completed(url: tempFileURL))

    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Preview file ready at \(tempFileURL.path)")

    return tempFileURL
  }

  private func cleanupTempFile() {
    guard let tempURL = self.temporaryFileURL else { return }
    self.temporaryFileURL = nil
    
    // Delete the temp file
    try? FileManager.default.removeItem(at: tempURL)
    
    print("HotlineFilePreviewClient[\(self.referenceNumber)]: Cleaned up temp file")
  }
}
