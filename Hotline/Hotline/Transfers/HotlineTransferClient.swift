import Foundation
import NetSocket
import Network
import UniformTypeIdentifiers

protocol HotlineTransferClient {
//  var serverAddress: NWEndpoint.Host { get }
//  var serverPort: NWEndpoint.Port { get }
//  var referenceNumber: UInt32 { get }
//  var status: HotlineTransferStatus { get set }
  
//  func start()
  func cancel()
}

enum HotlineTransferClientError: Error {
  case failedToConnect
  case failedToTransfer
  case cancelled
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
  case failed(HotlineTransferClientError)
}

enum HotlineFileForkType: UInt32 {
  case none = 0
  case unsupported = 1
  case info = 0x494E464F // 'INFO'
  case data = 0x44415441 // 'DATA'
  case resource = 1296122706 // 'MACR'
}

public enum HotlineFolderAction: UInt16 {
  case sendFile = 1
  case resumeFile = 2
  case nextFile = 3
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
    
    self.format = data.read(UInt32.self, at: 0)!
    self.version = data.read(UInt16.self, at: 4)!
    // 16 bytes of reserved data sits here. Skip it.
    self.forkCount = data.read(UInt16.self, at: 4 + 2 + 16)!
  }
  
  init?(file fileURL: URL) {
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
      return nil
    }
    
    self.format = "FILP".fourCharCode()
    self.version = 1

    let resourceURL = fileURL.urlForResourceFork()
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
    
    self.forkType = data.read(UInt32.self, at: 0)!
    self.compressionType = data.read(UInt32.self, at: 4)!
    // 4 bytes of reserved data sits here. Skip it.
    // self.reserved = data.read(UInt32.self, at: 4 + 4)!
    self.dataSize = data.read(UInt32.self, at: 4 + 4 + 4)!
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
      let platform = data.read(UInt32.self, at: 0),
      let type = data.read(UInt32.self, at: 4),
      let creator = data.read(UInt32.self, at: 4 + 4),
      let flags = data.read(UInt32.self, at: 4 + 4 + 4),
      let platformFlags = data.read(UInt32.self, at: 4 + 4 + 4 + 4),
      // 32 bytes of reserved data sits here. Skip it.
      let nameScript = data.read(UInt16.self, at: 4 + 4 + 4 + 4 + 4 + 32 + 8 + 8) {
      
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
          let commentLength = data.read(UInt16.self, at: HotlineFileInfoFork.BaseDataSize + nl)!
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
  
  func data() -> Data? {
    guard let fileName = self.name.data(using: .macOSRoman, allowLossyConversion: true) else {
      return nil
    }
    
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
