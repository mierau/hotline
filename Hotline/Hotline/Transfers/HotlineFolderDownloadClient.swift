import Foundation
import Network

/// Item progress callback for folder downloads
public struct HotlineFolderItemProgress: Sendable {
  public let fileName: String
  public let itemNumber: Int
  public let totalItems: Int
}

@MainActor
public class HotlineFolderDownloadClient: @MainActor HotlineTransferClient {
  private let serverAddress: String
  private let serverPort: UInt16
  private let referenceNumber: UInt32
  private let useTLS: Bool

  private let transferTotal: Int // Total byte size of all files in folder.
  private let folderItemCount: Int // Total numbner of items in the folder hierarchy.

  private var socket: NetSocket?
  private var downloadTask: Task<URL, Error>?
  private var folderProgress: Progress?

  private var estimator: TransferRateEstimator

  public init(
    address: String,
    port: UInt16,
    reference: UInt32,
    size: UInt32,
    itemCount: Int,
    useTLS: Bool = false
  ) {
    self.serverAddress = address
    self.serverPort = port
    self.referenceNumber = reference
    self.useTLS = useTLS
    self.transferTotal = Int(size)
    self.folderItemCount = itemCount

    self.estimator = TransferRateEstimator(total: self.transferTotal)
  }

  // MARK: - API

  public func download(
    to location: HotlineDownloadLocation,
    progress progressHandler: (@Sendable (HotlineTransferProgress) -> Void)? = nil,
    items itemProgressHandler: (@Sendable (HotlineFolderItemProgress) -> Void)? = nil
  ) async throws -> URL {
    progressHandler?(.preparing)
    
    self.downloadTask?.cancel()

    let task = Task<URL, Error> {
      try await performDownload(
        to: location,
        progressHandler: progressHandler,
        itemProgressHandler: itemProgressHandler
      )
    }
    self.downloadTask = task

    do {
      let url = try await task.value
      self.downloadTask = nil
      return url
    } catch {
      print("HotlineFolderDownloadClient[\(self.referenceNumber)]: Failed to download folder: \(error)")
      self.downloadTask = nil
      progressHandler?(.error(error))
      throw error
    }
  }

  /// Cancel the current download
  public func cancel() {
    self.downloadTask?.cancel()
    self.downloadTask = nil

    if let socket = self.socket {
      Task {
        await socket.close()
      }
    }
  }

  // MARK: - Implementation

  private func performDownload(
    to destination: HotlineDownloadLocation,
    progressHandler: (@Sendable (HotlineTransferProgress) -> Void)?,
    itemProgressHandler: (@Sendable (HotlineFolderItemProgress) -> Void)?
  ) async throws -> URL {
    
    var destinationFilename: String

    progressHandler?(.connecting)

    // Connect to transfer server
    let tlsPolicy: TLSPolicy = self.useTLS ? .enabled() : .disabled
    let socket = try await NetSocket.connect(
      host: self.serverAddress,
      port: self.serverPort + 1,
      tls: tlsPolicy
    )
    self.socket = socket
    defer { Task { await socket.close() } }

    // Determine destination folder URL
    let fm = FileManager.default
    let destinationURL: URL

    switch destination {
    case .url(let url):
      destinationURL = url
      destinationFilename = url.lastPathComponent
    case .downloads(let filename):
      destinationURL = URL.downloadsDirectory.generateUniqueFileURL(filename: filename)
      destinationFilename = destinationURL.lastPathComponent
    }

    print("HotlineFolderDownloadClient[\(self.referenceNumber)]: Downloading folder to \(destinationURL.path)")

    // Create destination folder
    try? fm.removeItem(at: destinationURL)
    try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)

    // Create and publish progress for the entire folder (shows in Finder)
    let progress = Progress(totalUnitCount: Int64(self.transferTotal))
    progress.fileURL = destinationURL
    progress.fileOperationKind = .downloading
    progress.publish()
    defer { progress.unpublish() }
    self.folderProgress = progress

