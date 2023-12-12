import Foundation
import Network

enum HotlineNewClientStatus: Int {
  case disconnected
  case connecting
  case connected
  case loggingIn
  case loggedIn
}

enum HotlineTransactionError: Error {
  case networkFailure
  case error(UInt32, String?)
  case invalidMessage(UInt32, String?)
}

//struct HotlineTransactionError {
//  let code: UInt32
//  let message: String
//}

struct HotlineTransactionInfo {
  let type: HotlineTransactionType
  let callback: ((HotlineTransaction) -> Void)?
  let reply: ((HotlineTransaction) -> Void)?
}

//struct HotlineAccount {
//  let username: String
//  let iconID: UInt16
//}

protocol HotlineNewClientDelegate: AnyObject {
  func hotlineGetUserInfo() -> (String, UInt16)
  func hotlineStatusChanged(status: HotlineNewClientStatus)
  func hotlineReceivedAgreement(text: String)
  func hotlineReceivedChatMessage(message: String)
  func hotlineReceivedUserList(users: [HotlineUser])
  func hotlineReceivedServerMessage(message: String)
  func hotlineUserChanged(user: HotlineUser)
  func hotlineUserDisconnected(userID: UInt16)
}

extension HotlineNewClientDelegate {
  func hotlineStatusChanged(status: HotlineNewClientStatus) {}
  func hotlineReceivedAgreement(text: String) {}
  func hotlineReceivedChatMessage(message: String) {}
  func hotlineReceivedUserList(users: [HotlineUser]) {}
  func hotlineReceivedServerMessage(message: String) {}
  func hotlineUserChanged(user: HotlineUser) {}
  func hotlineUserDisconnected(userID: UInt16) {}
}

class HotlineNewClient {
  //  static let shared = HotlineClient()
  
  static let handshakePacket = Data([
    0x54, 0x52, 0x54, 0x50, // 'TRTP' protocol ID
    0x48, 0x4F, 0x54, 0x4C, // Sub-protocol ID
    0x00, 0x01, // Version
    0x00, 0x02, // Sub-version
  ])
  
  weak var delegate: HotlineNewClientDelegate?
  
  var connectionStatus: HotlineNewClientStatus = .disconnected
  var connectCallback: ((Bool) -> Void)?
//  var chatMessages: [HotlineChat] = []
//  var messageBoardMessages: [String] = []
  var fileList: [HotlineFile] = []
  var newsCategories: [HotlineNewsCategory] = []
  
  //  var username: String = "guest"
  //  var iconID: UInt16
  //  var userIconID: UInt16 = 128
  var serverVersion: UInt16 = 151
  //  var server: HotlineServer?
  
  private var connection: NWConnection?
//  private var connectionContinuation: CheckedContinuation<Bool, Never>?
  private var transactionLog: [UInt32:(HotlineTransactionType, ((HotlineTransaction, HotlineTransactionError?) -> Void)?)] = [:]
  
  init() {
    //    let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    //    print("DOWNLOAD TO: \(downloadsPath)")
  }
  
  // MARK: -
  
  func login(_ address: String, port: UInt16, login: String, password: String, username: String, iconID: UInt16, callback: ((HotlineTransactionError?, UInt16) -> Void)?) -> Bool {
    print("AWAITING CONNECT")
    self.connect(address: address, port: port) { [weak self] success in
      guard success else {
        DispatchQueue.main.async {
          callback?(.networkFailure, 0)
        }
        return
      }
      
      print("AWAITING HANDSHAKE")
      self?.sendHandshake() { [weak self] success in
        guard success else {
          DispatchQueue.main.async {
            callback?(.networkFailure, 0)
          }
          return
        }
        
        print("AWAITING LOGIN")
        self?.sendLogin(login: login, password: password, username: username, iconID: iconID) { [weak self] err, serverVersion in
          guard err == nil else {
            DispatchQueue.main.async {
              callback?(err, 0)
            }
            return
          }
          
          self?.serverVersion = serverVersion
          print("SERVER VERSION: \(serverVersion)")
          
          self?.sendSetClientUserInfo(username: username, iconID: iconID)
          self?.sendGetUserList()
          
          DispatchQueue.main.async {
            callback?(nil, serverVersion)
          }
          
        }
      }
    }
    
    return false
  }
  
