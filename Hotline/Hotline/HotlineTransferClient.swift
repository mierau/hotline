import Foundation
import Network
import UniformTypeIdentifiers

enum HotlineFileClientError: Error {
  case failedToConnect
  case failedToDownload
  case failedToUpload
}

enum HotlineFileFork {
  case none
  case info
  case data
  case resource
  case unsupported
}

enum HotlineTransferStatus: Equatable {
  case unconnected
  case connecting
  case connected
  case progress(Double)
  case completing
  case completed
  case failed(HotlineFileClientError)
}

enum HotlineFileForkType: UInt32 {
  case none = 0
  case unsupported = 1
  case info = 0x494E464F // 'INFO'
  case data = 0x44415441 // 'DATA'
  case resource = 1296122706 // 'MACR'
}

protocol HotlineTransferDelegate: AnyObject {
  func hotlineTransferStatusChanged(client: HotlineTransferClient, reference: UInt32, status: HotlineTransferStatus, timeRemaining: TimeInterval)
}

protocol HotlineFileDownloadClientDelegate: HotlineTransferDelegate {
  func hotlineFileDownloadReceivedInfo(client: HotlineFileDownloadClient, reference: UInt32, info: HotlineFileInfoFork)
  func hotlineFileDownloadComplete(client: HotlineFileDownloadClient, reference: UInt32, at: URL)
}

protocol HotlineFilePreviewClientDelegate: HotlineTransferDelegate {
  func hotlineFilePreviewComplete(client: HotlineFilePreviewClient, reference: UInt32, data: Data)
}

protocol HotlineFileUploadClientDelegate: HotlineTransferDelegate {
  func hotlineFileUploadComplete(client: HotlineFileUploadClient, reference: UInt32)
}

protocol HotlineFolderDownloadClientDelegate: HotlineTransferDelegate {
  func hotlineFolderDownloadReceivedFileInfo(client: HotlineFolderDownloadClient, reference: UInt32, fileName: String, itemNumber: Int, totalItems: Int)
  func hotlineFolderDownloadComplete(client: HotlineFolderDownloadClient, reference: UInt32, at: URL)
}

enum HotlineFileTransferStage: Int {
  case fileHeader = 1
  case fileForkHeader = 2
  case fileInfoFork = 3
  case fileDataFork = 4
  case fileResourceFork = 5
  case fileUnsupportedFork = 6
}

enum HotlineFileUploadStage: Int {
  case magic = 1
  case fileHeader = 2
  case fileInfoForkHeader = 3
  case fileInfoFork = 4
  case fileDataForkHeader = 5
  case fileDataFork = 6
  case fileResourceForkHeader = 7
  case fileResourceFork = 8
  case fileComplete = 9
}

enum HotlineFolderDownloadStage: Int {
  case itemHeader = 0          // Read 2-byte length + item header
  case waitingForFileSize = 1  // Read 4-byte file size before FILP
  case fileHeader = 2
  case fileForkHeader = 3
  case fileInfoFork = 4
  case fileDataFork = 5
  case fileResourceFork = 6
  case fileUnsupportedFork = 7
}

private enum HotlineFolderAction: UInt16 {
  case sendFile = 1
  case resumeFile = 2
  case nextFile = 3
}

protocol HotlineTransferClient {
  var serverAddress: NWEndpoint.Host { get }
  var serverPort: NWEndpoint.Port { get }
  var referenceNumber: UInt32 { get }
  var status: HotlineTransferStatus { get set }
  
  func start()
  func cancel()
}

// MARK: -

class HotlineFileUploadClient: HotlineTransferClient {
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port
  let referenceNumber: UInt32
  
  weak var delegate: HotlineFileUploadClientDelegate? = nil
  
  private var connection: NWConnection?
  private var stage: HotlineFileUploadStage = .magic
  private var payloadSize: UInt32 = 0
  private let fileURL: URL
  private let fileResourceURL: URL?
  private var fileHandle: FileHandle? = nil
  private var bytesSent: Int = 0
  private let infoForkData: Data
  private let dataForkSize: UInt32
  private let resourceForkSize: UInt32
  
  var status: HotlineTransferStatus = .unconnected {
    didSet {
      DispatchQueue.main.async {
        self.delegate?.hotlineTransferStatusChanged(client: self, reference: self.referenceNumber, status: self.status, timeRemaining: 0.0)
      }
    }
  }
  
  init?(upload fileURL: URL, address: String, port: UInt16, reference: UInt32) {
    guard let payloadSize = FileManager.default.getFlattenedFileSize(fileURL) else {
      return nil
    }
    
    guard let infoFork = HotlineFileInfoFork(file: fileURL) else {
      return nil
    }
    
    guard let forkSizes = try? FileManager.default.getFileForkSizes(fileURL) else {
      return nil
    }
    
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.stage = .magic
    self.payloadSize = UInt32(payloadSize)
    self.fileURL = fileURL
    self.infoForkData = infoFork.data()
    self.dataForkSize = forkSizes.dataForkSize
    self.resourceForkSize = forkSizes.resourceForkSize
    if forkSizes.resourceForkSize > 0 {
      self.fileResourceURL = fileURL.urlForResourceFork()
    }
    else {
      self.fileResourceURL = nil
    }
  }
  
  deinit {
    self.invalidate()
  }
  
  func start() {
    guard self.status == .unconnected else {
      return
    }
    
    let _ = self.fileURL.startAccessingSecurityScopedResource()
    let _ = self.fileResourceURL?.stopAccessingSecurityScopedResource()
    
    self.bytesSent = 0
    self.connect()
  }
  
  func cancel() {
    self.delegate = nil
    
    if self.status == .unconnected {
      return
    }
    
    self.invalidate()
    
    print("HotlineFileUploadClient: Cancelled upload")
  }
  
