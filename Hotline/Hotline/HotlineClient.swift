import Foundation
import Network

enum HotlineClientStatus: Int {
  case disconnected
  case connecting
  case connected
  case loggingIn
  case loggedIn
}

@Observable
class HotlineClient {
//  static let shared = HotlineClient()
  
  static let handshakePacket = Data([
    0x54, 0x52, 0x54, 0x50, // 'TRTP' protocol ID
    0x48, 0x4F, 0x54, 0x4C, // Sub-protocol ID
    0x00, 0x01, // Version
    0x00, 0x02, // Sub-version
  ])
    
  var connectionStatus: HotlineClientStatus = .disconnected
  var users: [UInt16:HotlineUser] = [:]
  var userList: [HotlineUser] = []
  var chatMessages: [HotlineChat] = []
  var messageBoardMessages: [String] = []
  var fileList: [HotlineFile] = []
  var newsCategories: [HotlineNewsCategory] = []
  
  var userName: String = "bolt"
  var userIconID: UInt16 = 128
  var serverVersion: UInt16 = 151
  var server: HotlineServer?
  
  @ObservationIgnored private var connection: NWConnection?
  @ObservationIgnored private var transactionLog: [UInt32:(HotlineTransactionType, ((HotlineTransaction) -> Void)?)] = [:]
  