  private func connect(address: String, port: UInt16, callback: ((Bool) -> Void)?) {
    let serverAddress = NWEndpoint.Host(address)
    let serverPort = NWEndpoint.Port(rawValue: port)!
    
    let tcpOptions = NWProtocolTCP.Options()
    tcpOptions.enableKeepalive = true
    tcpOptions.keepaliveInterval = 30
    let connectionParameters: NWParameters
    connectionParameters = NWParameters(tls: nil, tcp: tcpOptions)
    
    self.connectCallback = callback
    
    self.connection = NWConnection(host: serverAddress, port: serverPort, using: connectionParameters)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      guard let self = self else {
        return
      }
      
      switch newState {
      case .preparing:
        print("HotlineClient: connection preparing...")
      case .setup:
        print("HotlineClient: connection setup")
      case .waiting(let err):
        print("HotlineClient: connection waiting \(err)...")
      case .ready:
        print("HotlineClient: connection ready!")
        self.updateConnectionStatus(.connected)
        self.connectCallback?(true)
        self.connectCallback = nil
//        if self.connectionContinuation != nil {
//          let continuation = self.connectionContinuation!
//          self.connectionContinuation = nil
//          callback?(true)
//          continuation.resume(returning: true)
//        }
//        callback?(true)
      case .failed(let err):
        print("HotlineClient: connection error \(err)")
        self.updateConnectionStatus(.disconnected)
        self.reset()
        self.connectCallback?(false)
        self.connectCallback = nil
//        callback?(false)
//        if self.connectionContinuation != nil {
//          let continuation = self.connectionContinuation!
//          self.connectionContinuation = nil
//          continuation.resume(returning: false)
//        }
      case .cancelled:
        print("HotlineClient: connection cancelled")
        self.updateConnectionStatus(.disconnected)
        self.reset()
        self.connectCallback?(false)
        self.connectCallback = nil
//        callback?(false)
//        if self.connectionContinuation != nil {
//          let continuation = self.connectionContinuation!
//          self.connectionContinuation = nil
//          continuation.resume(returning: false)
//        }
      default:
        break
      }
    }
    