  private func connect() {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        self?.status = .connected
        self?.stage = .magic
        self?.send()
      case .waiting(let err):
        print("HotlineFileClient: Waiting", err)
      case .cancelled:
        print("HotlineFileClient: Cancelled")
        self?.invalidate()
      case .failed(let err):
        print("HotlineFileClient: Connection error \(err)")
        switch self?.status {
        case .connecting:
          print("HotlineFileClient: Failed to connect to file transfer server.")
          self?.invalidate()
          self?.status = .failed(.failedToConnect)
        case .connected, .progress(_):
          print("HotlineFileClient: Failed to finish transfer.")
          self?.invalidate()
          self?.status = .failed(.failedToUpload)
        case .completing:
          print("HotlineFileClient: Completed.")
          self?.invalidate()
          self?.status = .completed
          DispatchQueue.main.async { [weak self] in
            if let s = self {
              s.delegate?.hotlineFileUploadComplete(client: s, reference: s.referenceNumber)
            }
          }
        case .completed:
          self?.invalidate()
        default:
          break
        }
      default:
        return
      }
    }
    
    self.status = .connecting
    self.connection?.start(queue: .global())
  }
  
  private func invalidate() {
    if let c = self.connection {
      c.stateUpdateHandler = nil
      c.cancel()
      
      self.connection = nil
    }
    
    self.stage = .magic
    
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    self.fileURL.stopAccessingSecurityScopedResource()
    self.fileResourceURL?.stopAccessingSecurityScopedResource()
  }
  
  private func sendComplete() {
    guard let c = self.connection else {
      self.invalidate()
      print("HotlineFileUploadClient: invalid connection to send data.")
      return
    }
    
    self.status = .completing
    
    c.send(content: nil, contentContext: .finalMessage, completion: .contentProcessed({ error in
    }))
  }
  
  private func sendFileData(_ data: Data) {
    guard let c = self.connection else {
      self.invalidate()
      
      print("HotlineFileUploadClient: invalid connection to send data.")
      return
    }
    
    let dataSent: Int = data.count
    c.send(content: data, completion: .contentProcessed({ [weak self] error in
      guard let client = self,
            error == nil else {
        self?.status = .failed(.failedToConnect)
        self?.invalidate()
        return
      }
      
      
      client.bytesSent += dataSent
      client.status = .progress(Double(client.bytesSent) / Double(client.payloadSize))
      
      client.send()
    }))
  }
  
  private func send() {
    guard let _ = self.connection else {
      self.invalidate()
      print("HotlineFileUploadClient: Invalid connection to send.")
      return
    }
    
    switch self.stage {
    case .magic:
      print("Upload: Starting upload for \(self.fileURL)")
      print("Upload: Sending magic")
      self.status = .progress(0.0)
      
      let magicData = Data(endian: .big) {
        "HTXF".fourCharCode()
        self.referenceNumber
        self.payloadSize
        UInt32.zero
      }
      //      var magicData = Data()
      //      magicData.appendUInt32("HTXF".fourCharCode())
      //      magicData.appendUInt32(self.referenceNumber)
      //      magicData.appendUInt32(self.payloadSize)
      //      magicData.appendUInt32(0)
      self.stage = .fileHeader
      self.sendFileData(magicData)
      
    case .fileHeader:
      print("Upload: Sending file header")
      if let header = HotlineFileHeader(file: self.fileURL) {
        self.stage = .fileInfoForkHeader
        self.sendFileData(header.data())
      }
      
    case .fileInfoForkHeader:
      print("Upload: Sending info fork header")
      let header = HotlineFileForkHeader(type: HotlineFileForkType.info.rawValue, dataSize: UInt32(self.infoForkData.count))
      self.stage = .fileInfoFork
      self.sendFileData(header.data())
      
    case .fileInfoFork:
      print("Upload: Sending info fork")
      self.stage = .fileDataForkHeader
      self.sendFileData(self.infoForkData)
      
    case .fileDataForkHeader:
      guard self.dataForkSize > 0 else {
        print("Upload: Data fork empty, skipping to resource fork")
        self.stage = .fileResourceForkHeader
        fallthrough
      }
      
      do {
        let fh = try FileHandle(forReadingFrom: self.fileURL)
        self.fileHandle = fh
        self.stage = .fileDataFork
        
        let header = HotlineFileForkHeader(type: HotlineFileForkType.data.rawValue, dataSize: self.dataForkSize)
        
        print("Upload: Sending data fork header \(self.dataForkSize)")
        self.sendFileData(header.data())
      }
      catch {
        print("Upload: Error opening data fork", error)
        self.invalidate()
        return
      }
      
    case .fileDataFork:
      guard self.dataForkSize > 0,
            let fh = self.fileHandle else {
        print("Upload: Data fork empty, skipping to resource fork")
        self.stage = .fileResourceForkHeader
        try? self.fileHandle?.close()
        self.fileHandle = nil
        fallthrough
      }
      
      do {
        let fileData = try fh.read(upToCount: 4 * 1024)
        if fileData == nil || fileData?.isEmpty == true {
          print("Upload: Finished data fork")
          self.stage = .fileResourceForkHeader
          try? fh.close()
          self.fileHandle = nil
          fallthrough
        }
        
        print("Upload: Sending data Fork \(String(describing: fileData?.count))")
        self.sendFileData(fileData!)
      }
      catch {
        self.invalidate()
        print("Upload: Error reading data fork", error)
        return
      }
      
    case .fileResourceForkHeader:
      guard self.resourceForkSize > 0,
            let resourceURL = self.fileResourceURL else {
        print("Upload: Skipping resource fork header")
        self.stage = .fileComplete
        fallthrough
      }
      
      print("Upload: Sending resource fork header")
      guard let fh = try? FileHandle(forReadingFrom: resourceURL) else {
        print("Upload: Error reading resource fork")
        self.invalidate()
        return
      }
      
      let header = HotlineFileForkHeader(type: HotlineFileForkType.resource.rawValue, dataSize: self.resourceForkSize)
      
      self.fileHandle = fh
      self.stage = .fileResourceFork
      self.sendFileData(header.data())
      
    case .fileResourceFork:
      guard self.resourceForkSize > 0,
            let fh = self.fileHandle else {
        print("Upload: Resource fork empty, skipping to completion")
        self.stage = .fileComplete
        try? self.fileHandle?.close()
        self.fileHandle = nil
        fallthrough
      }
      
      do {
        let resourceData = try fh.read(upToCount: 4 * 1024)
        if resourceData == nil || resourceData?.isEmpty == true {
          print("Upload: Finished resource fork")
          self.stage = .fileComplete
          try? self.fileHandle?.close()
          self.fileHandle = nil
          fallthrough
        }
        
        print("Upload: Sending resource fork \(String(describing: resourceData?.count))")
        self.sendFileData(resourceData!)
      }
      catch {
        self.invalidate()
        print("Upload: Error reading resource fork", error)
        return
      }
      break
      
    case .fileComplete:
      print("Upload: Complete!")
      self.sendComplete()
    }
  }
}

// MARK: -

class HotlineFilePreviewClient: HotlineTransferClient {
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port
  let referenceNumber: UInt32
  let referenceDataSize: UInt32

  weak var delegate: HotlineFilePreviewClientDelegate? = nil

  var status: HotlineTransferStatus = .unconnected {
    didSet {
      DispatchQueue.main.async {
        self.delegate?.hotlineTransferStatusChanged(client: self, reference: self.referenceNumber, status: self.status, timeRemaining: 0.0)
      }
    }
  }

  private var downloadTask: Task<Void, Never>?

  init(address: String, port: UInt16, reference: UInt32, size: UInt32) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.referenceDataSize = size
  }

  deinit {
    downloadTask?.cancel()
  }

  func start() {
    guard status == .unconnected else {
      return
    }

    downloadTask = Task {
      await self.download()
    }
  }

  func cancel() {
    downloadTask?.cancel()
    downloadTask = nil
    delegate = nil

    print("HotlineFilePreviewClient: Cancelled preview transfer")
  }

  private func download() async {
    status = .connecting

    do {
      // Connect to file transfer server (already includes +1 in serverPort from init)
      let socket = try await NetSocketNew.connect(
        host: serverAddress,
        port: serverPort,
        tls: .disabled
      )
      defer { Task { await socket.close() } }

      status = .connected

      // Send magic header
      let headerData = Data(endian: .big) {
        "HTXF".fourCharCode()
        self.referenceNumber
        UInt32.zero
        UInt32.zero
      }
      try await socket.write(headerData)

      status = .progress(0.0)

      // Download file data with progress updates
      let fileData = try await socket.read(Int(referenceDataSize)) { current, total in
        self.status = .progress(Double(current) / Double(total))
      }

      print("HotlineFilePreviewClient: Complete")
      status = .completed

      // Notify delegate on main thread
      let reference = self.referenceNumber
      await MainActor.run {
        self.delegate?.hotlineFilePreviewComplete(client: self, reference: reference, data: fileData)
      }

    } catch is CancellationError {
      // Already handled in cancel()
      return
    } catch {
      print("HotlineFilePreviewClient: Download failed: \(error)")

      if status == .connecting {
        status = .failed(.failedToConnect)
      } else {
        status = .failed(.failedToDownload)
      }
    }
  }
}

// MARK: -

class HotlineFileDownloadClient: HotlineTransferClient {
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port
  let referenceNumber: UInt32
  
  private var connection: NWConnection?
  private var transferStage: HotlineFileTransferStage = .fileHeader
  
  weak var delegate: HotlineFileDownloadClientDelegate? = nil
  
  var status: HotlineTransferStatus = .unconnected {
    didSet {
      DispatchQueue.main.async {
        self.delegate?.hotlineTransferStatusChanged(client: self, reference: self.referenceNumber, status: self.status, timeRemaining: 0.0)
      }
    }
  }
  
  private let referenceDataSize: UInt32
  private var fileBytes = Data()
  private var fileResourceBytes = Data()
  