    // Send initial magic header
    try await socket.write(Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero           // data size = 0
      UInt16(1)             // type = 1 (folder transfer)
      UInt16.zero           // reserved = 0
      HotlineFolderAction.nextFile.rawValue // action = 3 (next file)
    })

    progressHandler?(.connected)
    progressHandler?(.transfer(name: destinationFilename, size: 0, total: self.transferTotal, progress: 0.0, speed: nil, estimate: nil))

    var completedItemCount = 0

    // Process each item in the folder
    while completedItemCount < self.folderItemCount {
      // Read item header
      let headerLenData = try await socket.read(2)
      let headerLen = Int(headerLenData.readUInt16(at: 0)!)
      let headerData = try await socket.read(headerLen)

      self.updateProgress(2 + headerLen)

      guard let (itemType, pathComponents) = self.parseItemHeaderPath(headerData) else {
        throw HotlineTransferClientError.failedToTransfer
      }

      if itemType == 1 {
        // Folder entry - no progress shown for folder creation
        if !pathComponents.isEmpty {
          let folderURL = destinationURL.appendingPathComponents(pathComponents)
          try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
          print("HotlineFolderDownloadClient[\(self.referenceNumber)]: Created folder at \(folderURL.path)")
        }

        completedItemCount += 1

        // Request next item if not done
        if completedItemCount < self.folderItemCount {
          try await sendAction(socket: socket, action: .nextFile) // nextFile
        }

      } else if itemType == 0 {
        // File entry
        let parentComponents = pathComponents.dropLast()
        let fileName = pathComponents.last ?? "Untitled"

        // Request file download
        try await sendAction(socket: socket, action: .sendFile) // sendFile

        // Read file size
        let fileSizeData = try await socket.read(4)
        let fileSize = fileSizeData.readUInt32(at: 0)!

        self.updateProgress(4)

        // Notify item progress before download starts
        completedItemCount += 1
        itemProgressHandler?(HotlineFolderItemProgress(
          fileName: fileName,
          itemNumber: completedItemCount,
          totalItems: self.folderItemCount
        ))

        // Download the file with overall folder progress tracking
        try await self.downloadFile(
          socket: socket,
          fileName: fileName,
          parentPath: Array(parentComponents),
          destinationFolder: destinationURL,
          fileSize: fileSize,
          progressHandler: progressHandler
        )

        // Request next item if not done
        if completedItemCount < self.folderItemCount {
          try await sendAction(socket: socket, action: .nextFile) // nextFile
        }

      } else {
        // Unknown item type
        print("HotlineFolderDownloadClient[\(self.referenceNumber)]: Unknown item type \(itemType), skipping")
        completedItemCount += 1

        if completedItemCount < self.folderItemCount {
          try await sendAction(socket: socket, action: .nextFile) // nextFile
        }
      }
    }

    print("HotlineFolderDownloadClient[\(referenceNumber)]: Download complete!")

    // Ensure folder progress shows 100% complete
    self.folderProgress?.completedUnitCount = Int64(self.transferTotal)
    progressHandler?(.completed(url: destinationURL))

    return destinationURL
  }

  // MARK: -

  private func sendAction(socket: NetSocket, action: HotlineFolderAction) async throws {
    let actionData = Data(endian: .big) {
      action.rawValue
    }
    try await socket.write(actionData)
    print("HotlineFolderDownloadClient[\(referenceNumber)]: Sent action: \(action)")
  }

  private func parseItemHeaderPath(_ headerData: Data) -> (type: UInt16, components: [String])? {
    // Need at least: type(2) + count(2)
    guard headerData.count >= 4,
          let type = headerData.readUInt16(at: 0),
          let count = headerData.readUInt16(at: 2) else { return nil }

    var ofs = 4
    var comps: [String] = []
    for _ in 0..<Int(count) {
      guard headerData.count >= ofs + 3 else { return nil }
      // per Hotline path encoding: reserved(2) then nameLen(1) then name
      ofs += 2 // reserved == 0
      let nameLen = Int(headerData.readUInt8(at: ofs)!)
      ofs += 1
      guard headerData.count >= ofs + nameLen else { return nil }
      let nameData = headerData.subdata(in: ofs..<(ofs + nameLen))
      ofs += nameLen

      let name = String(data: nameData, encoding: .macOSRoman)
      ?? String(data: nameData, encoding: .utf8)
      ?? ""
      comps.append(name)
    }
    return (type, comps)
  }
  
  @discardableResult
  private func updateProgress(_ sent: Int) -> NetSocket.FileProgress {
    let progress = self.estimator.update(bytes: sent)
    self.folderProgress?.completedUnitCount = Int64(progress.sent)
    return progress
  }
  
  @discardableResult
  private func downloadFile(
    socket: NetSocket,
    fileName: String,
    parentPath: [String],
    destinationFolder: URL,
    fileSize: UInt32,
    progressHandler: (@Sendable (HotlineTransferProgress) -> Void)?
  ) async throws -> URL {
    let fm = FileManager.default
//    var bytesRead = 0

    // Read file header
    let headerData = try await socket.read(HotlineFileHeader.DataSize)
    guard let header = HotlineFileHeader(from: headerData) else {
      throw HotlineTransferClientError.failedToTransfer
    }
    self.updateProgress(HotlineFileHeader.DataSize)

    print("HotlineFolderDownloadClient[\(self.referenceNumber)]: File has \(header.forkCount) forks")

    var resourceForkData: Data?
    var fileHandle: FileHandle?
    var filePath: URL?
    var fileDataForkSize: Int = 0

    defer {
      try? fileHandle?.close()
    }

    // Process each fork
    for _ in 0..<Int(header.forkCount) {
      // Read fork header
      let forkHeaderData = try await socket.read(HotlineFileForkHeader.DataSize)
      guard let forkHeader = HotlineFileForkHeader(from: forkHeaderData) else {
        throw HotlineTransferClientError.failedToTransfer
      }
      self.updateProgress(HotlineFileForkHeader.DataSize)

      if forkHeader.isInfoFork {
        // Info fork
        let infoData = try await socket.read(Int(forkHeader.dataSize))
        self.updateProgress(infoData.count)

        guard let info = HotlineFileInfoFork(from: infoData) else {
          throw HotlineTransferClientError.failedToTransfer
        }

        // Create parent folder
        let parentFolderURL = destinationFolder.appendingPathComponents(parentPath)
        if !fm.fileExists(atPath: parentFolderURL.path) {
          try fm.createDirectory(at: parentFolderURL, withIntermediateDirectories: true)
        }

        // Determine final file path
        let finalURL = parentFolderURL.appendingPathComponent(fileName)
        filePath = finalURL

        // Remove existing file if present and create with metadata
        try? fm.removeItem(at: finalURL)
        fileHandle = try fm.createHotlineFile(at: finalURL, infoFork: info)

      }
      else if forkHeader.isDataFork {
        // Data fork
        guard let fh = fileHandle else {
          throw HotlineTransferClientError.failedToTransfer
        }

        fileDataForkSize = Int(forkHeader.dataSize)

        // Stream data fork to disk
        let updates = await socket.receiveFile(to: fh, length: fileDataForkSize)
        for try await fileProgress in updates {
          let progress = self.updateProgress(fileProgress.now)
          
          // Report overall folder progress to UI
          progressHandler?(.transfer(
            name: fileName,
            size: progress.sent,
            total: progress.total ?? 0,
            progress: progress.progress,
            speed: progress.bytesPerSecond,
            estimate: progress.estimatedTimeRemaining
          ))
        }

      } else if forkHeader.isResourceFork {
        // Resource fork
        resourceForkData = try await socket.read(Int(forkHeader.dataSize))
        let progress = self.updateProgress(resourceForkData?.count ?? 0)
        progressHandler?(.transfer(
          name: fileName,
          size: progress.sent,
          total: progress.total ?? 0,
          progress: progress.progress,
          speed: progress.bytesPerSecond,
          estimate: progress.estimatedTimeRemaining
        ))

      } else {
        // Unsupported fork
        try await socket.skip(Int(forkHeader.dataSize))
        let progress = self.updateProgress(Int(forkHeader.dataSize))
        progressHandler?(.transfer(
          name: fileName,
          size: progress.sent,
          total: progress.total ?? 0,
          progress: progress.progress,
          speed: progress.bytesPerSecond,
          estimate: progress.estimatedTimeRemaining
        ))
      }
    }

    // Close file handle
    try? fileHandle?.close()
    fileHandle = nil

    guard let filePath else {
      throw HotlineTransferClientError.failedToTransfer
    }

    // Write resource fork if present
    if let rsrcData = resourceForkData, !rsrcData.isEmpty {
      try writeResourceFork(data: rsrcData, to: filePath)
    }

    return filePath
  }

  private func writeResourceFork(data: Data, to url: URL) throws {
    try data.write(to: url.resolvingSymlinksInPath().urlForResourceFork())
  }
}
