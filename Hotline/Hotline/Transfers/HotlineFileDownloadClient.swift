import Foundation
import Network

public enum HotlineDownloadLocation: Sendable {
  case url(URL)
  case downloads(String)  // filename
}

public enum HotlineTransferProgress: Sendable {
  case error(Error) // An error occurred
  case unconnected // Initial state
  case preparing // Preparing to begin
  case connecting // Connecting to server
  case connected // Connected to server
  case transfer(name: String, size: Int, total: Int, progress: Double, speed: Double?, estimate: TimeInterval?) // size transferred, total size, progress (0.0-1.0), speed (in bytes/sec), time remaining
  case completed(url: URL?) // Download or upload complete (local url valid for downloads)
}


@MainActor
public class HotlineFileDownloadClient: @MainActor HotlineTransferClient {
  public struct Configuration: Sendable {
    public var chunkSize: Int = 256 * 1024
    public init() {}
  }

  private let serverAddress: String
  private let serverPort: UInt16
  private let referenceNumber: UInt32
  
  private let config: Configuration
  
  private var transferSize: Int
  private let transferTotal: Int
  private var transferProgress: Progress

  private var socket: NetSocket?
  private var downloadTask: Task<URL, Error>?

  public init(
    address: String,
    port: UInt16,
    reference: UInt32,
    size: UInt32,
    configuration: Configuration = .init()
  ) {
    self.serverAddress = address
    self.serverPort = port
    self.referenceNumber = reference
    self.config = configuration
    
    self.transferTotal = Int(size)
    self.transferSize = 0
    self.transferProgress = Progress(totalUnitCount: Int64(self.transferTotal))
  }

  // MARK: - API

  public func download(
    to location: HotlineDownloadLocation,
    progress progressHandler: (@Sendable (HotlineTransferProgress) throws -> Void)? = nil
  ) async throws -> URL {
    self.downloadTask?.cancel()
    
    let task = Task<URL, Error> {
      try await performDownload(to: location, progressHandler: progressHandler)
    }
    self.downloadTask = task
    
    do {
      let url = try await task.value
      self.downloadTask = nil
      return url
    }
    catch {
      self.downloadTask = nil
      // Stopped, from the transfers list or the Finder, which isn't a failure.
      if !(error is CancellationError) {
        try? progressHandler?(.error(error))
      }
      throw error
    }
  }

  /// Cancel the current download
  public func cancel() {
    self.downloadTask?.cancel()
    self.downloadTask = nil
  }

  // MARK: - Implementation
  
  private func updateProgress(sent: Int) throws {
    self.transferSize = sent
    self.transferProgress.completedUnitCount = Int64(sent)
    try self.checkCancelled()
  }
  
  private func checkCancelled() throws {
    if Task.isCancelled {
      throw CancellationError()
    }
    
    // People can cancel a transfer from the file icon in the Finder.
    // This code handles that.
    if self.transferProgress.isCancelled {
      throw CancellationError()
    }
  }

  private func performDownload(
    to destination: HotlineDownloadLocation,
    progressHandler: (@Sendable (HotlineTransferProgress) throws -> Void)?
  ) async throws -> URL {
    
    let fm = FileManager.default
    var fileHandle: FileHandle?

    try progressHandler?(.preparing)
    
    // Determine the download name
    // Determine destination URL based on location
    let destinationURL: URL
    let destinationFilename: String
    switch destination {
    case .url(let url):
      destinationURL = url.resolvingSymlinksInPath()
      destinationFilename = destinationURL.lastPathComponent
    case .downloads(let filename):
      destinationURL = URL.downloadsDirectory.resolvingSymlinksInPath().generateUniqueFileURL(filename: filename)
      destinationFilename = destinationURL.lastPathComponent
    }

    try self.checkCancelled()
    try progressHandler?(.connecting)
    
    // Connect to transfer server
    let socket = try await NetSocket.connect(
      host: self.serverAddress,
      port: self.serverPort + 1
    )
    defer { Task { await socket.close() } }
    self.socket = socket
    
    // See if we've been cancelled
    try self.checkCancelled()
    
    // Send magic header
    try await socket.write(Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero
      UInt32.zero
    })

