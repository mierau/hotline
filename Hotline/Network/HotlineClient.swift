import Foundation
import Network

enum HotlineClientStatus: Int {
  case disconnected
  case connecting
  case connected
  case loggingIn
  case loggedIn
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
  @Published var agreement: String?
  @Published var userList: [HotlineUser] = []
  @Published var chatMessages: [String] = []
  
  let userName: String = "bolt"
  let userIconID: UInt32 = 128
  
  var server: HotlineServer?
  var connection: NWConnection?
  
  init() {
    
  }
  
  // MARK: -
  
  func connect(to server: HotlineServer) {
    self.server = server
    
    let serverAddress = NWEndpoint.Host(server.address)
    let serverPort = NWEndpoint.Port(rawValue: server.port)!
    
    let tcpOptions = NWProtocolTCP.Options()
    tcpOptions.enableKeepalive = true
    tcpOptions.keepaliveInterval = 30
    let connectionParameters: NWParameters
    connectionParameters = NWParameters(tls: nil, tcp: tcpOptions)
    
    self.connection = NWConnection(host: serverAddress, port: serverPort, using: connectionParameters)
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
    self.connection?.cancel()
    self.connection = nil
    
    DispatchQueue.main.async {
      self.connectionStatus = .disconnected
    }
  }
  
  // MARK: -
  
  private func sendTransaction(_ t: HotlineTransaction, autodisconnect disconnectOnError: Bool = true, callback: (() -> Void)? = nil) {
    guard let c = connection else {
      return
    }
    
    c.send(content: t.encoded(), completion: .contentProcessed { [weak self] (error) in
      if disconnectOnError, error != nil {
        self?.disconnect()
        return
      }
      
      callback?()
    })
  }
  
  private func receiveTransaction() {
    guard let c = connection else {
      print("HotlineClient: no connection for transaction.")
      return
    }
    
    print("HotlineClient: waiting for transaction...")
    c.receive(minimumIncompleteLength: HotlineTransaction.headerSize, maximumLength: HotlineTransaction.headerSize) { [weak self] (headerData, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let error = error {
        print("HotlineClient: transaction error \(error)")
        self.disconnect()
        return
      }
      
      guard let headerData = headerData, !headerData.isEmpty else {
        self.receiveTransaction()
        return
      }
      
      print("HotlineClient: received \(headerData.count) header bytes")
      
      if var transaction = self.parseTransaction(data: headerData) {
        // Receive additional data if the transaction has data attached to it.
        print("DATA SIZE: \(transaction.dataSize)")
        if transaction.dataSize > 0 {
          c.receive(minimumIncompleteLength: Int(transaction.dataSize), maximumLength: Int(transaction.dataSize)) { [weak self] (parameterData, context, isComplete, error) in
            guard let self = self else {
              return
            }
            
            guard let parameterData = parameterData, !parameterData.isEmpty else {
              print("HotlineClient: transaction parameter data is empty!")
              self.disconnect()
              return
            }
            
            let parameterCount = parameterData.readUInt16(at: 0)!
            
            if parameterCount > 0 {
              var dataCursor = 2
              for _ in 0..<parameterCount {
                if
                  let fieldID = parameterData.readUInt16(at: dataCursor),
                  let fieldSize = parameterData.readUInt16(at: dataCursor + 2),
                  let fieldData = parameterData.readData(at: dataCursor + 4, length: Int(fieldSize)) {
                  
                  if let fieldType = HotlineTransactionFieldType(rawValue: fieldID) {
                    transaction.parameters.append(HotlineTransactionParameter(type: fieldType, dataSize: fieldSize, data: fieldData))
//                    transaction.parameters[fieldType] = HotlineTransactionParameter(type: fieldType, dataSize: fieldSize, data: fieldData)
                  }
                  else {
                    print("HotlineClient: UNKNOWN PARAM TYPE!", fieldID, fieldSize)
                  }
                  
                  dataCursor += 4 + Int(fieldSize)
                }
              }
              
              // Process the transaction if we have processed more than zero parameters here
              // as we expect parameters at this point.
              self.processTransaction(transaction)
            }
            
            // Continue receiving transactions.
            self.receiveTransaction()
          }
        }
        else {
          // In this case we have no further data to receive so we simply
          // process the transaction and then continue receiving.
          self.processTransaction(transaction)
          self.receiveTransaction()
        }
      }
      else {
        // Here we failed to parse the current transaction.
        // We should consider disconnecting perhaps.
        // But for now we'll continue receiving.
        self.receiveTransaction()
      }
    }
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
      
      print("HotlineClient: Parsing transaction type \(type) with data \(dataSize)")
      if let transactionType = HotlineTransactionType(rawValue: type) {
        return HotlineTransaction(type: transactionType, flags: flags, isReply: isReply, id: id, errorCode: errorCode, totalSize: transactionSize, dataSize: dataSize)
      }
    }
    
    return nil
  }
  
