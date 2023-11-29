import Foundation
import Network

enum HotlineClientStatus: Int {
  case disconnected
  case connecting
  case connected
}

class HotlineClient : ObservableObject {
  static let shared = HotlineClient()
  
  static let handshakePacket = Data([
    0x54, 0x52, 0x54, 0x50, // 'TRTP' protocol ID
    0x48, 0x4F, 0x54, 0x4C, // Sub-protocol ID
    0x00, 0x01, // Version
    0x00, 0x02, // Sub-version
  ])
  
  @Published var connectionStatus: HotlineClientStatus = .disconnected
  
  var server: HotlineServer?
  var connection: NWConnection?
  var bytes = Data()
  var handshakeComplete = false
  
  init() {
    
  }
  
  func connect(to server: HotlineServer) {
    self.server = server
    
    let serverAddress = NWEndpoint.Host(server.address)
    let serverPort = NWEndpoint.Port(rawValue: server.port)!
    
    self.connection = NWConnection(host: serverAddress, port: serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        print("HotlineClient: connection ready!")
        DispatchQueue.main.async {
          self?.connectionStatus = .connected
        }
        self?.sendHandshake()
      case .cancelled:
        print("HotlineClient: connection cancelled")
        DispatchQueue.main.async {
          self?.connectionStatus = .disconnected
        }
      case .failed(let err):
        print("HotlineClient: connection error \(err)")
        DispatchQueue.main.async {
          self?.connectionStatus = .disconnected
        }
      default:
        print("HotlineClient: unhandled connection state \(newState)")
      }
    }
    
    DispatchQueue.main.async {
      self.connectionStatus = .connecting
    }
    self.connection?.start(queue: .global())
  }
  
  private func disconnect() {
    guard let c = connection else {
      print("HotlineClient: already disconnected")
      return
    }
    
    c.cancel()
    self.connection = nil
  }
  
  private func sendHandshake() {
    guard let c = connection else {
      print("HotlineClient: invalid connection to send handshake.")
      return
    }
    
    c.send(content: HotlineClient.handshakePacket, completion: .contentProcessed { [weak self] (error) in
      if let err = error {
        print("HotlineClient: sending magic failed \(err)")
        return
      }
      
      print("HotlineClient: sent handshake packet!")
      
      self?.receiveHandshake()
    })
  }
  
  private func receiveHandshake() {
    guard let c = connection else {
      print("HotlineTracker: invalid connection to receive magic.")
      return
    }
    
    print("HotlineClient: receiving handshake...")
    c.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] (data, context, isComplete, error) in
      guard let self = self, let data = data else {
        return
      }
      
      if data.isEmpty {
        print("HotlineClient: empty handshake response")
        self.disconnect()
        return
      }
      
      let protocolID = data.readUInt32(at: 0)!
      if protocolID != 0x54525450 { // 'TRTP'
        print("HotlineClient: invalid handshake protocol ID \(protocolID)")
        self.disconnect()
        return
      }
      
      let errorCode = data.readUInt32(at: 4)!
      if errorCode != 0 { // 0 == no error
        print("HotlineClient: handshake error", errorCode)
        self.disconnect()
        return
      }
      
      print("HotlineClient: completed handshake")
      self.sendLogin()
    }
  }
  
  private func sendLogin() {
    guard let c = connection else {
      print("HotlineClient: no connection for transaction.")
      return
    }
    
    c.send(content: HotlineClient.handshakePacket, completion: .contentProcessed { [weak self] (error) in
      if let err = error {
        print("HotlineClient: sending login failed \(err)")
        return
      }
      
      print("HotlineClient: sent handshake packet!")
      
      
    })
  }
  
  private func receiveTransaction() {
    guard let c = connection else {
      print("HotlineClient: no connection for transaction.")
      return
    }
    
    print("HotlineClient: waiting on transaction header...")
    c.receive(minimumIncompleteLength: HotlineTransaction.headerSize, maximumLength: HotlineTransaction.headerSize) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let error = error {
        print("HotlineClient: receive error \(error)")
        self.disconnect()
        return
      }
      
      if let data = data, !data.isEmpty {
        print("HotlineClient: received \(data.count) header bytes")
        
        let transaction = self.parseTransaction(data: data)
        if var t = transaction {
          if t.dataSize > 0 {
            c.receive(minimumIncompleteLength: Int(t.dataSize), maximumLength: Int(t.dataSize)) { [weak self] (data, context, isComplete, error) in
              guard let self = self else {
                return
              }
              
              if let data = data, !data.isEmpty {
                t.parameterCount = data.readUInt16(at: 0)!
                
                if t.parameterCount > 0 {
                  t.parameters = []
                  var dataCursor = 2
                  for _ in 0..<t.parameterCount {
                    if
                      let fieldID = data.readUInt16(at: dataCursor),
                      let fieldSize = data.readUInt16(at: dataCursor + 2),
                      let fieldData = data.readData(at: dataCursor + 4, length: Int(fieldSize)) {
                      t.parameters?.append(HotlineTransactionParameter(id: fieldID, dataSize: fieldSize, data: fieldData))
                      
                      dataCursor += 4 + Int(fieldSize)
                    }
                  }
                }
              }
              
              self.processTransaction(t)
            }
          }
          else {
            self.processTransaction(t)
          }
        }
        
//        print("HotlineTracker: server count = \(self.serverCount)")
      }
      
//        self.receiveListing()
//      }
    }
  }
  
  private func processTransaction(_ transaction: HotlineTransaction) {
    print("HotlineClient processing transaction \(transaction.type) with \(transaction.parameterCount) parameters")
  }
    
  private func parseTransaction(data: Data) -> HotlineTransaction? {
    if
      let flags = data.readUInt8(at: 0),
      let isReply = data.readUInt8(at: 1),
      let type = data.readUInt16(at: 2),
      let id = data.readUInt32(at: 4),
      let errorCode = data.readUInt32(at: 8),
      let transactionSize = data.readUInt32(at: 12),
      let dataSize = data.readUInt32(at: 16) {
      
      return HotlineTransaction(
        flags: flags,
        isReply: isReply,
        type: HotlineTransactionType(rawValue: type) ?? HotlineTransactionType.unknown,
        id: id,
        errorCode: errorCode,
        totalSize: transactionSize,
        dataSize: dataSize
      )
    }
    
    return nil
  }
}