    // Read file header
    let headerData = try await socket.read(HotlineFileHeader.DataSize)
    guard let header = HotlineFileHeader(from: headerData) else {
      throw HotlineTransferClientError.failedToTransfer
    }
    
    // Connected
    try progressHandler?(.connected)

    // Bytes of the flattened file received so far, across headers and all forks.
    var received = headerData.count

    do {
      // Process each fork
      for _ in 0..<Int(header.forkCount) {
        // Read fork header
        let forkHeaderData = try await socket.read(HotlineFileForkHeader.DataSize)
        guard let forkHeader = HotlineFileForkHeader(from: forkHeaderData) else {
          throw HotlineTransferClientError.failedToTransfer
        }
        received += forkHeaderData.count
        let forkSize = Int(forkHeader.dataSize)

        // Handle whichever fork is being sent.
        if forkHeader.isInfoFork {
          // Read info fork
          let infoData = try await socket.read(forkSize)
          guard let info = HotlineFileInfoFork(from: infoData) else {
            throw HotlineTransferClientError.failedToTransfer
          }
          received += infoData.count

          // Prepare temporary file for atomic write
          try? fm.removeItem(at: destinationURL)

          // Create file with metadata
          fileHandle = try fm.createHotlineFile(at: destinationURL, infoFork: info)

          // Create and configure progress, as a file operation, for the Finder to show
          self.transferProgress.kind = .file
          self.transferProgress.fileURL = destinationURL
          self.transferProgress.fileOperationKind = .downloading
          self.transferProgress.publish()

          // Update progress
          try self.updateProgress(sent: received)
        }
        else if forkHeader.isDataFork {
          guard let fh = fileHandle else {
            throw HotlineTransferClientError.failedToTransfer
          }

          // Stream data fork to disk
          try await self.receiveFork(from: socket, to: fh, length: forkSize, startingAt: received, name: destinationFilename, progressHandler: progressHandler)
          received += forkSize
        }
        else if forkHeader.isResourceFork {
          // The file is created when the info fork arrives.
          guard fileHandle != nil else {
            throw HotlineTransferClientError.failedToTransfer
          }

          // Stream resource fork to disk, so its size isn't limited by memory
          let resourceHandle = try fm.openResourceForkForWriting(at: destinationURL)
          defer { try? resourceHandle.close() }
          try await self.receiveFork(from: socket, to: resourceHandle, length: forkSize, startingAt: received, name: destinationFilename, progressHandler: progressHandler)
          received += forkSize

        } else {
          // Skip unsupported fork
          try await socket.skip(forkSize)
          received += forkSize

          try self.updateProgress(sent: received)
        }
        
        try progressHandler?(.transfer(name: destinationFilename, size: self.transferSize, total: self.transferTotal, progress: self.transferProgress.fractionCompleted, speed: nil, estimate: nil))
      }
      
      self.transferProgress.unpublish()

      // Close file handle
      try fileHandle?.close()
      fileHandle = nil

      // See if we've been cancelled
      try self.checkCancelled()

      try progressHandler?(.completed(url: destinationURL))

      return destinationURL

    }
    catch {
      // Cleanup on failure
      try? fileHandle?.close()
      try? fm.removeItem(at: destinationURL)
      self.transferProgress.unpublish()

      // Stopped, from the transfers list or the Finder, which isn't a failure.
      if !(error is CancellationError) {
        try? progressHandler?(.error(error))
      }

      throw error
    }
  }

  /// Stream one fork to disk, reporting progress for the whole file.
  ///
  /// - Parameter received: Bytes of the file received before this fork
  private func receiveFork(
    from socket: NetSocket,
    to handle: FileHandle,
    length: Int,
    startingAt received: Int,
    name: String,
    progressHandler: (@Sendable (HotlineTransferProgress) throws -> Void)?
  ) async throws {
    let updates = await socket.receiveFile(to: handle, length: length)
    for try await p in updates {
      try self.updateProgress(sent: received + p.sent)
      try progressHandler?(.transfer(name: name, size: self.transferSize, total: self.transferTotal, progress: self.transferProgress.fractionCompleted, speed: p.bytesPerSecond, estimate: p.estimatedTimeRemaining))
    }
  }
}