  private var fileHeader: HotlineFileHeader? = nil
  private var fileCurrentForkHeader: HotlineFileForkHeader? = nil
  private var fileCurrentForkBytesLeft: Int = 0
  private var fileInfoFork: HotlineFileInfoFork? = nil
  private var fileHandle: FileHandle? = nil
  private var filePath: String? = nil
  private var fileBytesTransferred: Int = 0
  private var fileProgress: Progress
  
  init(address: String, port: UInt16, reference: UInt32, size: UInt32) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.referenceDataSize = size
    self.transferStage = .fileHeader
    self.fileProgress = Progress(totalUnitCount: Int64(size))
  }
  
  deinit {
    self.invalidate()
  }
  
  func start() {
    guard self.status == .unconnected else {
      return
    }
    
    self.filePath = nil
    self.connect()
  }
  
  func start(to fileURL: URL) {
    guard self.status == .unconnected else {
      return
    }
    
    self.filePath = fileURL.path
    self.connect()
  }
  
  func cancel() {
    self.delegate = nil
    
    if self.status == .unconnected {
      return
    }
    
    // Close file before we try to potentionally delete it.
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    if let downloadPath = self.filePath {
      print("HotlineFileClient: Deleting file fragment at", downloadPath)
      if FileManager.default.isDeletableFile(atPath: downloadPath) {
        try? FileManager.default.removeItem(atPath: downloadPath)
      }
      self.filePath = nil
    }
    
    self.invalidate()
    
    print("HotlineFileClient: Cancelled transfer")
  }
  
  private func connect() {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        self?.status = .connected
        self?.sendMagic()
      case .waiting(let err):
        print("HotlineFileClient: Waiting", err)
      case .cancelled:
        print("HotlineFileClient: Cancelled")
        self?.invalidate()
      case .failed(let err):
        print("HotlineFileClient: Connection error \(err)")
        switch self?.status {
        case .connecting:
          print("HotlineFileClient: Failed to connect to file transfer server.")
          self?.invalidate()
          self?.status = .failed(.failedToConnect)
        case .connected, .progress(_):
          print("HotlineFileClient: Failed to finish transfer.")
          self?.invalidate()
          self?.status = .failed(.failedToDownload)
        default:
          break
        }
      default:
        return
      }
    }
    
    self.status = .connecting
    self.connection?.start(queue: .global())
  }
  
  func invalidate() {
    if let c = self.connection {
      c.stateUpdateHandler = nil
      c.cancel()
      
      self.connection = nil
    }
    
    self.fileBytes = Data()
    
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    self.fileProgress.unpublish()
  }
  
  private func sendMagic() {
    guard let c = connection, self.status == .connected else {
      self.invalidate()
      print("HotlineFileClient: invalid connection to send header.")
      return
    }
    
    let headerData = Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero
      UInt32.zero
    }
    
    c.send(content: headerData, completion: .contentProcessed { [weak self] (error) in
      guard let self = self else {
        return
      }
      
      guard error == nil else {
        self.status = .failed(.failedToConnect)
        self.invalidate()
        return
      }
      
      self.status = .progress(0.0)
      self.receiveFile()
    })
  }
  
  private func receiveFile() {
    guard let c = self.connection else {
      return
    }
    
    c.receive(minimumIncompleteLength: 1, maximumLength: Int(UInt16.max)) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      guard error == nil else {
        self.status = .failed(.failedToDownload)
        self.invalidate()
        return
      }
      
      if let newData = data, !newData.isEmpty {
        self.fileBytesTransferred += newData.count
        self.fileBytes.append(newData)
        self.fileProgress.completedUnitCount = Int64(self.fileBytesTransferred)
        self.status = .progress(Double(self.fileBytesTransferred) / Double(self.referenceDataSize))
      }
      
      // See if we need header data still.
      var keepProcessing = false
      repeat {
        keepProcessing = false
        
        switch self.transferStage {
        case .fileHeader:
          if let header = HotlineFileHeader(from: self.fileBytes) {
            self.fileBytes.removeSubrange(0..<HotlineFileHeader.DataSize)
            self.fileHeader = header
            self.transferStage = .fileForkHeader
            keepProcessing = true
          }
        case .fileForkHeader:
          if let forkHeader = HotlineFileForkHeader(from: self.fileBytes) {
            //            let fileForkHeader = HotlineFileForkHeader(from: self.fileBytes)
            self.fileBytes.removeSubrange(0..<HotlineFileForkHeader.DataSize)
            self.fileCurrentForkHeader = forkHeader
            self.fileCurrentForkBytesLeft = Int(forkHeader.dataSize)
            
            if forkHeader.isInfoFork {
              print("HotlineFileClient: Downloading info fork")
              self.transferStage = .fileInfoFork
            }
            else if forkHeader.isDataFork {
              print("HotlineFileClient: Downloading data fork")
              self.transferStage = .fileDataFork
            }
            else if forkHeader.isResourceFork {
              print("HotlineFileClient: Downloading resource fork")
              self.fileResourceBytes = Data()
              self.transferStage = .fileResourceFork
            }
            else {
              print("HotlineFileClient: Downloading unsupported fork")
              self.transferStage = .fileUnsupportedFork
            }
            
            keepProcessing = true
          }
        case .fileInfoFork:
          if let infoForkDataSize = self.fileCurrentForkHeader?.dataSize, self.fileBytes.count >= infoForkDataSize {
            let infoForkData = self.fileBytes.subdata(in: 0..<Int(infoForkDataSize))
            if let infoFork = HotlineFileInfoFork(from: infoForkData) {
              self.fileInfoFork = infoFork
              
              self.fileBytes.removeSubrange(0..<infoFork.headerSize)
              
              self.transferStage = .fileForkHeader
              self.fileCurrentForkBytesLeft -= Int(infoForkDataSize)
              self.fileCurrentForkHeader = nil
              
              print("INFO FORK STUFF:", infoFork)
              
              // Create file in Downloads folder if we don't have a destination already.
              if !self.prepareDownloadFile(name: infoFork.name) {
                print("FAILED TO CREATE FILE ON DISK")
              }
              
              let reference = self.referenceNumber
              DispatchQueue.main.async {
                self.delegate?.hotlineFileDownloadReceivedInfo(client: self, reference: reference, info: infoFork)
              }
            }
            
            keepProcessing = true
          }
        case .fileDataFork:
          if self.fileBytes.count > 0 {
            if let f = self.fileHandle {
              do {
                var dataToWrite = self.fileBytes
                
                if dataToWrite.count >= self.fileCurrentForkBytesLeft {
                  dataToWrite = self.fileBytes.subdata(in: 0..<self.fileCurrentForkBytesLeft)
                  self.fileBytes.removeSubrange(0..<self.fileCurrentForkBytesLeft)
                  
                  self.transferStage = .fileForkHeader
                  self.fileCurrentForkBytesLeft = 0
                  self.fileCurrentForkHeader = nil
                  
                  keepProcessing = true
                }
                else {
                  self.fileCurrentForkBytesLeft -= dataToWrite.count
                  self.fileBytes = Data()
                }
                
                try f.write(contentsOf: dataToWrite)
              }
              catch {
                print("DOWNLOAD WRITE ERROR", error)
              }
            }
          }
        case .fileResourceFork:
          if self.fileBytes.count > 0 {
            var dataToWrite = self.fileBytes
            
            if dataToWrite.count >= self.fileCurrentForkBytesLeft {
              dataToWrite = self.fileBytes.subdata(in: 0..<self.fileCurrentForkBytesLeft)
              self.fileBytes.removeSubrange(0..<self.fileCurrentForkBytesLeft)
              
              self.transferStage = .fileForkHeader
              self.fileCurrentForkBytesLeft = 0
              self.fileCurrentForkHeader = nil
              
              keepProcessing = true
            }
            else {
              self.fileCurrentForkBytesLeft -= dataToWrite.count
              self.fileBytes = Data()
            }
            
            print("WRITING TO RESOURCE FORK", dataToWrite.count)
            
            self.fileResourceBytes.append(dataToWrite)
          }
        case .fileUnsupportedFork:
          if self.fileBytes.count > 0 {
            var dataToWrite = self.fileBytes
            
            if dataToWrite.count >= self.fileCurrentForkBytesLeft {
              dataToWrite = self.fileBytes.subdata(in: 0..<self.fileCurrentForkBytesLeft)
              self.fileBytes.removeSubrange(0..<self.fileCurrentForkBytesLeft)
              
              self.transferStage = .fileForkHeader
              self.fileCurrentForkBytesLeft = 0
              self.fileCurrentForkHeader = nil
              
              keepProcessing = true
            }
            else {
              self.fileCurrentForkBytesLeft -= dataToWrite.count
              self.fileBytes = Data()
            }
          }
        }
      } while keepProcessing
      
      if self.fileBytesTransferred < Int(self.referenceDataSize) {
        // If we still have more to download, then receive more data.
        self.receiveFile()
        return
      }
      else {
        self.invalidate()
        
        if self.fileResourceBytes.count > 0 {
          let _ = self.writeResourceFork()
          self.fileResourceBytes = Data()
        }
        
        self.status = .completed
        
        if let downloadPath = self.filePath {
          DispatchQueue.main.sync {
            print("POSTING DOWNLOAD FILE FINISHED", downloadPath)
            
            var downloadURL = URL(filePath: downloadPath)
            downloadURL.resolveSymlinksInPath()
            print("FINAL PATH", downloadURL.path)
            
            self.delegate?.hotlineFileDownloadComplete(client: self, reference: self.referenceNumber, at: downloadURL)
            
#if os(macOS)
            // Bounce dock icon when download completes. Weird this is the only API to do so.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: downloadURL.path)
#endif
          }
        }
      }
    }
  }
  
  private func writeResourceFork() -> Bool {
    guard let filePath = self.filePath else {
      return false
    }
    
    var resolvedFileURL = URL(filePath: filePath)
    resolvedFileURL.resolveSymlinksInPath()
    
    let resourceFilePath = resolvedFileURL.appendingPathComponent("..namedfork/rsrc")
    
    do {
      try self.fileResourceBytes.write(to: resourceFilePath)
    }
    catch {
      return false
    }
    
    return true
  }
  
  private func prepareDownloadFile(name: String) -> Bool {
    var filePath: String
    
    if self.filePath != nil {
      filePath = self.filePath!
    }
    else {
      let folderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
      filePath = folderURL.generateUniqueFilePath(filename: name)
    }
    
    var fileAttributes: [FileAttributeKey: Any] = [:]
    if let creatorCode = self.fileInfoFork?.creator {
      fileAttributes[.hfsCreatorCode] = creatorCode as NSNumber
    }
    if let typeCode = self.fileInfoFork?.type {
      fileAttributes[.hfsTypeCode] = typeCode as NSNumber
    }
    if let createdDate = self.fileInfoFork?.createdDate {
      fileAttributes[.creationDate] = createdDate as NSDate
    }
    if let modifiedDate = self.fileInfoFork?.modifiedDate {
      fileAttributes[.modificationDate] = modifiedDate as NSDate
    }
    if let comment = self.fileInfoFork?.comment {
      if let commentPlistData = try? PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0) {
        fileAttributes[FileAttributeKey(rawValue: "NSFileExtendedAttributes")] = [
          FileAttributeKey(rawValue: "com.apple.metadata:kMDItemFinderComment"): commentPlistData
        ]
      }
    }
    
    if FileManager.default.createFile(atPath: filePath, contents: nil, attributes: fileAttributes) {
      if let h = FileHandle(forWritingAtPath: filePath) {
        self.filePath = filePath
        self.fileHandle = h
        self.fileProgress.fileURL = URL(filePath: filePath).resolvingSymlinksInPath()
        self.fileProgress.fileOperationKind = .downloading
        self.fileProgress.publish()
        return true
      }
    }
    
    return false
  }
}

