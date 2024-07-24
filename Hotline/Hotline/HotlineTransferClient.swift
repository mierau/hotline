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
  case completed
  case failed(HotlineFileClientError)
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

//enum HotlineFileTransferType {
//  case fileDownload
//  case filePreview
//  case fileUpload
//}

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
      
      var magicData = Data()
      magicData.appendUInt32("HTXF".fourCharCode())
      magicData.appendUInt32(self.referenceNumber)
      magicData.appendUInt32(self.payloadSize)
      magicData.appendUInt32(0)
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
      let header = HotlineFileForkHeader(type: "INFO".fourCharCode(), dataSize: UInt32(self.infoForkData.count))
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
        
        let header = HotlineFileForkHeader(type: "DATA".fourCharCode(), dataSize: self.dataForkSize)
        
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
         
        print("Upload: Sending Data Fork \(String(describing: fileData?.count))")
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
      
      let header = HotlineFileForkHeader(type: "MACR".fourCharCode(), dataSize: self.resourceForkSize)
      
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
      self.status = .completed
      self.invalidate()
      
      DispatchQueue.main.sync {
        self.delegate?.hotlineFileUploadComplete(client: self, reference: self.referenceNumber)
      }
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
  
  private var connection: NWConnection?
  private var transferStage: HotlineFileTransferStage = .fileHeader
  private var fileBytes = Data()
  private var fileBytesTransferred: Int = 0
  
  init(address: String, port: UInt16, reference: UInt32, size: UInt32) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.referenceDataSize = size
  }
  
  deinit {
    self.invalidate()
  }
  
  func start() {
    guard self.status == .unconnected else {
      return
    }
    
    self.connect()
  }
  
  func cancel() {
    self.delegate = nil
    
    if self.status == .unconnected {
      return
    }
    
    self.invalidate()
    
    print("HotlineFilePreviewClient: Cancelled preview transfer")
  }
  
  private func invalidate() {
    if let c = self.connection {
      c.stateUpdateHandler = nil
      c.cancel()
      
      self.connection = nil
    }
    
    self.fileBytes = Data()
  }
  
  private func connect() {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        self?.status = .connected
        self?.sendMagic()
      case .waiting(let err):
        print("HotlineFilePreviewClient: Waiting", err)
      case .cancelled:
        print("HotlineFilePreviewClient: Cancelled")
        self?.invalidate()
      case .failed(let err):
        print("HotlineFilePreviewClient: Connection error \(err)")
        switch self?.status {
        case .connecting:
          print("HotlineFilePreviewClient: Failed to connect to file transfer server.")
          self?.invalidate()
          self?.status = .failed(.failedToConnect)
        case .connected, .progress(_):
          print("HotlineFilePreviewClient: Failed to finish transfer.")
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
      self.receive()
    })
  }
  
  private func receive() {
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
        self.status = .progress(Double(self.fileBytesTransferred) / Double(self.referenceDataSize))
        print("HotlineFilePreviewClient: Download progress", self.fileBytesTransferred, self.referenceDataSize, isComplete)
      }
      
      if self.fileBytesTransferred < Int(self.referenceDataSize) {
        self.receive()
      }
      else {
        print("HotlineFilePreviewClient: Complete")
        let data = self.fileBytes
        
        self.status = .completed
        self.invalidate()
        
        let reference = self.referenceNumber
        DispatchQueue.main.sync {
          self.delegate?.hotlineFilePreviewComplete(client: self, reference: reference, data: data)
        }
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
//            if let f = self.fileResourceHandle {
//              do {
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
//                try f.write(contentsOf: dataToWrite)
//              }
//              catch {
//                print("DOWNLOAD WRITE ERROR", error)
//              }
//            }
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
      
    var fileAttributes: [FileAttributeKey : Any] = [:]
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
    // self.reserved = data.readData(at: 4 + 2, length: 16)
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
      self.forkCount = 2
    }
    else {
      self.forkCount = 1
    }
  }
  
  func data() -> Data {
    var d = Data()
    
    d.appendUInt32(self.format)
    d.appendUInt16(self.version)
    d.appendZeros(count: 16)
    d.appendUInt16(self.forkCount)
    
    return d
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
    var d = Data()
    
    d.appendUInt32(self.forkType)
    d.appendUInt32(self.compressionType)
    d.appendUInt32(0)
    d.appendUInt32(self.dataSize)
    
    return d
  }
  
  var isInfoFork: Bool {
    return self.forkType == "INFO".fourCharCode()
  }
  
  var isDataFork: Bool {
    return self.forkType == "DATA".fourCharCode()
  }
  
  var isResourceFork: Bool {
    return self.forkType == "MACR".fourCharCode()
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
    
    self.comment = nil
    
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
    var d = Data()
    
    d.appendUInt32(self.platform)
    d.appendUInt32(self.type)
    d.appendUInt32(self.creator)
    d.appendUInt32(self.flags)
    d.appendUInt32(self.platformFlags)
    d.appendZeros(count: 32)
    d.appendDate(self.createdDate)
    d.appendDate(self.modifiedDate)
    d.appendUInt16(self.nameScript)
    
    d.appendUInt16(UInt16(self.name.count))
    d.appendString(self.name, encoding: .macOSRoman)
    
    return d
  }
}
