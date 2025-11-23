import Foundation
import Network

@MainActor
public class HotlineFileUploadClient: @MainActor HotlineTransferClient {
  public struct Configuration: Sendable {
    public var chunkSize: Int = 256 * 1024
    public init() {}
  }

  private let serverAddress: String
  private let serverPort: UInt16
  private let referenceNumber: UInt32
  private let fileURL: URL
  private let useTLS: Bool

  private let config: Configuration

  private var transferSize: Int
  private let transferTotal: Int
  private var transferProgress: Progress

  private var socket: NetSocket?
  private var uploadTask: Task<Void, Error>?

  public init?(
    fileURL: URL,
    address: String,
    port: UInt16,
    reference: UInt32,
    useTLS: Bool = false,
    configuration: Configuration = .init()
  ) {
    // Validate file and get total size
    guard let payloadSize = FileManager.default.getFlattenedFileSize(fileURL) else {
      return nil
    }

    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
      return nil
    }

    self.serverAddress = address
    self.serverPort = port
    self.referenceNumber = reference
    self.fileURL = fileURL
    self.useTLS = useTLS
    self.config = configuration

    self.transferTotal = Int(payloadSize)
    self.transferSize = 0
    self.transferProgress = Progress(totalUnitCount: Int64(self.transferTotal))
  }

  // MARK: - Public API

  public func upload(
    progress progressHandler: (@Sendable (HotlineTransferProgress) -> Void)? = nil
  ) async throws {
    self.uploadTask?.cancel()

    let task = Task<Void, Error> {
      try await performUpload(progressHandler: progressHandler)
    }
    self.uploadTask = task

    do {
      try await task.value
      self.uploadTask = nil
    } catch {
      print("HotlineFileUploadClient[\(self.referenceNumber)]: Failed to upload file: \(error)")
      self.uploadTask = nil
      progressHandler?(.error(error))
      throw error
    }
  }

  /// Cancel the current upload
  public func cancel() {
    self.uploadTask?.cancel()
    self.uploadTask = nil

    if let socket = self.socket {
      Task {
        await socket.close()
      }
    }
  }

  // MARK: - Implementation

  private func updateProgress(sent: Int, speed: Double? = nil, estimate: TimeInterval? = nil) {
    self.transferSize = sent
    self.transferProgress.completedUnitCount = Int64(sent)

    if self.transferProgress.isCancelled {
      self.cancel()
    }
  }

  private func performUpload(
    progressHandler: (@Sendable (HotlineTransferProgress) -> Void)?
  ) async throws {
    let filename = self.fileURL.lastPathComponent

    progressHandler?(.connecting)

    // Start accessing security-scoped resource
    let didStartAccess = fileURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        fileURL.stopAccessingSecurityScopedResource()
      }
    }

    // Connect to transfer server
    let tlsPolicy: TLSPolicy = self.useTLS ? .enabled() : .disabled
    let socket = try await NetSocket.connect(
      host: self.serverAddress,
      port: self.serverPort + 1,
      tls: tlsPolicy
    )
    defer { Task { await socket.close() } }
    self.socket = socket

    // Get file metadata
    guard let infoFork = HotlineFileInfoFork(file: self.fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let header = HotlineFileHeader(file: self.fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let forkSizes = try? FileManager.default.getFileForkSizes(self.fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let infoForkData = infoFork.data() else {
      throw HotlineTransferClientError.failedToTransfer
    }
    let dataForkSize = forkSizes.dataForkSize
    let resourceForkSize = forkSizes.resourceForkSize
    
    // Configure progress for Finder if enabled
    self.transferProgress.fileURL = self.fileURL.resolvingSymlinksInPath()
    self.transferProgress.fileOperationKind = .uploading
    self.transferProgress.publish()
    
    // Connected
    progressHandler?(.connected)

    // Send magic header
    try await socket.write(Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32(self.transferTotal)
      UInt32.zero
    })

    var totalBytesSent = 0

    // MARK: - Info Fork
    // Send file header
    let headerData = header.data()
    try await socket.write(headerData)
    totalBytesSent += headerData.count

    // Send info fork header
    let infoForkHeader = HotlineFileForkHeader(type: HotlineFileForkType.info.rawValue, dataSize: UInt32(infoForkData.count))
    try await socket.write(infoForkHeader.data())
    totalBytesSent += HotlineFileForkHeader.DataSize

    // Send info fork
    try await socket.write(infoForkData)
    totalBytesSent += infoForkData.count

    self.updateProgress(sent: totalBytesSent)
    progressHandler?(.transfer(name: filename, size: self.transferSize, total: self.transferTotal, progress: self.transferProgress.fractionCompleted, speed: nil, estimate: nil))

    // MARK: - Data Fork
    // Send data fork (if present)
    if dataForkSize > 0 {
      // Data fork header
      let dataForkHeader = HotlineFileForkHeader(type: HotlineFileForkType.data.rawValue, dataSize: dataForkSize)
      try await socket.write(dataForkHeader.data())
      totalBytesSent += HotlineFileForkHeader.DataSize

      // Stream data fork from disk
      let fileHandle = try FileHandle(forReadingFrom: self.fileURL)
      defer { try? fileHandle.close() }

      let updates = await socket.writeFile(from: fileHandle, length: Int(dataForkSize))
      for try await p in updates {
        let bytesSentNow = totalBytesSent + p.sent
        self.updateProgress(sent: bytesSentNow, speed: p.bytesPerSecond, estimate: p.estimatedTimeRemaining)
        progressHandler?(.transfer(name: filename, size: bytesSentNow, total: self.transferTotal, progress: self.transferProgress.fractionCompleted, speed: p.bytesPerSecond, estimate: p.estimatedTimeRemaining))
      }

      totalBytesSent += Int(dataForkSize)
    }

    // MARK: - Resource Fork
    // Send resource fork (if present)
    if resourceForkSize > 0 {
      let resourceURL = self.fileURL.urlForResourceFork()

      // Resource fork header
      let resourceForkHeader = HotlineFileForkHeader(type: HotlineFileForkType.resource.rawValue, dataSize: resourceForkSize)
      try await socket.write(resourceForkHeader.data())
      totalBytesSent += HotlineFileForkHeader.DataSize

      // Stream resource fork from disk
      let resourceHandle = try FileHandle(forReadingFrom: resourceURL)
      defer { try? resourceHandle.close() }

      let updates = await socket.writeFile(from: resourceHandle, length: Int(resourceForkSize))
      for try await p in updates {
        let bytesSentNow = totalBytesSent + p.sent
        self.updateProgress(sent: bytesSentNow, speed: p.bytesPerSecond, estimate: p.estimatedTimeRemaining)
        progressHandler?(.transfer(name: filename, size: bytesSentNow, total: self.transferTotal, progress: self.transferProgress.fractionCompleted, speed: p.bytesPerSecond, estimate: p.estimatedTimeRemaining))
      }

      totalBytesSent += Int(resourceForkSize)
    }

    self.transferProgress.unpublish()
    progressHandler?(.completed(url: nil))

    print("HotlineFileUploadClient[\(self.referenceNumber)]: Complete!")
  }
}