// MARK: -

struct HotlineFileHeader {
  static let DataSize: Int = 4 + 2 + 16 + 2
  
  let format: UInt32
  let version: UInt16
  let forkCount: UInt16
  
  init?(from data: Data) {
    guard data.count >= HotlineFileHeader.DataSize else {
      return nil
    }
    
    self.format = data.readUInt32(at: 0)!
    self.version = data.readUInt16(at: 4)!
    // 16 bytes of reserved data sits here. Skip it.
    self.forkCount = data.readUInt16(at: 4 + 2 + 16)!
  }
  
  init?(file fileURL: URL) {
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
      return nil
    }
    
    self.format = "FILP".fourCharCode()
    self.version = 1
    
    let resourceURL = fileURL.appendingPathComponent("..namedfork/rsrc")
    if FileManager.default.fileExists(atPath: resourceURL.path(percentEncoded: false)) {
      self.forkCount = 3
    }
    else {
      self.forkCount = 2
    }
  }
  
  func data() -> Data {
    Data(endian: .big) {
      self.format
      self.version
      Data(repeating: 0, count: 16)
      self.forkCount
    }
  }
}

// MARK: -

struct HotlineFileForkHeader {
  static let DataSize: Int = 4 + 4 + 4 + 4
  
  let forkType: UInt32
  let compressionType: UInt32
  let dataSize: UInt32
  
  init(type: UInt32, dataSize: UInt32) {
    self.forkType = type
    self.compressionType = 0
    self.dataSize = dataSize
  }
  
  init?(from data: Data) {
    guard data.count >= HotlineFileForkHeader.DataSize else {
      return nil
    }
    
    self.forkType = data.readUInt32(at: 0)!
    self.compressionType = data.readUInt32(at: 4)!
    // 4 bytes of reserved data sits here. Skip it.
    // self.reserved = data.readUInt32(at: 4 + 4)!
    self.dataSize = data.readUInt32(at: 4 + 4 + 4)!
  }
  
  func data() -> Data {
    Data(endian: .big) {
      self.forkType
      self.compressionType
      UInt32.zero
      self.dataSize
    }
  }
  
  var isInfoFork: Bool {
    return self.forkType == HotlineFileForkType.info.rawValue
  }
  
  var isDataFork: Bool {
    return self.forkType == HotlineFileForkType.data.rawValue
  }
  
  var isResourceFork: Bool {
    return self.forkType == HotlineFileForkType.resource.rawValue
  }
}

// MARK: -

struct HotlineFileInfoFork {
  static let BaseDataSize: Int = 4 + 4 + 4 + 4 + 4 + 32 + 8 + 8 + 2 + 2
  
  let platform: UInt32
  let type: UInt32
  let creator: UInt32
  let flags: UInt32
  let platformFlags: UInt32
  let createdDate: Date
  let modifiedDate: Date
  let nameScript: UInt16
  let name: String
  let comment: String?
  var headerSize: Int
  
  init?(file fileURL: URL) {
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
      return nil
    }
    
    self.platform = "AMAC".fourCharCode()
    
    if let hfsInfo = try? FileManager.default.getHFSTypeAndCreator(fileURL) {
      self.type = hfsInfo.hfsType
      self.creator = hfsInfo.hfsCreator
    }
    else {
      self.type = 0
      self.creator = 0
    }
    
    self.flags = 0
    self.platformFlags = 0
    
    let dateInfo = FileManager.default.getCreatedAndModifiedDates(fileURL)
    self.createdDate = dateInfo.createdDate
    self.modifiedDate = dateInfo.modifiedDate
    
    self.nameScript = 0
    self.name = fileURL.lastPathComponent
    
    let fileComment = try? FileManager.default.getFinderComment(fileURL)
    self.comment = fileComment ?? ""
    