  // MARK: - Messages
  
  private func sendHandshake() {
    guard let c = connection else {
      print("HotlineClient: invalid connection to send handshake.")
      return
    }
    
    c.send(content: HotlineClient.handshakePacket, completion: .contentProcessed { [weak self] (error) in
      if let err = error {
        print("HotlineClient: sending handshake failed \(err)")
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
        self.receiveTransaction()
      }
    })
  }
    
  func sendLogin(callback: (() -> Void)? = nil) {
    DispatchQueue.main.async {
      self.connectionStatus = .loggingIn
    }
    
    var t = HotlineTransaction(type: .login)
    t.setParameterEncodedString(type: .userLogin, val: "")
    t.setParameterEncodedString(type: .userPassword, val: "")
    t.setParameterUInt32(type: .userIconID, val: self.userIconID)
    t.setParameterString(type: .userName, val: self.userName)
    t.setParameterUInt32(type: .versionNumber, val: 151)
    
    print("HotlineClient: logging in...")
    self.sendTransaction(t) { [weak self] in
      print("HotlineClient: logged in!")
      DispatchQueue.main.async {
        self?.connectionStatus = .loggedIn
      }
      
      callback?()
    }
  }
  
  func sendAgree(callback: (() -> Void)? = nil) {
    var t = HotlineTransaction(type: .agreed)
    t.setParameterString(type: .userName, val: self.userName)
    t.setParameterUInt32(type: .userIconID, val: self.userIconID)
    t.setParameterUInt32(type: .options, val: 0)
    
    print("HotlineClient: agreeing")
    self.sendTransaction(t, callback: callback)
  }
  
  func sendChat(message: String, callback: (() -> Void)? = nil) {
    var t = HotlineTransaction(type: .sendChat)
    t.setParameterString(type: .data, val: message)
    
    print("HotlineClient: sending chat...")
    self.sendTransaction(t, callback: callback)
  }
  
  func sendGetUserList(callback: (() -> Void)? = nil) {
    let t = HotlineTransaction(type: .getUserNameList)
    print("HotlineClient: fetching user list...")
    self.sendTransaction(t, callback: callback)
  }
  
  // MARK: - Incoming
  
  private func processTransaction(_ transaction: HotlineTransaction) {
    switch(transaction.type) {
    case .reply:
      print("HotlineClient: GOT REPLY TRANSACTION? \(transaction)")
    case .chatMessage:
      print("HotlineClient: CHAT MESSAGE!")
      if 
        let chatTextParam = transaction.getParameter(type: .data),
        let chatText = chatTextParam.getString(),
        let userNameParam = transaction.getParameter(type: .userName),
        let userName = userNameParam.getString(),
        let userIDParam = transaction.getParameter(type: .userID),
        let userID = userIDParam.getUInt16() {
        print("HotlineClient: \(userName):\(userID): \(chatText)")
          DispatchQueue.main.async {
            self.chatMessages.append(chatText)
          }
        }
    case .getUserNameList:
      print("HotlineClient: GOT USER NAME LIST!")
      let userList = transaction.getParameterList(type: .userInfo)
      for u in userList {
        let userInfo = u.getUserInfo()
        print("HotlineClient: user \(userInfo.userName)")
      }
    case .notifyOfUserChange:
      print("HotlineClient: user changed")
      if let p = transaction.getParameter(type: .userName),
         let userName = p.getString() {
        print("HotlineClient: user name \(userName)")
      }
    case .disconnectMessage:
      print("HotlineClient: DISCONNECTED BY SERVER!")
      self.disconnect()
    case .showAgreement:
      if let agreementParam = transaction.getParameter(type: .data) {
        if let agreementText = agreementParam.getString() {
          print("AGREEMENT:", agreementText)
          DispatchQueue.main.async {
            self.agreement = agreementText
          }
          self.sendAgree() {
//            self.sendGetUserList()
          }
        }
      }
    case .userAccess:
      print("HotlineClient: user access transaction.")
    default:
      print("HotlineClient: UNKNOWN transaction \(transaction.type) with \(transaction.parameters.count) parameters")
      print(transaction.parameters)
    }
  }
}
