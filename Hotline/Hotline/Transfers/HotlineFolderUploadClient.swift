import Foundation
import Network

/// Item progress callback for folder uploads
public struct HotlineFolderItemUploadProgress: Sendable {
  public let fileName: String
  public let itemNumber: Int
  public let totalItems: Int
}

/// Represents a file or folder in the upload queue
private struct FolderItem {
  let url: URL
  let pathComponents: [String]  // Path relative to upload root
  let isFolder: Bool
}

@MainActor
public class HotlineFolderUploadClient: @MainActor HotlineTransferClient {
  public struct Configuration: Sendable {
    public var chunkSize: Int = 256 * 1024
    public init() {}
  }

  private let serverAddress: String
  private let serverPort: UInt16
  private let referenceNumber: UInt32
  private let folderURL: URL
  private let useTLS: Bool

  private let config: Configuration

  private var transferTotal: Int = 0
  private var transferSize: Int = 0
  private var folderItems: [FolderItem] = []
  private var totalItems: Int = 0

  private var socket: NetSocket?
  private var uploadTask: Task<Void, Error>?

  public init?(
    folderURL: URL,
    address: String,
    port: UInt16,
    reference: UInt32,
    useTLS: Bool = false,
    configuration: Configuration = .init()
  ) {
    guard FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) else {
      return nil
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false), isDirectory: &isDirectory),
          isDirectory.boolValue else {
      return nil
    }

    self.serverAddress = address
    self.serverPort = port
    self.referenceNumber = reference
    self.folderURL = folderURL
    self.useTLS = useTLS
    self.config = configuration

    print("HotlineFolderUploadClientNew[\(reference)]: Preparing to upload folder '\(folderURL.lastPathComponent)'")
  }

  // MARK: - API

  public func upload(
    progress progressHandler: (@Sendable (HotlineTransferProgress) -> Void)? = nil,
    itemProgress itemProgressHandler: (@Sendable (HotlineFolderItemUploadProgress) -> Void)? = nil
  ) async throws {
    self.uploadTask?.cancel()

    let task = Task<Void, Error> {
      try await performUpload(
        progressHandler: progressHandler,
        itemProgressHandler: itemProgressHandler
      )
    }
    self.uploadTask = task

    do {
      try await task.value
      self.uploadTask = nil
    } catch {
      print("HotlineFolderUploadClientNew[\(referenceNumber)]: Failed to upload folder: \(error)")
      self.uploadTask = nil
      progressHandler?(.error(error))
      throw error
    }
  }

  /// Cancel the current upload
  public func cancel() {
    uploadTask?.cancel()
    uploadTask = nil

    if let socket = socket {
      Task {
        await socket.close()
      }
    }
  }

  // MARK: - Implementation

  private enum UploadStage {
    case waitingForNextFile      // Waiting for server to send .nextFile action
    case sendingItemHeader       // Sending item header to server
    case waitingForFileAction    // Waiting for server action after file header (.sendFile, .nextFile, .resumeFile)
    case uploadingFile           // Uploading file data
    case done                    // All items uploaded
  }

  private func performUpload(
    progressHandler: (@Sendable (HotlineTransferProgress) -> Void)?,
    itemProgressHandler: (@Sendable (HotlineFolderItemUploadProgress) -> Void)?
  ) async throws {
    
    // Note that we're preparing now.
    progressHandler?(.preparing)

    // Start accessing security-scoped resource
    let didStartAccess = folderURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        self.folderURL.stopAccessingSecurityScopedResource()
      }
    }

    // Build folder hierarchy (excluding root folder itself)
    try buildFolderHierarchy()

    // Fast path if this is an empty folder
    if self.totalItems == 0 {
      progressHandler?(.completed(url: nil))
      return
    }
    
    // Note that we're connecting now.
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

    // Send magic header for folder upload
    try await socket.write(Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero           // data size = 0
      UInt16(1)             // type = 1 (folder transfer)
      UInt16.zero           // reserved = 0
    })

    progressHandler?(.connected)

    var completedItemCount = 0
    var totalBytesTransferred = 0
    var itemIndex = 0
    var stage: UploadStage = .waitingForNextFile
    var currentItem: FolderItem?

    // State machine loop
    while stage != .done {
      switch stage {

      case .waitingForNextFile:
        // Wait for server to send .nextFile action
        let action = try await self.readAction(socket: socket)
        guard action == .nextFile else {
          throw HotlineTransferClientError.failedToTransfer
        }

        // Check if we have more items to send
        if itemIndex < self.folderItems.count {
          currentItem = self.folderItems[itemIndex]
          itemIndex += 1
          stage = .sendingItemHeader
        } else {
          // No more items
          stage = .done
        }

      case .sendingItemHeader:
        // Send item header to server
        guard let item = currentItem else {
          throw HotlineTransferClientError.failedToTransfer
        }

        // Encode and send item header
        totalBytesTransferred += try await socket.write(self.encodeItemHeader(item: item))

        // Next: wait for server's response
        if item.isFolder {
          // For folders, we're done with this item (just creating the directory)
          completedItemCount += 1
          // Server should immediately respond with .nextFile
          stage = .waitingForNextFile
        } else {
          // For files, server will tell us what to do
          stage = .waitingForFileAction
        }

      case .waitingForFileAction:
        // Wait for server action after file header (.sendFile, .nextFile, .resumeFile)
        guard currentItem != nil else {
          throw HotlineTransferClientError.failedToTransfer
        }

        let action = try await self.readAction(socket: socket)
        switch action {
        case .nextFile:
          // Server wants to skip this file
          completedItemCount += 1
          // The .nextFile action means send next item, check if we have more
          if itemIndex < self.folderItems.count {
            currentItem = self.folderItems[itemIndex]
            itemIndex += 1
            stage = .sendingItemHeader
          } else {
            stage = .done
          }

        case .sendFile:
          // Server wants the file
          completedItemCount += 1
          stage = .uploadingFile

        case .resumeFile:
          // Server wants to resume
          let resumeSizeData = try await socket.read(2)
          let resumeSize = Int(resumeSizeData.readUInt16(at: 0)!)
          let _ = try await socket.read(resumeSize)
          completedItemCount += 1
          stage = .uploadingFile
        }

      case .uploadingFile:
        // Upload file data
        guard let item = currentItem else {
          throw HotlineTransferClientError.failedToTransfer
        }

        // Notify item progress
        itemProgressHandler?(HotlineFolderItemUploadProgress(
          fileName: item.url.lastPathComponent,
          itemNumber: completedItemCount,
          totalItems: self.totalItems
        ))

        // Upload the file
        let bytesUploaded = try await self.uploadFile(
          socket: socket,
          fileURL: item.url,
          itemNumber: completedItemCount,
          totalItems: self.totalItems,
          totalBytesTransferredSoFar: totalBytesTransferred,
          progressHandler: progressHandler
        )

        totalBytesTransferred += bytesUploaded
        self.transferSize = totalBytesTransferred

        // After uploading, wait for server to send .nextFile
        stage = .waitingForNextFile

      case .done:
        break
      }
    }

    // All items processed
    progressHandler?(.completed(url: nil))
  }

  private func buildFolderHierarchy() throws {
    let fm = FileManager.default
    folderItems = []
    transferTotal = 0

    let rootFolderName = folderURL.lastPathComponent

    // Recursively walk the folder
    func walkFolder(at url: URL, relativePath: [String]) throws {
      let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])

      for itemURL in contents {
        let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = resourceValues.isDirectory ?? false
        let itemName = itemURL.lastPathComponent
        let itemPath = relativePath + [itemName]

        if isDirectory {
          // Add folder to list
          folderItems.append(FolderItem(url: itemURL, pathComponents: itemPath, isFolder: true))

          // Recurse into subfolder
          try walkFolder(at: itemURL, relativePath: itemPath)

        } else {
          // Add file to list and calculate size
          if let fileSize = FileManager.default.getFlattenedFileSize(itemURL) {
            folderItems.append(FolderItem(url: itemURL, pathComponents: itemPath, isFolder: false))
            transferTotal += Int(fileSize)
          }
        }
      }
    }

    // Start from root folder with root name as first path component
    try walkFolder(at: folderURL, relativePath: [rootFolderName])
    totalItems = folderItems.count

    print("BUILD HEIRARCHY (\(folderItems.count) items):\n", folderItems)
  }

  private func encodeItemHeader(item: FolderItem) -> Data {
    let strippedPath = item.pathComponents.count > 1 ? Array(item.pathComponents.dropFirst()) : item.pathComponents
    let strippedPathCount = strippedPath.count

    // Build path components (Hotline format: reserved(2) + nameLen(1) + name)
    var pathData = Data()
    for component in strippedPath {
      let nameData = component.data(using: .macOSRoman) ?? component.data(using: .utf8) ?? Data()
      let nameLen = min(nameData.count, 255)

      pathData.append(contentsOf: [0, 0])  // reserved
      pathData.append(UInt8(nameLen))
      pathData.append(nameData.prefix(nameLen))
    }

    // Calculate header size (this is what goes in the DataSize field)
    // DataSize = isFolder(2) + pathCount(2) + pathData
    let headerSize = 2 + 2 + pathData.count

    return Data(endian: .big) {
      UInt16(headerSize)
      UInt16(item.isFolder ? 1 : 0)
      UInt16(strippedPathCount)
      pathData
    }
  }

  private func readAction(socket: NetSocket) async throws -> HotlineFolderAction {
    let actionData = try await socket.read(2)
    guard let rawAction = actionData.readUInt16(at: 0),
          let action = HotlineFolderAction(rawValue: rawAction) else {
      throw HotlineTransferClientError.failedToTransfer
    }
    return action
  }

  private func uploadFile(
    socket: NetSocket,
    fileURL: URL,
    itemNumber: Int,
    totalItems: Int,
    totalBytesTransferredSoFar: Int,
    progressHandler: (@Sendable (HotlineTransferProgress) -> Void)?
  ) async throws -> Int {
    var bytesUploaded = 0
    let filename = fileURL.lastPathComponent

    // Get file metadata
    guard let infoFork = HotlineFileInfoFork(file: fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let header = HotlineFileHeader(file: fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let forkSizes = try? FileManager.default.getFileForkSizes(fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let infoForkData = infoFork.data() else {
      throw HotlineTransferClientError.failedToTransfer
    }
    
    let dataForkSize = forkSizes.dataForkSize
    let resourceForkSize = forkSizes.resourceForkSize

    // Calculate total flattened file size
    guard let flattenedSize = FileManager.default.getFlattenedFileSize(fileURL) else {
      throw HotlineTransferClientError.failedToTransfer
    }
    let totalFileSize = Int(flattenedSize)

    // Send file size
    let fileSizeData = Data(endian: .big) {
      UInt32(totalFileSize)
    }
    try await socket.write(fileSizeData)
    bytesUploaded += 4

    // Send file header
    let headerData = header.data()
    try await socket.write(headerData)
    bytesUploaded += headerData.count

    // Send INFO fork header
    let infoForkHeader = HotlineFileForkHeader(type: HotlineFileForkType.info.rawValue, dataSize: UInt32(infoForkData.count))
    try await socket.write(infoForkHeader.data())
    bytesUploaded += HotlineFileForkHeader.DataSize

    // Send INFO fork data
    try await socket.write(infoForkData)
    bytesUploaded += infoForkData.count

    // Create per-file progress for Finder
    let fileProgress = Progress(totalUnitCount: Int64(totalFileSize))
    fileProgress.fileURL = fileURL.resolvingSymlinksInPath()
    fileProgress.fileOperationKind = Progress.FileOperationKind.uploading
    fileProgress.publish()

    defer {
      fileProgress.unpublish()
    }

    // Send DATA fork if present
    let dataForkHeader = HotlineFileForkHeader(type: HotlineFileForkType.data.rawValue, dataSize: dataForkSize)
    try await socket.write(dataForkHeader.data())
    bytesUploaded += HotlineFileForkHeader.DataSize

    if dataForkSize > 0 {
      // Stream DATA fork
      let fileHandle = try FileHandle(forReadingFrom: fileURL)
      defer { try? fileHandle.close() }

      let updates = await socket.writeFile(from: fileHandle, length: Int(dataForkSize))
      for try await p in updates {
        // Update per-file Finder progress
        fileProgress.completedUnitCount = Int64(bytesUploaded + p.sent)

        // Calculate overall folder progress
        let totalBytesNow = totalBytesTransferredSoFar + bytesUploaded + p.sent
        let rawProgress = self.transferTotal > 0 ? Double(totalBytesNow) / Double(self.transferTotal) : 0.0
        let overallProgress = min(rawProgress, 1.0)

        // Calculate overall time estimate
        let remainingBytes = max(0, self.transferTotal - totalBytesNow)
        let estimate: TimeInterval? = if let speed = p.bytesPerSecond, speed > 0, remainingBytes > 0 {
          TimeInterval(remainingBytes) / speed
        } else {
          nil
        }

        // Report overall folder progress
        progressHandler?(.transfer(
          name: filename,
          size: totalBytesNow,
          total: self.transferTotal,
          progress: overallProgress,
          speed: p.bytesPerSecond,
          estimate: estimate
        ))
      }

      bytesUploaded += Int(dataForkSize)
    }

    // Send RESOURCE fork if present
    if resourceForkSize > 0 {
      let resourceURL = fileURL.urlForResourceFork()

      let resourceForkHeader = HotlineFileForkHeader(type: HotlineFileForkType.resource.rawValue, dataSize: resourceForkSize)
      try await socket.write(resourceForkHeader.data())
      bytesUploaded += HotlineFileForkHeader.DataSize

      // Stream RESOURCE fork
      let resourceHandle = try FileHandle(forReadingFrom: resourceURL)
      defer { try? resourceHandle.close() }

      let updates = await socket.writeFile(from: resourceHandle, length: Int(resourceForkSize))
      for try await p in updates {
        // Update per-file Finder progress
        fileProgress.completedUnitCount = Int64(bytesUploaded + p.sent)

        // Calculate overall folder progress
        let totalBytesNow = totalBytesTransferredSoFar + bytesUploaded + p.sent
        let rawProgress = self.transferTotal > 0 ? Double(totalBytesNow) / Double(self.transferTotal) : 0.0
        let overallProgress = min(rawProgress, 1.0)

        // Calculate overall time estimate
        let remainingBytes = max(0, self.transferTotal - totalBytesNow)
        let estimate: TimeInterval? = if let speed = p.bytesPerSecond, speed > 0, remainingBytes > 0 {
          TimeInterval(remainingBytes) / speed
        } else {
          nil
        }

        // Report overall folder progress
        progressHandler?(.transfer(
          name: filename,
          size: totalBytesNow,
          total: self.transferTotal,
          progress: overallProgress,
          speed: p.bytesPerSecond,
          estimate: estimate
        ))
      }

      bytesUploaded += Int(resourceForkSize)
    }

    return bytesUploaded
  }
}
