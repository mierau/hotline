import Foundation
import Network

enum HotlineFileClientError: Error {
  case failedToConnect
  case failedToDownload
}

enum HotlineFileClientStatus: Equatable {
  case unconnected
  case connecting
  case connected
  case progress(Double)
  case completed
  case failed(HotlineFileClientError)
}

protocol HotlineFileClientDelegate: AnyObject {
  func hotlineFileStatusChanged(client: HotlineFileClient, reference: UInt32, status: HotlineFileClientStatus, timeRemaining: TimeInterval)
  func hotlineFileReceivedInfo(client: HotlineFileClient, reference: UInt32, info: HotlineFileInfoFork)
  func hotlineFileDownloadedData(client: HotlineFileClient, reference: UInt32, data: Data)
  func hotlineFileDownloadedFile(client: HotlineFileClient, reference: UInt32, at: URL)
}

extension HotlineFileClientDelegate {
  func hotlineFileStatusChanged(client: HotlineFileClient, reference: UInt32, status: HotlineFileClientStatus, timeRemaining: TimeInterval) {}
  func hotlineFileReceivedInfo(client: HotlineFileClient, reference: UInt32, info: HotlineFileInfoFork) {}
  func hotlineFileDownloadedData(client: HotlineFileClient, reference: UInt32, data: Data) {}
  func hotlineFileDownloadedFile(client: HotlineFileClient, reference: UInt32, at: URL) {}
}

enum HotlineFileTransferType {
  case file
  case preview
}

enum HotlineFileTransferStage: Int {
  case fileHeader = 1
  case fileForkHeader = 2
  case fileInfoFork = 3
  case fileDataFork = 4
  case fileUnsupportedFork = 5
}

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
    // self.reserved = data.readData(at: 4 + 2, length: 16)
    self.forkCount = data.readUInt16(at: 4 + 2 + 16)!
  }
}

struct HotlineFileForkHeader {
  static let DataSize: Int = 4 + 4 + 4 + 4
  
  let forkType: UInt32
  let compressionType: UInt32
  let dataSize: UInt32
  
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
}

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
}

class HotlineFileClient {
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port
  let referenceNumber: UInt32
  let referenceDataSize: UInt32
  let transferType: HotlineFileTransferType
  
  weak var delegate: HotlineFileClientDelegate? = nil
  
  var status: HotlineFileClientStatus = .unconnected {
    didSet {
      DispatchQueue.main.async {
        self.delegate?.hotlineFileStatusChanged(client: self, reference: self.referenceNumber, status: self.status, timeRemaining: self.fileProgress?.estimatedTimeRemaining ?? 0.0)
      }
    }
  }
  
  private var connection: NWConnection?
  private var transferStage: HotlineFileTransferStage = .fileHeader
  
  private var fileBytes = Data()
  
  private var fileHeader: HotlineFileHeader? = nil
  private var fileCurrentForkHeader: HotlineFileForkHeader? = nil
  private var fileCurrentForkBytesLeft: Int = 0
  private var fileInfoFork: HotlineFileInfoFork? = nil
  private var fileHandle: FileHandle? = nil
  private var filePath: String? = nil
  private var fileBytesDownloaded: Int = 0
  private var fileProgress: Progress? = nil
  
//  private var previewCallback: ((Data?) -> Void)? = nil
//  private var fileCallback: ((URL?) -> Void)? = nil
  