  init() {
//    let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
//    print("DOWNLOAD TO: \(downloadsPath)")
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
        self?.reset()
      case .failed(let err):
        print("HotlineClient: connection error \(err)")
        DispatchQueue.main.async {
          self?.connectionStatus = .disconnected
        }
        self?.reset()
      default:
        print("HotlineClient: unhandled connection state \(newState)")
      }
    }
    
    DispatchQueue.main.async {
      self.connectionStatus = .connecting
    }
    self.connection?.start(queue: .global())
  }
  
  func reset() {
    self.transactionLog = [:]
    DispatchQueue.main.async {
      self.chatMessages = []
      self.users = [:]
      self.userList = []
      self.messageBoardMessages = []
      self.fileList = []
      self.newsCategories = []
    }
  }
  
  func disconnect() {
    self.connection?.cancel()
    self.connection = nil
  }
  
  // MARK: -
  
  private func sendTransaction(_ t: HotlineTransaction, autodisconnect disconnectOnError: Bool = true, callback: (() -> Void)? = nil, reply: ((HotlineTransaction) -> Void)? = nil) {
    guard let c = connection else {
      return
    }
    
    print("HotlineClient => \(t.id) \(t.type)")
    
    self.transactionLog[t.id] = (t.type, reply)
    
    c.send(content: t.encoded(), completion: .contentProcessed { [weak self] (error) in
      if disconnectOnError, error != nil {
        self?.disconnect()
        return
      }
      
      callback?()
    })
  }
  
  private func sendTransaction(_ t: HotlineTransaction, autodisconnect disconnectOnError: Bool = true, callback: (() -> Void)? = nil) {
    sendTransaction(t, autodisconnect: disconnectOnError, callback: callback, reply: nil)
  }
  
  private func receiveTransaction() {
    guard let c = connection else {
      print("HotlineClient: no connection for transaction.")
      return
    }
    
    print("HotlineClient ⏳")
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
      
//      print("HotlineClient: received \(headerData.count) header bytes")
      
      if var transaction = self.parseTransaction(data: headerData) {
        // Receive additional data if the transaction has data attached to it.
        print("DATA SIZE: \(transaction.dataSize)")
        if transaction.dataSize > 0 {
          c.receive(minimumIncompleteLength: Int(transaction.dataSize), maximumLength: Int(transaction.dataSize)) { [weak self] (fieldData, context, isComplete, error) in
            guard let self = self else {
              return
            }
            
            guard let fieldData = fieldData, !fieldData.isEmpty else {
              print("HotlineClient: transaction field data is empty!")
              self.disconnect()
              return
            }
            
            let fieldCount = fieldData.readUInt16(at: 0)!
            
            if fieldCount > 0 {
              var dataCursor = 2
              for _ in 0..<fieldCount {
                if
                  let fieldID = fieldData.readUInt16(at: dataCursor),
                  let fieldSize = fieldData.readUInt16(at: dataCursor + 2),
                  let fieldRemainingData = fieldData.readData(at: dataCursor + 4, length: Int(fieldSize)) {
                  
                  if let fieldType = HotlineTransactionFieldType(rawValue: fieldID) {
                    
                    transaction.fields.append(HotlineTransactionField(type: fieldType, dataSize: fieldSize, data: fieldRemainingData))
//                    transaction.parameters[fieldType] = HotlineTransactionField(type: fieldType, dataSize: fieldSize, data: fieldData)
                  }
                  else {
                    print("HotlineClient: UNKNOWN FIELD TYPE!", fieldID, fieldSize)
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
      
      if let transactionType = HotlineTransactionType(rawValue: type) {
        return HotlineTransaction(type: transactionType, flags: flags, isReply: isReply, id: id, errorCode: errorCode, totalSize: transactionSize, dataSize: dataSize)
      }
      else {
        print("HotlineClient: Unknown type \(type) parsing with \(dataSize) bytes")
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
        
        print("HotlineClient 🤝")
        self.sendLogin() { [weak self] in
          self?.sendSetClientUserInfo()
          self?.sendGetUserList()
        }
        self.receiveTransaction()
      }
    })
  }
    
  func sendLogin(callback: (() -> Void)? = nil) {
    DispatchQueue.main.async {
      self.connectionStatus = .loggingIn
    }
    
    var t = HotlineTransaction(type: .login)
    t.setFieldEncodedString(type: .userLogin, val: "")
    t.setFieldEncodedString(type: .userPassword, val: "")
    t.setFieldUInt16(type: .userIconID, val: self.userIconID)
    t.setFieldString(type: .userName, val: self.userName)
    t.setFieldUInt32(type: .versionNumber, val: 123)
    
    self.sendTransaction(t) { [weak self] in
      DispatchQueue.main.async {
        self?.connectionStatus = .loggedIn
      }
      
      callback?()
    }
  }
  
  func sendSetClientUserInfo(callback: (() -> Void)? = nil) {
    var t = HotlineTransaction(type: .setClientUserInfo)
    t.setFieldString(type: .userName, val: self.userName)
    t.setFieldUInt16(type: .userIconID, val: self.userIconID)
    
    self.sendTransaction(t, callback: callback)
  }
  
  func sendAgree(callback: (() -> Void)? = nil) {
    var t = HotlineTransaction(type: .agreed)
    t.setFieldString(type: .userName, val: self.userName)
    t.setFieldUInt16(type: .userIconID, val: self.userIconID)
    t.setFieldUInt32(type: .options, val: 0)
    self.sendTransaction(t, callback: callback)
  }
  
  func sendChat(message: String, callback: (() -> Void)? = nil) {
    var t = HotlineTransaction(type: .sendChat)
    t.setFieldString(type: .data, val: message)
    self.sendTransaction(t, callback: callback)
  }
  
  func sendGetUserList(callback: (() -> Void)? = nil) {
    let t = HotlineTransaction(type: .getUserNameList)
    self.sendTransaction(t, callback: callback)
  }
  
  func sendGetMessageBoard(callback: (() -> Void)? = nil) {
    let t = HotlineTransaction(type: .getMessages)
    self.sendTransaction(t, callback: callback)
  }
  
  func sendGetNewsCategories(callback: (() -> Void)? = nil) {
    let t = HotlineTransaction(type: .getNewsCategoryNameList)
    self.sendTransaction(t, callback: callback)
  }
  
  func sendGetNewsArticles(path: [String]? = nil, callback: (() -> Void)? = nil) {
    var t = HotlineTransaction(type: .getNewsArticleNameList)
    if path != nil {
      t.setFieldPath(type: .newsPath, val: path!)
    }
    self.sendTransaction(t, callback: callback)
  }
  
  func sendGetFileList(path: [String] = [], callback: (() -> Void)? = nil, reply: (([HotlineFile]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getFileNameList)
    var parentFile: HotlineFile? = nil
    
    if !path.isEmpty {
      t.setFieldPath(type: .filePath, val: path)
      parentFile = self.findFile(in: self.fileList, at: path)
    }
    
    
    
//    if let p = path {
//      t.setFieldString(type: .filePath)
//    }
    self.sendTransaction(t, callback: callback, reply: { r in
      var files: [HotlineFile] = []
      for fi in r.getFieldList(type: .fileNameWithInfo) {
        var file = fi.getFile()
        file.path = path + [file.name]
        files.append(file)
      }
      
      DispatchQueue.main.async {
        if var pf = parentFile {
          pf.files = files
        }
        else {
          self.fileList = files
        }
        reply?(files)
      }
    })
  }
  
  func findFile(in filesToSearch: [HotlineFile], at path: [String]) -> HotlineFile? {
    guard !path.isEmpty, !filesToSearch.isEmpty else { return nil }
    
//    var stack: [([HotlineFile], [String])] = [(self.files!, path)]
    
    let currentName = path[0]
    
    for file in filesToSearch {
      if file.name == currentName {
        if path.count == 1 {
          return file
        }
        else if let subfiles = file.files {
          let remainingPath = Array(path[1...])
          return self.findFile(in: subfiles, at: remainingPath)
        }
      }
    }
    
    return nil
  }
  
//  func sendGetNews(callback: (() -> Void)? = nil) {
//    let t = HotlineTransaction(type: .getNewsFile)
//    self.sendTransaction(t, callback: callback)
//  }
  
  // MARK: - Incoming
  
  private func processReply(_ transaction: HotlineTransaction) {
    guard transaction.errorCode == 0 else {
      if let errorParam = transaction.getField(type: .errorText), let errorText = errorParam.getString() {
        print("HotlineClient 😵 \(transaction.errorCode): \(errorText)")
      }
      else {
        print("HotlineClient 😵 \(transaction.errorCode)")
      }
      return
    }
    
    guard let repliedTransactionType = self.transactionLog[transaction.id] else {
      return
    }
    
    defer {
      let replyCallback = repliedTransactionType.1
      DispatchQueue.main.async {
        replyCallback?(transaction)
      }
    }
    
    self.transactionLog[transaction.id] = nil
    
    print("HotlineClient reply in response to \(repliedTransactionType)")
    
    switch(repliedTransactionType.0) {
    case .login:
      print("GOT REPLY TO LOGIN!")
      
      if
        let serverVersionField = transaction.getField(type: .versionNumber),
        let serverVersion = serverVersionField.getUInt16() {
        self.serverVersion = serverVersion
        print("SERVER VERSION: \(serverVersion)")
      }
    case .getUserNameList:
      print("GOT USER LIST")
      var newUsers: [UInt16:HotlineUser] = [:]
      var newUserList: [HotlineUser] = []
      for u in transaction.getFieldList(type: .userNameWithInfo) {
        let user = u.getUser()
        newUsers[user.id] = user
        newUserList.append(user)
      }
      DispatchQueue.main.async {
        self.users = newUsers
        self.userList = newUserList
        
        print("HotlineClient got users:\n")
        print("\(self.userList)\n\n")
      }
    case .getMessages:
      if let textField = transaction.getField(type: .data), let text = textField.getString() {
        var messages: [String] = []
        let messageBoardRegex = /([\s\r\n]*[_\-]+[\s\r\n]+)/
        let matches = text.matches(of: messageBoardRegex)
        var start = text.startIndex
        
        if matches.count > 0 {
          for match in matches {
            let range = match.range
            messages.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
          }
        }
        else {
          messages.append(text)
        }
        
        DispatchQueue.main.async {
          self.messageBoardMessages = messages
        }
      }
//    case .getFileNameList:
//      var files: [HotlineFile] = []
//      for fi in transaction.getFieldList(type: .fileNameWithInfo) {
//        let file = fi.getFile()
//        files.append(file)
//      }
//      DispatchQueue.main.async {
//        self.fileList = files
//      }
    case .getNewsCategoryNameList:
      var categories: [HotlineNewsCategory] = []
      for fi in transaction.getFieldList(type: .newsCategoryListData15) {
        let c = fi.getNewsCategory()
        categories.append(c)
        print("CATEGORY: \(c)")
      }
      DispatchQueue.main.async {
        self.newsCategories = categories
      }
    default:
      break
    }
    
    
  }
  
  private func processTransaction(_ transaction: HotlineTransaction) {
    if transaction.type == .reply {
      print("HotlineClient <= \(transaction.type) to \(transaction.id):")
      print(transaction)
    }
    else {
      print("HotlineClient <= \(transaction.type)")
    }
    
    switch(transaction.type) {
    case .reply:
      self.processReply(transaction)
//      print("HotlineClient: Received reply transaction: \(transaction)")
      
    case .chatMessage:
      print("HotlineClient: chat \(transaction)")
      if
        let chatTextParam = transaction.getField(type: .data),
        let chatText = chatTextParam.getString()
//        let userNameParam = transaction.getField(type: .userName),
//        let userName = userNameParam.getString(),
//        let userIDParam = transaction.getField(type: .userID),
//        let userID = userIDParam.getUInt16() {
      {
        print("HotlineClient: \(chatText)")
          DispatchQueue.main.async {
            self.chatMessages.append(HotlineChat(text: chatText, type: .message))
          }
        }
    case .notifyOfUserChange:
//      print("HotlineClient: user changed")
      if let p = transaction.getField(type: .userName),
         let userName = p.getString() {
        print("HotlineClient: User changed \(userName)")
      }
    case .disconnectMessage:
      print("HotlineClient ❌")
      self.disconnect()
    case .showAgreement:
      if let _ = transaction.getField(type: .noServerAgreement) {
        print("NO AGREEMENT?")
      }
      if let agreementParam = transaction.getField(type: .data) {
        if let agreementText = agreementParam.getString() {
          print("\n\n--------------------------\n")
          print(agreementText)
          print("\n--------------------------\n\n")
          DispatchQueue.main.async {
            self.chatMessages.insert(HotlineChat(text: agreementText, type: .agreement), at: 0)
//            self.agreement = agreementText
          }
//          self.sendAgree() {
//            self.sendGetUserList()
//          }
        }
      }
    case .userAccess:
      print("")
    default:
      print("HotlineClient: UNKNOWN transaction \(transaction.type) with \(transaction.fields.count) parameters")
      print(transaction.fields)
    }
  }
}