    self.headerSize = 0
  }
  
  init?(from data: Data) {
    // Make sure we have at least enough data to read basic header data
    guard data.count >= HotlineFileInfoFork.BaseDataSize else {
      return nil
    }
    
    if
      let platform = data.readUInt32(at: 0),
      let type = data.readUInt32(at: 4),
      let creator = data.readUInt32(at: 4 + 4),
      let flags = data.readUInt32(at: 4 + 4 + 4),
      let platformFlags = data.readUInt32(at: 4 + 4 + 4 + 4),
      // 32 bytes of reserved data sits here. Skip it.
      let nameScript = data.readUInt16(at: 4 + 4 + 4 + 4 + 4 + 32 + 8 + 8) {
      
      let createdDate = data.readDate(at: 4 + 4 + 4 + 4 + 4 + 32) ?? Date.now
      let modifiedDate = data.readDate(at: 4 + 4 + 4 + 4 + 4 + 32 + 8) ?? Date.now
      
      let (n, nl) = data.readLongPString(at: 4 + 4 + 4 + 4 + 4 + 32 + 8 + 8 + 2)
      if let name = n {
        self.platform = platform
        self.type = type
        self.creator = creator
        self.flags = flags
        self.platformFlags = platformFlags
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.nameScript = nameScript
        self.name = name
        
        var calculatedHeaderSize: Int = HotlineFileInfoFork.BaseDataSize + nl
        var commentRead: String? = nil
        if data.count >= HotlineFileInfoFork.BaseDataSize + nl + 2 {
          let commentLength = data.readUInt16(at: HotlineFileInfoFork.BaseDataSize + nl)!
          var commentCorrupted = false
          
          // Some servers have incorrect data length for the INFO fork
          // the length they send is what it should be but don't include
          // the comment length in the actual data, so we end up with mismatched
          // lengths. So here we test if the length we read is actually 'DA'
          // or the first part of the "DATA" fork header.
          // Needless to say, stuff like this makes for sad code but this ain't so bad.
          if commentLength == 0x4441 {
            commentCorrupted = true
          }
          
          if !commentCorrupted {
            let (c, cl) = data.readLongPString(at: HotlineFileInfoFork.BaseDataSize + nl)
            calculatedHeaderSize += 2
            if cl > 0 {
              calculatedHeaderSize += Int(cl)
              if let ct = c, cl > 0 {
                commentRead = ct
              }
            }
          }
        }
        
        self.comment = commentRead
        self.headerSize = calculatedHeaderSize
        return
      }
    }
    
    return nil
  }
  
  func data() -> Data {
    let fileName = self.name.data(using: .macOSRoman)!
    
    let data = Data(endian: .big) {
      self.platform
      self.type
      self.creator
      self.flags
      self.platformFlags
      Data(repeating: 0, count: 32)
      self.createdDate
      self.modifiedDate
      self.nameScript
      UInt16(fileName.count)
      fileName
      if let commentData = self.comment?.data(using: .macOSRoman) {
        UInt16(commentData.count)
        commentData
      }
    }
    
    return data
  }
}

// MARK: -

class HotlineFolderDownloadClient: HotlineTransferClient {
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port
  let referenceNumber: UInt32
  
  private var connection: NWConnection?
  private var transferStage: HotlineFolderDownloadStage = .fileHeader
  
  weak var delegate: HotlineFolderDownloadClientDelegate? = nil
  
  var status: HotlineTransferStatus = .unconnected {
    didSet {
      DispatchQueue.main.async {
        self.delegate?.hotlineTransferStatusChanged(client: self, reference: self.referenceNumber, status: self.status, timeRemaining: 0.0)
      }
    }
  }
  
  private let referenceDataSize: UInt32
  private let folderItemCount: Int
  private var fileBytes = Data()
  private var fileResourceBytes = Data()
  
  private var fileHeader: HotlineFileHeader? = nil
  private var fileCurrentForkHeader: HotlineFileForkHeader? = nil
  private var fileCurrentForkBytesLeft: Int = 0
  private var fileForksRemaining: Int = 0
  private var currentFileSize: UInt32 = 0        // Size of current file from server
  private var currentFileBytesRead: Int = 0     // Bytes read for current file
  private var fileInfoFork: HotlineFileInfoFork? = nil
  private var fileHandle: FileHandle? = nil
  private var currentFilePath: String? = nil
  private var fileBytesTransferred: Int = 0
  private var fileProgress: Progress
  
  private var currentItemNumber: Int = 0
  private var completedItemCount: Int = 0  // Track actually completed files
  private var folderPath: String? = nil
  private var currentItemRelativePath: [String] = []
  private var currentFileName: String? = nil
  
  private let FILP_MAGIC: UInt32 = "FILP".fourCharCode()
  