    self.updateConnectionStatus(.connecting)
    self.connection?.start(queue: .global())
    
//    return await withCheckedContinuation { [weak self] continuation in
//      self?.connectionContinuation = continuation
//      self?.connection?.start(queue: .global())
//    }
  }
  
  private func reset() {
    self.transactionLog = [:]
    DispatchQueue.main.async {
//      self.chatMessages = []
//      self.messageBoardMessages = []
      self.fileList = []
      self.newsCategories = []
    }
  }
  
  func disconnect() {
    self.connection?.cancel()
    self.connection = nil
  }
  
  private func updateConnectionStatus(_ status: HotlineNewClientStatus) {
    self.connectionStatus = status
    DispatchQueue.main.async { [weak self] in
      self?.delegate?.hotlineStatusChanged(status: status)
    }
  }
  
  // MARK: -
  
  private func sendTransaction(_ t: HotlineTransaction, sent sentCallback: ((Bool) -> Void)? = nil, reply replyCallback: ((HotlineTransaction, HotlineTransactionError?) -> Void)? = nil) {
    guard let c = connection else {
      return
    }
    
    print("HotlineClient => \(t.id) \(t.type)")
    
    if replyCallback != nil {
      self.transactionLog[t.id] = (t.type, replyCallback)
    }
    
    c.send(content: t.encoded(), completion: .contentProcessed { [weak self] (error) in
      if error != nil {
        sentCallback?(false)
        self?.transactionLog[t.id] = nil
        self?.disconnect()
        return
      }
      
      sentCallback?(true)
    })
  }
  
  private func sendTransaction(_ t: HotlineTransaction, sent sentCallback: ((Bool) -> Void)? = nil) {
    self.sendTransaction(t, sent: sentCallback, reply: nil)
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
  
  private func sendHandshake(callback: ((Bool) -> Void)?) {
    guard let c = self.connection else {
      print("HotlineClient: invalid connection to send handshake.")
      return
    }
    
    c.send(content: HotlineNewClient.handshakePacket, completion: .contentProcessed { [weak self] (error) in
      if let err = error {
        print("HotlineClient: sending handshake failed \(err)")
        callback?(false)
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
          callback?(false)
          return
        }
        
        let protocolID = data.readUInt32(at: 0)!
        if protocolID != 0x54525450 { // 'TRTP'
          print("HotlineClient: invalid handshake protocol ID \(protocolID)")
          self.disconnect()
          callback?(false)
          return
        }
        
        let errorCode = data.readUInt32(at: 4)!
        if errorCode != 0 { // 0 == no error
          print("HotlineClient: handshake error", errorCode)
          self.disconnect()
          callback?(false)
          return
        }
        
        callback?(true)
        print("HotlineClient 🤝")
        self.receiveTransaction()
      }
    })
  }
  
  func sendLogin(login: String, password: String, username: String, iconID: UInt16, callback: ((HotlineTransactionError?, UInt16) -> Void)?) {
    self.updateConnectionStatus(.loggingIn)
    
    var t = HotlineTransaction(type: .login)
    t.setFieldEncodedString(type: .userLogin, val: login)
    t.setFieldEncodedString(type: .userPassword, val: password)
    t.setFieldUInt16(type: .userIconID, val: iconID)
    t.setFieldString(type: .userName, val: username)
    t.setFieldUInt32(type: .versionNumber, val: 123)
      
    self.sendTransaction(t) { success in
      if !success {
        DispatchQueue.main.async {
          callback?(.networkFailure, 0)
        }
      }
    } reply: { [weak self] replyTransaction, err in
      print("GOT LOGIN REPLY")
      self?.updateConnectionStatus(.loggedIn)
      
      var serverVersion: UInt16?
      if
        let serverVersionField = replyTransaction.getField(type: .versionNumber),
        let serverVersionValue = serverVersionField.getUInt16() {
        self?.serverVersion = serverVersionValue
        serverVersion = serverVersionValue
        print("SERVER VERSION: \(serverVersionValue)")
      }
      
      DispatchQueue.main.async {
        callback?(err, serverVersion ?? 0)
      }
    }
  }
  
  func sendSetClientUserInfo(username: String, iconID: UInt16, sent: ((Bool) -> Void)? = nil) {
    var t = HotlineTransaction(type: .setClientUserInfo)
    t.setFieldString(type: .userName, val: username)
    t.setFieldUInt16(type: .userIconID, val: iconID)
    self.sendTransaction(t, sent: sent)
  }
  
  func sendAgree(sent: ((Bool) -> Void)? = nil) {
    var t = HotlineTransaction(type: .agreed)
//    t.setFieldString(type: .userName, val: self.userName)
//    t.setFieldUInt16(type: .userIconID, val: self.userIconID)
    t.setFieldUInt32(type: .options, val: 0)
    self.sendTransaction(t, sent: sent)
  }
  
  func sendChat(message: String, sent sentCallback: ((Bool) -> Void)?) {
    var t = HotlineTransaction(type: .sendChat)
    t.setFieldString(type: .data, val: message)
    self.sendTransaction(t, sent: sentCallback)
  }
  
  func sendGetUserList(sent sentCallback: ((Bool) -> Void)? = nil) {
    print("SENDING GET USER LIST")
    let t = HotlineTransaction(type: .getUserNameList)
    self.sendTransaction(t, sent: sentCallback) { [weak self] replyTransaction, err in
      print("GOT USER LIST")
      var newUsers: [UInt16:HotlineUser] = [:]
      var newUserList: [HotlineUser] = []
      for u in replyTransaction.getFieldList(type: .userNameWithInfo) {
        let user = u.getUser()
        newUsers[user.id] = user
        newUserList.append(user)
      }
      DispatchQueue.main.async { [weak self] in
        self?.delegate?.hotlineReceivedUserList(users: newUserList)
      }
    }
  }
  
  func sendGetMessageBoard(callback: ((HotlineTransactionError?, [String]) -> Void)?) {
    let t = HotlineTransaction(type: .getMessageBoard)
    self.sendTransaction(t) { success in
      if !success {
        DispatchQueue.main.async {
          callback?(.networkFailure, [])
        }
      }
    } reply: { replyTransaction, err in
      if err != nil {
        DispatchQueue.main.async {
          callback?(err, [])
        }
        return
      }
            
      if let textField = replyTransaction.getField(type: .data),
         let text = textField.getString() {
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
          callback?(err, messages)
        }
        
        
        
//          continuation.resume(returning: messages)
//          DispatchQueue.main.async {
//            self.messageBoardMessages = messages
//          }
      }
    }
  }
  
  func sendGetNewsCategories(sent: ((Bool) -> Void)? = nil) {
    let t = HotlineTransaction(type: .getNewsCategoryNameList)
    self.sendTransaction(t, sent: sent)
  }
  
  func sendGetNewsArticles(path: [String]? = nil, sent: ((Bool) -> Void)? = nil, reply: ((String) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getNewsArticleNameList)
    if path != nil {
      t.setFieldPath(type: .newsPath, val: path!)
    }
    self.sendTransaction(t, sent: sent)
  }
  
  func sendGetFileList(path: [String] = [], sent: ((Bool) -> Void)? = nil, reply: (([HotlineFile]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getFileNameList)
    
    if !path.isEmpty {
      t.setFieldPath(type: .filePath, val: path)
    }
    
    self.sendTransaction(t, sent: sent, reply: { r, err in
      if err != nil {
        reply?([])
        return
      }
      
      var files: [HotlineFile] = []
      for fi in r.getFieldList(type: .fileNameWithInfo) {
        let file = fi.getFile()
        file.path = path + [file.name]
        files.append(file)
      }
      
      DispatchQueue.main.async {
        reply?(files)
      }
    })
  }
  
  //  func sendGetNews(callback: (() -> Void)? = nil) {
  //    let t = HotlineTransaction(type: .getNewsFile)
  //    self.sendTransaction(t, callback: callback)
  //  }
  
  // MARK: - Incoming
  
  private func processReply(_ transaction: HotlineTransaction) {
    guard let replyCallbackInfo = self.transactionLog[transaction.id] else {
      return
    }
    
    self.transactionLog[transaction.id] = nil
    
    print("HotlineClient reply in response to \(replyCallbackInfo.0)")
    
//    var replyError: HotlineTransactionError? = nil
    
//    defer {
//      let replyCallback = replyCallbackInfo.1
//      DispatchQueue.main.async {
//        replyCallback?(transaction, replyError)
//      }
//    }
    
    let replyCallback = replyCallbackInfo.1
    
    guard transaction.errorCode == 0 else {
      let errorField: HotlineTransactionField? = transaction.getField(type: .errorText)
      
      print("HotlineClient 😵 \(transaction.errorCode): \(errorField?.getString() ?? "")")
      
      DispatchQueue.main.async {
        replyCallback?(transaction, .error(transaction.errorCode, errorField?.getString()))
      }
      return
    }
    
    replyCallback?(transaction, nil)
    
    
    switch(replyCallbackInfo.0) {
//    case .login:
//      print("GOT REPLY TO LOGIN!")
      
//      if
//        let serverVersionField = transaction.getField(type: .versionNumber),
//        let serverVersion = serverVersionField.getUInt16() {
//        self.serverVersion = serverVersion
//        print("SERVER VERSION: \(serverVersion)")
//      }
//    case .getUserNameList:
//      print("GOT USER LIST")
//      var newUsers: [UInt16:HotlineUser] = [:]
//      var newUserList: [HotlineUser] = []
//      for u in transaction.getFieldList(type: .userNameWithInfo) {
//        let user = u.getUser()
//        newUsers[user.id] = user
//        newUserList.append(user)
//      }
//      DispatchQueue.main.async { [weak self] in
////        self.userList = newUserList
//        
//        self?.delegate?.hotlineReceivedUserList(users: newUserList)
//      }
//    case .getMessageBoard:
//      if let textField = transaction.getField(type: .data), let text = textField.getString() {
//        var messages: [String] = []
//        let messageBoardRegex = /([\s\r\n]*[_\-]+[\s\r\n]+)/
//        let matches = text.matches(of: messageBoardRegex)
//        var start = text.startIndex
//        
//        if matches.count > 0 {
//          for match in matches {
//            let range = match.range
//            messages.append(String(text[start..<range.lowerBound]))
//            start = range.upperBound
//          }
//        }
//        else {
//          messages.append(text)
//        }
//        
//        DispatchQueue.main.async {
//          self.messageBoardMessages = messages
//        }
//      }
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
        DispatchQueue.main.async { [weak self] in
          self?.delegate?.hotlineReceivedChatMessage(message: chatText)
//          self.chatMessages.append(HotlineChat(text: chatText, type: .message))
        }
      }
    case .notifyOfUserChange:
      //      print("HotlineClient: user changed")
      if let usernameField = transaction.getField(type: .userName),
         let username = usernameField.getString(),
         let userIDField = transaction.getField(type: .userID),
         let userID = userIDField.getUInt16(),
         let userIconIDField = transaction.getField(type: .userIconID),
         let userIconID = userIconIDField.getUInt16(),
         let userFlagsField = transaction.getField(type: .userFlags),
         let userFlags = userFlagsField.getUInt16() {
        print("HotlineClient: User changed \(username)")
        
        let user = HotlineUser(id: userID, iconID: userIconID, status: userFlags, name: username)
        
        DispatchQueue.main.async { [weak self] in
          self?.delegate?.hotlineUserChanged(user: user)
        }
      }
    case .notifyOfUserDelete:
      if let userIDField = transaction.getField(type: .userID),
         let userID = userIDField.getUInt16() {
        DispatchQueue.main.async { [weak self] in
          self?.delegate?.hotlineUserDisconnected(userID: userID)
        }
      }
    case .disconnectMessage:
      print("HotlineClient ❌")
      self.disconnect()
    case .serverMessage:
      if let messageField = transaction.getField(type: .data),
         let message = messageField.getString() {
        DispatchQueue.main.async { [weak self] in
          self?.delegate?.hotlineReceivedServerMessage(message: message)
        }
      }
    case .showAgreement:
      if let _ = transaction.getField(type: .noServerAgreement) {
        print("NO AGREEMENT?")
      }
      if let agreementParam = transaction.getField(type: .data) {
        if let agreementText = agreementParam.getString() {
          print("\n\n--------------------------\n")
          print(agreementText)
          print("\n--------------------------\n\n")
          DispatchQueue.main.async { [weak self] in
            self?.delegate?.hotlineReceivedAgreement(text: agreementText)
          }
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
