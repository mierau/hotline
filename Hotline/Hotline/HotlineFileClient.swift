import Foundation
import Network

enum HotlineFileTransferType {
  case banner
  case file
}

enum HotlineFileStatus: Int {
  case disconnected
  case connecting
  case connected
  case downloading
  case complete
}

@Observable
class HotlineFileClient {
  var status: HotlineFileStatus = .disconnected
  var progress: Double = -1.0
  
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port
  let referenceNumber: UInt32
  let referenceDataSize: UInt32
  let transferType: HotlineFileTransferType
  
  private var connection: NWConnection?
  private var fileBytes = Data()
  
  init(address: String, port: UInt16, reference: UInt32, size: UInt32, type: HotlineFileTransferType = .file) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: port + 1)!
    self.referenceNumber = reference
    self.referenceDataSize = size
    self.status = .disconnected
    self.transferType = type
    
    if size == 0 {
      self.progress = -1.0
    }
    else {
      self.progress = 0.0
    }
  }
  
  func downloadToMemory(_ callback: ((Data?) -> Void)?) {
    self.reset()
    self.connect { data in
      callback?(data)
    }
  }
  
  private func reset() {
    self.progress = 0.0
    self.fileBytes = Data()
  }
  
  private func connect(_ callback: ((Data?) -> Void)? = nil) {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        self?.status = .connected
        self?.sendMagic()
      case .cancelled:
        self?.status = .disconnected
        DispatchQueue.main.async {
          callback?(self?.fileBytes)
        }
      case .failed(let err):
        print("HotlineTrackerClient: Connection error \(err)")
        if self?.status == .complete {
          DispatchQueue.main.async {
            callback?(self?.fileBytes)
          }
        }
        else {
          self?.status = .disconnected
        }
      default:
        return
      }
    }
    
    self.status = .connecting
    self.connection?.start(queue: .global())
  }
  
  func disconnect() {
    self.status = .disconnected
    self.connection?.cancel()
    self.connection = nil
  }
  
  private func sendMagic() {
    guard let c = connection else {
      print("HotlineFileClient: invalid connection to send header.")
      return
    }
    
    var headerData = Data()
    headerData.appendUInt32(0x48545846) // 'HTXF'
    headerData.appendUInt32(self.referenceNumber)
    headerData.appendUInt32(self.referenceDataSize)
    headerData.appendUInt16(2) // Type
    headerData.appendUInt16(0) // Reserved?
    
    c.send(content: headerData, completion: .contentProcessed { [weak self] (error) in
      guard let transferType = self?.transferType else {
        self?.disconnect()
        return
      }
      
      if let err = error {
        print("HotlineFileClient: sending header failed \(err)")
        self?.disconnect()
        return
      }
      
      switch transferType {
      case .banner:
        self?.receiveBannerFile()
      case .file:
        break
      }
    })
  }
  
  private func receiveBannerFile() {
    guard let c = connection else {
      return
    }
    
    self.status = .downloading
    
    let finalSize = Double(self.referenceDataSize)
    var maxLength: Int = 65536
    
    if self.referenceDataSize != 0 {
      maxLength = max(Int(self.referenceDataSize) - self.fileBytes.count, 0)
    }
    
    if maxLength == 0 {
      self.status = .complete
      self.progress = 1.0
      self.disconnect()
      return
    }
    
    c.receive(minimumIncompleteLength: maxLength, maximumLength: maxLength) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let fileData = data {
        if !fileData.isEmpty {
          self.fileBytes.append(fileData)
          if finalSize > 0 {
            self.progress = min(min(Double(self.fileBytes.count) / finalSize, 1.0), 0.0)
          }
        }
      }
        
      if isComplete {
        self.status = .complete
        self.progress = 1.0
        self.disconnect()
      }
      else {
        self.receiveBannerFile()
      }
    }
  }
}