  init(address: String, port: UInt16, reference: UInt32, size: UInt32, type: HotlineFileTransferType = .file) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.referenceDataSize = size
    self.transferType = type
    self.transferStage = .fileHeader
  }
  
  deinit {
    self.invalidate()
  }
  
  func downloadToMemory() {
    guard self.status == .unconnected else {
      return
    }
    
    self.connect()
  }
  
  func downloadToFile() {
    guard self.status == .unconnected else {
      return
    }

    self.connect()
  }
  
  func cancel(deleteIncompleteFile: Bool = true) {
    self.delegate = nil
    
    if self.status == .unconnected {
      return
    }
    
    // Close file before we try to potentionally delete it.
    if let fh = self.fileHandle {
      try? fh.close()
      self.fileHandle = nil
    }
    
    if deleteIncompleteFile, let downloadPath = self.filePath {
      print("HotlineFileClient: Deleting file fragment at", downloadPath)
      if FileManager.default.isDeletableFile(atPath: downloadPath) {
        try? FileManager.default.removeItem(atPath: downloadPath)
      }
      self.filePath = nil
    }
    
    self.invalidate()
    
    print("HotlineFileClient: Cancelled transfer")
  }
  
  // MARK: -
  
  private func connect() {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        self?.status = .connected
        self?.sendMagic()
      case .cancelled:
        self?.invalidate()
      case .failed(let err):
        print("HotlineTrackerClient: Connection error \(err)")
        switch self?.status {
        case .connecting:
          print("FAILED TO CONNECT")
          self?.invalidate()
          self?.status = .failed(.failedToConnect)
        case .connected, .progress(_):
          print("FAILED TO DOWNLLOAD")
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
  }
  
  private func sendMagic() {
    guard let c = connection, self.status == .connected else {
      self.invalidate()
      print("HotlineFileClient: invalid connection to send header.")
      return
    }
    
    var headerData = Data()
    headerData.appendUInt32("HTXF".fourCharCode())
    headerData.appendUInt32(self.referenceNumber)
    headerData.appendUInt32(0)
    headerData.appendUInt32(0)
    
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
      
      switch self.transferType {
      case .file:
        self.receiveFile()
      case .preview:
        self.receivePreviewData()
      }
    })
  }
  
  private func receiveFile() {
    guard let c = self.connection else {
      return
    }
    
    c.receive(minimumIncompleteLength: 1024, maximumLength: Int(UInt16.max)) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      guard error == nil else {
        self.status = .failed(.failedToDownload)
        self.invalidate()
        return
      }
      
      if let newData = data, !newData.isEmpty {
        self.fileBytesDownloaded += newData.count
        self.fileBytes.append(newData)
        self.fileProgress?.completedUnitCount = Int64(self.fileBytesDownloaded)
        self.status = .progress(Double(self.fileBytesDownloaded) / Double(self.referenceDataSize))
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
            print("FILE HEADER", self.fileHeader)
            
            self.transferStage = .fileForkHeader
            keepProcessing = true
          }
        case .fileForkHeader:
          if let forkHeader = HotlineFileForkHeader(from: self.fileBytes) {
//            let fileForkHeader = HotlineFileForkHeader(from: self.fileBytes)
            self.fileBytes.removeSubrange(0..<HotlineFileForkHeader.DataSize)
            self.fileCurrentForkHeader = forkHeader
            self.fileCurrentForkBytesLeft = Int(forkHeader.dataSize)
            
            print("FILE FORK HEADER", forkHeader, forkHeader.forkType.fourCharCode())
            if forkHeader.forkType == "INFO".fourCharCode() {
              print("INFO FORK!")
              self.transferStage = .fileInfoFork
            }
            else if forkHeader.forkType == "DATA".fourCharCode() {
              print("DATA FORK!")
              self.transferStage = .fileDataFork
            }
            else if forkHeader.forkType == "MACR".fourCharCode() {
              print("RESOURCE FORK!")
              self.transferStage = .fileUnsupportedFork
            }
            else {
              print("UNKNOWN FORK??")
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
              
              if !self.prepareDownloadFile(name: infoFork.name) {
                print("FAILED TO CREATE FILE ON DISK")
              }
              
              let reference = self.referenceNumber
              DispatchQueue.main.async {
                self.delegate?.hotlineFileReceivedInfo(client: self, reference: reference, info: infoFork)
              }
            }
            
            keepProcessing = true
          }
        case .fileDataFork:
          if self.fileBytes.count > 0 {
            print("DOWNLOADING DATA FORK")
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
                
                print("WRITING \(dataToWrite.count) BYTES TO DISK")
                
                try f.write(contentsOf: dataToWrite)
              }
              catch {
                print("DOWNLOAD WRITE ERROR", error)
              }
            }
          }
        case .fileUnsupportedFork:
          if self.fileBytes.count > 0 {
            print("SKIPPING UNSUPPORTED FORK DATA")
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
      
      if self.fileBytesDownloaded < Int(self.referenceDataSize) {
        // If we still have more to download, then receive more data.
        self.receiveFile()
        return
      }
      else {
        print("FILE COMPLETE")
        if let h = self.fileHandle {
          try? h.close()
          self.fileHandle = nil
        }
        self.fileBytes = Data()
        
        self.status = .completed
        self.invalidate()
        
        if let downloadPath = self.filePath {
          DispatchQueue.main.sync {
            print("POSTING DOWNLOAD FILE FINISHED", downloadPath)
            
            var downloadURL = URL(filePath: downloadPath)
            downloadURL.resolveSymlinksInPath()
            print("FINAL PATH", downloadURL.path)
            
            let reference = self.referenceNumber
            self.delegate?.hotlineFileDownloadedFile(client: self, reference: reference, at: downloadURL)
            
            #if os(macOS)
            // Bounce dock icon when download completes. Weird this is the only API to do so.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: downloadURL.path)
            #endif
          }
        }
      }
    }
  }
  
  private func receivePreviewData() {
    guard let c = self.connection else {
      return
    }
            
    c.receive(minimumIncompleteLength: 1024, maximumLength: Int(UInt16.max)) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      guard error == nil else {
        self.status = .failed(.failedToDownload)
        self.invalidate()
        return
      }
      
      if let newData = data, !newData.isEmpty {
        self.fileBytesDownloaded += newData.count
        self.fileBytes.append(newData)
        self.fileProgress?.completedUnitCount = Int64(self.fileBytesDownloaded)
        self.status = .progress(Double(self.fileBytesDownloaded) / Double(self.referenceDataSize))
        
        
        
        print("DOWNLOAD PROGRESS", self.fileProgress.debugDescription)
      }
      
      if self.fileBytesDownloaded < Int(self.referenceDataSize) {
        self.receivePreviewData()
      }
      else {
        let reference = self.referenceNumber
        let data = self.fileBytes
        
        self.status = .completed
        self.invalidate()
        
        DispatchQueue.main.sync {
          self.delegate?.hotlineFileDownloadedData(client: self, reference: reference, data: data)
        }
      }
    }
  }
  
  // MARK: - Utility
  
  private func findUniqueFilePath(base: String, at folderURL: URL) -> String {
    let fileManager = FileManager.default
    var finalName = base
    var counter = 2
    
    // Helper function to generate a new filename with a counter
    func makeFileName() -> String {
      let baseName = (base as NSString).deletingPathExtension
      let extensionName = (base as NSString).pathExtension
      return extensionName.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(extensionName)"
    }
    
    // Check if file exists and append counter until a unique name is found
    var filePath = folderURL.appending(component: finalName).path(percentEncoded: false)
    while fileManager.fileExists(atPath: filePath) {
      finalName = makeFileName()
      filePath = folderURL.appending(component: finalName).path(percentEncoded: false)
      counter += 1
    }
    
    return filePath
  }
  
  private func prepareDownloadFile(name: String) -> Bool {
    let folderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    let filePath = findUniqueFilePath(base: name, at: folderURL)
    
    if FileManager.default.createFile(atPath: filePath, contents: nil) {
      if let h = FileHandle(forWritingAtPath: filePath) {
        self.filePath = filePath
        self.fileHandle = h
        self.fileProgress?.fileURL = URL(filePath: filePath).resolvingSymlinksInPath()
        return true
      }
    }
    
    return false
  }
}