  init(address: String, port: UInt16, reference: UInt32, size: UInt32, itemCount: Int) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.referenceDataSize = size
    self.folderItemCount = itemCount
    self.transferStage = .fileHeader
    self.fileProgress = Progress(totalUnitCount: Int64(size))
  }
  
  deinit {
    self.invalidate()
  }
  
  func start() {
    guard self.status == .unconnected else {
      return
    }
    
    self.folderPath = nil
    self.connect()
  }
  
  func start(to folderURL: URL) {
    print("HotlineFolderDownloadClient: start(to:) called with path: \(folderURL.path)")
    guard self.status == .unconnected else {
      print("HotlineFolderDownloadClient: Already connected, status: \(self.status)")
      return
    }
    
    self.folderPath = folderURL.path
    print("HotlineFolderDownloadClient: Calling connect()")
    self.connect()
  }
  
  func cancel() {
    self.delegate = nil
    
    if self.status == .unconnected {
      return
    }
    
    // Close file before we try to potentially delete it.
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    if let downloadPath = self.folderPath {
      print("HotlineFolderDownloadClient: Deleting folder fragment at", downloadPath)
      if FileManager.default.isDeletableFile(atPath: downloadPath) {
        try? FileManager.default.removeItem(atPath: downloadPath)
      }
      self.folderPath = nil
    }
    
    self.invalidate()
    
    print("HotlineFolderDownloadClient: Cancelled transfer")
  }
  
  private func connect() {
    print("HotlineFolderDownloadClient: connect() called, connecting to \(self.serverAddress):\(self.serverPort)")
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    print("HotlineFolderDownloadClient: NWConnection created")
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        print("HotlineFolderDownloadClient: Connection ready!")
        self?.status = .connected
        self?.sendMagic()
      case .waiting(let err):
        print("HotlineFolderDownloadClient: Waiting", err)
      case .cancelled:
        print("HotlineFolderDownloadClient: Cancelled")
        self?.invalidate()
      case .failed(let err):
        print("HotlineFolderDownloadClient: Connection error \(err)")
        switch self?.status {
        case .connecting:
          print("HotlineFolderDownloadClient: Failed to connect to file transfer server.")
          self?.invalidate()
          self?.status = .failed(.failedToConnect)
        case .connected, .progress(_):
          print("HotlineFolderDownloadClient: Failed to finish transfer.")
          self?.invalidate()
          self?.status = .failed(.failedToDownload)
        default:
          break
        }
      default:
        return
      }
    }
    
    self.status = .connecting
    self.connection?.start(queue: .global())
  }
  
  func invalidate() {
    if let c = self.connection {
      c.stateUpdateHandler = nil
      c.cancel()
      
      self.connection = nil
    }
    
    self.fileBytes = Data()
    
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    self.fileProgress.unpublish()
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
  
  /// Find and align the buffer to the start of a FILP header.
  /// Returns the number of bytes dropped.
  @discardableResult
  private func alignBufferToFILP() -> Int {
    // We need at least the 4-byte magic to try
    guard self.fileBytes.count >= 4 else { return 0 }
    let magicData = Data([0x46, 0x49, 0x4C, 0x50]) // "FILP"
    if self.fileBytes.starts(with: magicData) { return 0 }
    
    if let r = self.fileBytes.firstRange(of: magicData) {
      let toDrop = r.lowerBound
      if toDrop > 0 {
        print("HotlineFolderDownloadClient: Resync — dropping \(toDrop) stray bytes before FILP")
        self.fileBytes.removeSubrange(0..<toDrop)
      }
      return toDrop
    }
    
    // If we can't find FILP yet, wait for more data.
    return 0
  }
  
  private func sendMagic() {
    print("HotlineFolderDownloadClient: sendMagic() called")
    guard let c = connection, self.status == .connected else {
      self.invalidate()
      print("HotlineFolderDownloadClient: invalid connection to send header.")
      return
    }
    
    // Folder transfer initial record: HTXF + ref + dataSize(0) + type(1) + rsvd(0) + action(NextFile)
    // Classic clients send a zero data size and append the action immediately after the header.
    let headerData = Data(endian: .big) {
      "HTXF".fourCharCode()
      self.referenceNumber
      UInt32.zero           // data size = 0 (action appended implicitly)
      UInt16(1)             // type = 1 (folder transfer)
      UInt16.zero           // reserved = 0
      UInt16(HotlineFolderAction.nextFile.rawValue)  // action = 3 (next file)
    }
    
    print("HotlineFolderDownloadClient: Sending HTXF magic with reference: \(self.referenceNumber)")
    
    c.send(content: headerData, completion: .contentProcessed { [weak self] (error) in
      guard let self = self else {
        print("HotlineFolderDownloadClient: self is nil in sendMagic completion")
        return
      }
      
      guard error == nil else {
        print("HotlineFolderDownloadClient: Error sending magic: \(error!)")
        self.status = .failed(.failedToConnect)
        self.invalidate()
        return
      }
      
      print("HotlineFolderDownloadClient: Magic sent successfully, expecting item header")
      self.status = .progress(0.0)
      self.currentItemNumber = 0
      self.transferStage = .itemHeader
      self.receiveFolder()
    })
  }
  
  private func sendAction(_ action: HotlineFolderAction, resumeData: Data? = nil) {
    guard let c = connection else {
      self.invalidate()
      print("HotlineFolderDownloadClient: invalid connection to send action.")
      return
    }
    
    var actionData = Data(endian: .big) {
      UInt16(action.rawValue)
    }
    
    if let resume = resumeData, !resume.isEmpty {
      actionData.append(Data(endian: .big) { UInt16(resume.count) })
      actionData.append(resume)
    }
    
    print("HotlineFolderDownloadClient: Sending action: \(action)")
    
    c.send(content: actionData, completion: .contentProcessed { [weak self] (error) in
      guard let self = self else {
        return
      }
      
      guard error == nil else {
        print("HotlineFolderDownloadClient: Error sending action: \(error!)")
        self.status = .failed(.failedToConnect)
        self.invalidate()
        return
      }
      
      print("HotlineFolderDownloadClient: Action sent successfully")
      // Don't call receiveFolder() here - the main receive loop handles it
    })
  }
  
  private func receiveFolder() {
    print("HotlineFolderDownloadClient: receiveFolder() called, status: \(self.status)")
    guard let c = self.connection else {
      print("HotlineFolderDownloadClient: No connection in receiveFolder")
      return
    }
    
    print("HotlineFolderDownloadClient: Connection state: \(c.state)")
    print("HotlineFolderDownloadClient: About to call c.receive()")
    
    c.receive(minimumIncompleteLength: 1, maximumLength: Int(UInt16.max)) { [weak self] (data, context, isComplete, error) in
      print("HotlineFolderDownloadClient: Receive completion handler called! isComplete: \(isComplete), error: \(String(describing: error)), dataCount: \(data?.count ?? 0)")
      
      guard let self = self else {
        print("HotlineFolderDownloadClient: self is nil in receiveFolder")
        return
      }
      
      if let error = error {
        if self.status == .completed,
           case .posix(let posixError) = error,
           posixError == .ENODATA {
          print("HotlineFolderDownloadClient: Ignoring ENODATA after completion")
          return
        }
        
        print("HotlineFolderDownloadClient: Error in receiveFolder: \(error)")
        self.status = .failed(.failedToDownload)
        self.invalidate()
        return
      }
      
      if let newData = data, !newData.isEmpty {
        print("HotlineFolderDownloadClient: Received \(newData.count) bytes (total: \(self.fileBytesTransferred + newData.count)/\(self.referenceDataSize))")
        self.fileBytesTransferred += newData.count
        self.fileBytes.append(newData)
        self.fileProgress.completedUnitCount = Int64(self.fileBytesTransferred)
        self.status = .progress(Double(self.fileBytesTransferred) / Double(self.referenceDataSize))
      }
      else {
        print("HotlineFolderDownloadClient: Received empty or nil data, isComplete: \(isComplete)")
      }
      
      // Process received data
      var keepProcessing = false
      repeat {
        keepProcessing = false
        
        switch self.transferStage {
        case .itemHeader:
          // Need 2-byte length + header data
          guard self.fileBytes.count >= 2 else { break }
          let headerLen = Int(self.fileBytes.readUInt16(at: 0)!)
          guard self.fileBytes.count >= 2 + headerLen else { break }
          
          let headerData = self.fileBytes.subdata(in: 2..<(2 + headerLen))
          
          guard let parsed = parseItemHeaderPath(headerData) else {
            print("HotlineFolderDownloadClient: Invalid item header; waiting for more data")
            break
          }
          
          // Consume the header from the buffer
          self.fileBytes.removeSubrange(0..<(2 + headerLen))
          
          let itemType = parsed.type
          let comps = parsed.components
          let joinedPath = comps.joined(separator: "/")
          print("HotlineFolderDownloadClient: item type=\(itemType) path=\(joinedPath)")
          
          guard !comps.isEmpty else {
            print("HotlineFolderDownloadClient: Empty path components for item type \(itemType); requesting next item")
            self.sendAction(.nextFile)
            keepProcessing = !self.fileBytes.isEmpty
            break
          }
          
          if itemType == 1 {
            // Folder entries: create the directory locally and continue.
            self.currentItemRelativePath = comps
            
            if let base = self.folderPath {
              var dir = base
              for c in comps { dir = (dir as NSString).appendingPathComponent(c) }
              do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                print("HotlineFolderDownloadClient: Created folder at \(dir)")
              } catch {
                print("HotlineFolderDownloadClient: Failed to create subfolder: \(error)")
              }
            }
            
            self.completedItemCount += 1
            
            if self.completedItemCount >= self.folderItemCount {
              self.handleAllItemsDownloaded()
              return
            }
            
            self.sendAction(.nextFile)
            keepProcessing = !self.fileBytes.isEmpty
            break
          }
          else if itemType == 0 {
            // File entries include the full path; split parent components from filename.
            self.currentItemRelativePath = Array(comps.dropLast())
            self.currentFileName = comps.last
            
            self.transferStage = .waitingForFileSize
            print("HotlineFolderDownloadClient: Requesting file download for '\(self.currentFileName ?? "?")'")
            self.sendAction(.sendFile)
            
            if self.fileBytes.count >= 4 {
              keepProcessing = true
            }
            break
          }
          else {
            print("HotlineFolderDownloadClient: Unknown item type \(itemType); skipping")
            self.sendAction(.nextFile)
            keepProcessing = !self.fileBytes.isEmpty
            break
          }
          
        case .waitingForFileSize:
          // Read 4-byte file size that comes before FILP in folder mode
          guard self.fileBytes.count >= 4 else { break }
          let fileSize = self.fileBytes.readUInt32(at: 0)!
          self.fileBytes.removeSubrange(0..<4)
          
          print("HotlineFolderDownloadClient: File size: \(fileSize) bytes")
          
          self.currentFileSize = fileSize
          self.currentFileBytesRead = 0
          
          // Align to FILP boundary before decoding the file header
          let dropped = self.alignBufferToFILP()
          if dropped > 0 {
            // These bytes were in the stream for this file but not part of FILP.
            // Keep byte-accounting consistent by shrinking the expected size.
            if self.currentFileSize >= UInt32(dropped) {
              self.currentFileSize -= UInt32(dropped)
            } else {
              // Defensive: if weird, treat as zero-size to avoid underflow
              self.currentFileSize = 0
            }
          }
          
          self.transferStage = .fileHeader
          keepProcessing = true
          
        case .fileHeader:
          // Make sure we're actually at a FILP header
          if self.fileBytes.count >= HotlineFileHeader.DataSize {
            // If the 4-byte magic doesn't match, try one more resync here
            if self.fileBytes.readUInt32(at: 0)! != FILP_MAGIC {
              let dropped = self.alignBufferToFILP()
              if dropped > 0 {
                if self.currentFileSize >= UInt32(dropped) { self.currentFileSize -= UInt32(dropped) }
              }
              // If still not aligned or not enough bytes, wait for more data
              guard self.fileBytes.count >= HotlineFileHeader.DataSize,
                    self.fileBytes.readUInt32(at: 0)! == FILP_MAGIC else { break }
            }
            
            if let header = HotlineFileHeader(from: self.fileBytes) {
              // Sanity gate: version and fork count
              if header.format != FILP_MAGIC || header.version == 0 || header.forkCount > 3 {
                print("HotlineFolderDownloadClient: Invalid FILP header (fmt=\(String(format:"0x%08X", header.format)), ver=\(header.version), forks=\(header.forkCount)). Resyncing.")
                // Try resync and wait for more data
                let dropped = self.alignBufferToFILP()
                if dropped > 0 { if self.currentFileSize >= UInt32(dropped) { self.currentFileSize -= UInt32(dropped) } }
                break
              }
              
              self.fileBytes.removeSubrange(0..<HotlineFileHeader.DataSize)
              self.currentFileBytesRead += HotlineFileHeader.DataSize
              self.fileHeader = header
              self.fileForksRemaining = Int(header.forkCount)
              print("HotlineFolderDownloadClient: File has \(header.forkCount) forks")
              self.transferStage = .fileForkHeader
              keepProcessing = true
            }
          }
        case .fileForkHeader:
          let allForksConsumed = self.fileForksRemaining == 0 && self.fileCurrentForkHeader == nil && self.fileCurrentForkBytesLeft == 0
          
          if allForksConsumed {
            if self.currentFileBytesRead != Int(self.currentFileSize) {
              self.currentFileSize = UInt32(min(Int.max, self.currentFileBytesRead))
            }
            
            print("HotlineFolderDownloadClient: File complete (consumed all forks, bytes read: \(self.currentFileBytesRead)/\(self.currentFileSize))")
            
            self.finishCurrentFile()
            self.completedItemCount += 1
            
            // Check if we've completed all items
            if self.completedItemCount >= self.folderItemCount {
              self.handleAllItemsDownloaded()
              return
            }
            
            // More files to download
            // Check if server has pipelined all remaining data (we've received more than expected total)
            print("HotlineFolderDownloadClient: Completed \(self.completedItemCount)/\(self.folderItemCount) items, requesting next entry")
            self.transferStage = .itemHeader
            self.sendAction(.nextFile)
            keepProcessing = !self.fileBytes.isEmpty
          }
          // File not complete - try to read next fork header
          else if let forkHeader = HotlineFileForkHeader(from: self.fileBytes) {
            // Quick validation: first fork must be INFO, and sizes must be plausible
            let remainingForThisFile = max(0, Int(self.currentFileSize) - self.currentFileBytesRead)
            let plausible = forkHeader.dataSize <= UInt32(remainingForThisFile)
            let knownType = forkHeader.isInfoFork || forkHeader.isDataFork || forkHeader.isResourceFork
            
            if !plausible || (!knownType && self.currentFileBytesRead == HotlineFileHeader.DataSize) {
              print("HotlineFolderDownloadClient: Implausible fork header (type=\(String(format:"0x%08X", forkHeader.forkType)), size=\(forkHeader.dataSize), remaining=\(remainingForThisFile)). Resyncing.")
              let dropped = self.alignBufferToFILP()
              if dropped > 0 { if self.currentFileSize >= UInt32(dropped) { self.currentFileSize -= UInt32(dropped) } }
              break
            }
            
            self.fileBytes.removeSubrange(0..<HotlineFileForkHeader.DataSize)
            self.currentFileBytesRead += HotlineFileForkHeader.DataSize
            self.fileCurrentForkHeader = forkHeader
            self.fileCurrentForkBytesLeft = Int(forkHeader.dataSize)
            self.fileForksRemaining -= 1  // Decrement fork count
            
            print("HotlineFolderDownloadClient: Read fork header (type: \(String(format: "0x%08X", forkHeader.forkType)), size: \(forkHeader.dataSize) bytes, \(self.fileForksRemaining) forks remaining)")
            
            // Handle zero-length forks immediately
            if forkHeader.dataSize == 0 {
              print("HotlineFolderDownloadClient: Skipping zero-length fork")
              self.fileCurrentForkHeader = nil
              self.fileCurrentForkBytesLeft = 0
              // Stay in .fileForkHeader to read next fork or complete file
              keepProcessing = true
            }
            else if forkHeader.isInfoFork {
              print("HotlineFolderDownloadClient: Downloading info fork for item \(self.currentItemNumber + 1)/\(self.folderItemCount)")
              self.transferStage = .fileInfoFork
              keepProcessing = true
            }
            else if forkHeader.isDataFork {
              print("HotlineFolderDownloadClient: Downloading data fork")
              self.transferStage = .fileDataFork
              keepProcessing = true
            }
            else if forkHeader.isResourceFork {
              print("HotlineFolderDownloadClient: Downloading resource fork")
              self.fileResourceBytes = Data()
              self.transferStage = .fileResourceFork
              keepProcessing = true
            }
            else {
              print("HotlineFolderDownloadClient: Downloading unsupported fork (type: \(String(format: "0x%08X", forkHeader.forkType)), size: \(forkHeader.dataSize) bytes)")
              self.transferStage = .fileUnsupportedFork
              keepProcessing = true
            }
          }
          // Not enough data yet for next fork header - wait for more data
          
        case .fileInfoFork:
          if let infoForkDataSize = self.fileCurrentForkHeader?.dataSize, self.fileBytes.count >= infoForkDataSize {
            let infoForkData = self.fileBytes.subdata(in: 0..<Int(infoForkDataSize))
            if let infoFork = HotlineFileInfoFork(from: infoForkData) {
              self.fileInfoFork = infoFork
              
              self.fileBytes.removeSubrange(0..<infoFork.headerSize)
              self.currentFileBytesRead += infoFork.headerSize
              
              self.fileCurrentForkBytesLeft -= Int(infoForkDataSize)
              self.fileCurrentForkHeader = nil
              
              print("HotlineFolderDownloadClient: Received info fork for \(infoFork.name)")
              
              // Create the file on disk using the filename we extracted from the item header
              if !self.prepareDownloadFile(name: self.currentFileName ?? infoFork.name) {
                print("HotlineFolderDownloadClient: Failed to create file on disk")
              }
              
              self.currentItemNumber += 1
              
              let reference = self.referenceNumber
              let fileName = infoFork.name
              let itemNum = self.currentItemNumber
              let totalItems = self.folderItemCount
              DispatchQueue.main.async {
                self.delegate?.hotlineFolderDownloadReceivedFileInfo(client: self, reference: reference, fileName: fileName, itemNumber: itemNum, totalItems: totalItems)
              }
              
              // Info fork complete, check for next fork
              self.transferStage = .fileForkHeader
              keepProcessing = true
            }
          }
        case .fileDataFork:
          if self.fileBytes.count > 0 {
            if let f = self.fileHandle {
              do {
                var dataToWrite = self.fileBytes
                
                if dataToWrite.count >= self.fileCurrentForkBytesLeft {
                  dataToWrite = self.fileBytes.subdata(in: 0..<self.fileCurrentForkBytesLeft)
                  self.fileBytes.removeSubrange(0..<self.fileCurrentForkBytesLeft)
                  self.currentFileBytesRead += dataToWrite.count
                  
                  self.fileCurrentForkBytesLeft = 0
                  self.fileCurrentForkHeader = nil
                  
                  // Write the final chunk of data
                  try f.write(contentsOf: dataToWrite)
                  
                  print("HotlineFolderDownloadClient: Data fork complete")
                  
                  self.transferStage = .fileForkHeader
                  keepProcessing = true
                }
                else {
                  self.fileCurrentForkBytesLeft -= dataToWrite.count
                  self.currentFileBytesRead += dataToWrite.count
                  self.fileBytes = Data()
                  
                  // Write partial data
                  try f.write(contentsOf: dataToWrite)
                }
              }
              catch {
                print("HotlineFolderDownloadClient: Download write error", error)
              }
            }
          }
        case .fileResourceFork:
          if self.fileBytes.count > 0 {
            var dataToWrite = self.fileBytes
            
            if dataToWrite.count >= self.fileCurrentForkBytesLeft {
              dataToWrite = self.fileBytes.subdata(in: 0..<self.fileCurrentForkBytesLeft)
              self.fileBytes.removeSubrange(0..<self.fileCurrentForkBytesLeft)
              self.currentFileBytesRead += dataToWrite.count
              
              self.fileCurrentForkBytesLeft = 0
              self.fileCurrentForkHeader = nil
              
              print("HotlineFolderDownloadClient: Writing to resource fork", dataToWrite.count)
              self.fileResourceBytes.append(dataToWrite)
              
              print("HotlineFolderDownloadClient: Resource fork complete")
              
              self.transferStage = .fileForkHeader
              keepProcessing = true
            }
            else {
              self.fileCurrentForkBytesLeft -= dataToWrite.count
              self.currentFileBytesRead += dataToWrite.count
              self.fileBytes = Data()
              
              print("HotlineFolderDownloadClient: Writing to resource fork", dataToWrite.count)
              self.fileResourceBytes.append(dataToWrite)
            }
          }
        case .fileUnsupportedFork:
          if self.fileBytes.count > 0 {
            var dataToWrite = self.fileBytes
            
            if dataToWrite.count >= self.fileCurrentForkBytesLeft {
              dataToWrite = self.fileBytes.subdata(in: 0..<self.fileCurrentForkBytesLeft)
              self.fileBytes.removeSubrange(0..<self.fileCurrentForkBytesLeft)
              self.currentFileBytesRead += dataToWrite.count
              
              self.fileCurrentForkBytesLeft = 0
              self.fileCurrentForkHeader = nil
              
              print("HotlineFolderDownloadClient: Unsupported fork complete (discarded \(dataToWrite.count) bytes)")
              
              self.transferStage = .fileForkHeader
              keepProcessing = true
            }
            else {
              self.fileCurrentForkBytesLeft -= dataToWrite.count
              self.currentFileBytesRead += dataToWrite.count
              print("HotlineFolderDownloadClient: Unsupported fork partial data (discarded \(dataToWrite.count) bytes, \(self.fileCurrentForkBytesLeft) bytes remaining)")
              self.fileBytes = Data()
            }
          }
        }
      } while keepProcessing
      
      // Continue receiving data - completion is handled in .fileForkHeader when all items are done
      if self.connection != nil && self.status != .completed {
        self.receiveFolder()
      }
    }
  }
  
  private func finishCurrentFile() {
    // Close current file handle
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    // Write resource fork if present
    if self.fileResourceBytes.count > 0 {
      let _ = self.writeResourceFork()
      self.fileResourceBytes = Data()
    }
    
    self.fileCurrentForkHeader = nil
    self.fileCurrentForkBytesLeft = 0
    self.fileForksRemaining = 0
    self.currentFileBytesRead = 0
    self.currentFileSize = 0
    self.currentFilePath = nil
    self.fileInfoFork = nil
    self.fileHeader = nil
    self.currentFileName = nil
  }
  
  private func handleAllItemsDownloaded() {
    guard self.status != .completed else {
      return
    }
    
    print("HotlineFolderDownloadClient: All \(self.folderItemCount) items downloaded")
    
    self.invalidate()
    self.status = .completed
    
    if let downloadPath = self.folderPath {
      DispatchQueue.main.sync {
        print("HotlineFolderDownloadClient: Folder download complete", downloadPath)
        
        var downloadURL = URL(filePath: downloadPath)
        downloadURL.resolveSymlinksInPath()
        
        self.delegate?.hotlineFolderDownloadComplete(client: self, reference: self.referenceNumber, at: downloadURL)
        
#if os(macOS)
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: downloadURL.path)
#endif
      }
    }
  }
  
  private func writeResourceFork() -> Bool {
    guard let filePath = self.currentFilePath else {
      return false
    }
    
    var resolvedFileURL = URL(filePath: filePath)
    resolvedFileURL.resolveSymlinksInPath()
    
    let resourceFilePath = resolvedFileURL.appendingPathComponent("..namedfork/rsrc")
    
    do {
      try self.fileResourceBytes.write(to: resourceFilePath)
    }
    catch {
      return false
    }
    
    return true
  }
  
  private func prepareDownloadFile(name: String) -> Bool {
    var filePath: String
    
    if self.folderPath != nil {
      // Build the full path including subfolders
      var fullPath = self.folderPath!
      for component in self.currentItemRelativePath {
        fullPath = (fullPath as NSString).appendingPathComponent(component)
      }
      
      let folderURL = URL(filePath: fullPath)
      
      // Create folder if it doesn't exist
      if !FileManager.default.fileExists(atPath: folderURL.path) {
        do {
          try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        catch {
          print("HotlineFolderDownloadClient: Failed to create folder", error)
          return false
        }
      }
      
      filePath = folderURL.appendingPathComponent(name).path
      print("HotlineFolderDownloadClient: Creating file at \(filePath)")
    }
    else {
      let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
      filePath = downloadsURL.generateUniqueFilePath(filename: name)
    }
    
    var fileAttributes: [FileAttributeKey: Any] = [:]
    if let creatorCode = self.fileInfoFork?.creator {
      fileAttributes[.hfsCreatorCode] = creatorCode as NSNumber
    }
    if let typeCode = self.fileInfoFork?.type {
      fileAttributes[.hfsTypeCode] = typeCode as NSNumber
    }
    if let createdDate = self.fileInfoFork?.createdDate {
      fileAttributes[.creationDate] = createdDate as NSDate
    }
    if let modifiedDate = self.fileInfoFork?.modifiedDate {
      fileAttributes[.modificationDate] = modifiedDate as NSDate
    }
    if let comment = self.fileInfoFork?.comment {
      if let commentPlistData = try? PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0) {
        fileAttributes[FileAttributeKey(rawValue: "NSFileExtendedAttributes")] = [
          FileAttributeKey(rawValue: "com.apple.metadata:kMDItemFinderComment"): commentPlistData
        ]
      }
    }
    
    if FileManager.default.createFile(atPath: filePath, contents: nil, attributes: fileAttributes) {
      if let h = FileHandle(forWritingAtPath: filePath) {
        self.currentFilePath = filePath
        self.fileHandle = h
        
        // Only set file progress on first file
        if self.currentItemNumber == 1 && self.folderPath != nil {
          self.fileProgress.fileURL = URL(filePath: self.folderPath!).resolvingSymlinksInPath()
          self.fileProgress.fileOperationKind = .downloading
          self.fileProgress.publish()
        }
        
        return true
      }
    }
    
    return false
  }
}
