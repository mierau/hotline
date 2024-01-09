import Foundation
import Network

enum HotlineClientStatus: Int {
  case disconnected
  case connecting
  case connected
  case loggingIn
  case loggedIn
}

enum HotlineTransactionError: Error {
  case networkFailure
  case timeout
  case error(UInt32, String?)
  case invalidMessage(UInt32, String?)
}

struct HotlineTransactionInfo {
  let type: HotlineTransactionType
  let callback: ((HotlineTransaction) -> Void)?
  let reply: ((HotlineTransaction) -> Void)?
}

protocol HotlineClientDelegate: AnyObject {
  func hotlineGetUserInfo() -> (String, UInt16)
  func hotlineStatusChanged(status: HotlineClientStatus)
  func hotlineReceivedAgreement(text: String)
  func hotlineReceivedChatMessage(message: String)
  func hotlineReceivedUserList(users: [HotlineUser])
  func hotlineReceivedServerMessage(message: String)
  func hotlineReceivedUserAccess(options: HotlineUserAccessOptions)
  func hotlineUserChanged(user: HotlineUser)
  func hotlineUserDisconnected(userID: UInt16)
}

extension HotlineClientDelegate {
  func hotlineStatusChanged(status: HotlineClientStatus) {}
  func hotlineReceivedAgreement(text: String) {}
  func hotlineReceivedChatMessage(message: String) {}
  func hotlineReceivedUserList(users: [HotlineUser]) {}
  func hotlineReceivedServerMessage(message: String) {}
  func hotlineReceivedUserAccess(options: HotlineUserAccessOptions) {}
  func hotlineUserChanged(user: HotlineUser) {}
  func hotlineUserDisconnected(userID: UInt16) {}
}

class HotlineClient {
  static let handshakePacket = Data([
    0x54, 0x52, 0x54, 0x50, // 'TRTP' protocol ID
    0x48, 0x4F, 0x54, 0x4C, // Sub-protocol ID
    0x00, 0x01, // Version
    0x00, 0x02, // Sub-version
  ])
  
  weak var delegate: HotlineClientDelegate?
  
  var connectionStatus: HotlineClientStatus = .disconnected
  var connectCallback: ((Bool) -> Void)?
  
  private var serverAddress: String? = nil
  private var serverPort: UInt16? = nil
  
  private var connection: NWConnection?
  private var transactionLog: [UInt32:(HotlineTransactionType, ((HotlineTransaction, HotlineTransactionError?) -> Void)?)] = [:]
  
  init() {
    //    let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    //    print("DOWNLOAD TO: \(downloadsPath)")
  }
  
  // MARK: -
  
  func login(_ address: String, port: UInt16, login: String?, password: String?, username: String, iconID: UInt16, callback: ((HotlineTransactionError?, String?, UInt16?) -> Void)?) {
    print("AWAITING CONNECT")
    self.connect(address: address, port: port) { [weak self] success in
      guard success else {
        DispatchQueue.main.async {
          callback?(.networkFailure, nil, nil)
        }
        return
      }
      
      print("AWAITING HANDSHAKE")
      self?.sendHandshake() { [weak self] success in
        guard success else {
          DispatchQueue.main.async {
            callback?(.networkFailure, nil, nil)
          }
          return
        }
        
        print("AWAITING LOGIN \(login ?? "empty login")  \(password ?? "empty pass")")
        self?.sendLogin(login: login ?? "", password: password ?? "", username: username, iconID: iconID) { err, serverName, serverVersion in
//          guard err == nil else {
//            DispatchQueue.main.async {
//              callback?(err, nil, nil)
//            }
//            return
//          }
          
          print("LOGGED INTO SERVER: \(String(describing: serverName?.debugDescription)) \(serverVersion.debugDescription)")
          
          DispatchQueue.main.async {
            callback?(err, serverName, serverVersion)
          }
          
        }
      }
    }
  }
  
  private func connect(address: String, port: UInt16, callback: ((Bool) -> Void)?) {
    self.serverAddress = address
    self.serverPort = port
    
    let tcpOptions = NWProtocolTCP.Options()
    tcpOptions.enableKeepalive = true
//    tcpOptions.enableFastOpen = true
//    tcpOptions.keepaliveInterval = 30
//    tcpOptions.connectionTimeout = 30
    let connectionParameters: NWParameters
    connectionParameters = NWParameters(tls: nil, tcp: tcpOptions)
    
    self.connectCallback = callback
    
    self.connection = NWConnection(host: NWEndpoint.Host(address), port: NWEndpoint.Port(rawValue: port)!, using: connectionParameters)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      guard let self = self else {
        return
      }
      
      switch newState {
      case .ready:
        print("HotlineClient: connection ready!")
        self.updateConnectionStatus(.connected)
        self.connectCallback?(true)
        self.connectCallback = nil
//      case .waiting(let err):
//        print("HotlineClient: connection waiting \(err)...")
//        switch err {
//        case .posix(let errCode):
//          print("HotlineClient: posix error code \(errCode)")
//          self.disconnect()
//        case .tls(let errStatus):
//          print("HotlineClient: tls error code \(errStatus)")
//          self.disconnect()
//        case .dns(let errType):
//          print("HotlineClient: DNS Error code \(errType)")
//          self.disconnect()
//        default:
//          print("HotlineClient: error code \(err)")
//        }
      case .cancelled:
        print("HotlineClient: connection cancelled")
        self.updateConnectionStatus(.disconnected)
        self.reset()
        self.connectCallback?(false)
        self.connectCallback = nil
      case .failed(let err):
        print("HotlineClient: connection error \(err)")
        self.updateConnectionStatus(.disconnected)
        self.reset()
        self.connectCallback?(false)
        self.connectCallback = nil
      default:
        print("HotlineClient: hmm", newState)
        break
      }
    }
    
    self.updateConnectionStatus(.connecting)
    self.connection?.start(queue: .global())
  }
  
  private func reset() {
    self.transactionLog = [:]
  }
  
  func disconnect() {
    print("DISCONNECT?")
    for (_, replyInfo) in self.transactionLog {
      let replyCallback = replyInfo.1
      replyCallback?(HotlineTransaction(type: replyInfo.0), .networkFailure)
    }
    self.transactionLog = [:]
    
    self.connection?.cancel()
    self.connection = nil
  }
  
  // MARK: -
  
  private func sendTransaction(_ t: HotlineTransaction, sent sentCallback: ((Bool) -> Void)? = nil, reply replyCallback: ((HotlineTransaction, HotlineTransactionError?) -> Void)? = nil) {
    guard let c = connection else {
      print("NO CONNECTION?????")
      sentCallback?(false)
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
    
    c.send(content: HotlineClient.handshakePacket, completion: .contentProcessed { [weak self] (error) in
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
        if protocolID != "TRTP".fourCharCode() {
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
  
  func sendLogin(login: String, password: String, username: String, iconID: UInt16, callback: ((HotlineTransactionError?, String?, UInt16?) -> Void)?) {
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
          callback?(.networkFailure, nil, nil)
        }
      }
    } reply: { [weak self] replyTransaction, err in
      print("GOT LOGIN REPLY")
      self?.updateConnectionStatus(.loggedIn)
      
      var serverVersion: UInt16?
      var serverName: String?
      
      if
        let serverVersionField = replyTransaction.getField(type: .versionNumber),
        let serverVersionValue = serverVersionField.getUInt16() {
        serverVersion = serverVersionValue
        print("SERVER VERSION: \(serverVersionValue)")
      }
      
      if
        let serverNameField = replyTransaction.getField(type: .serverName),
        let serverNameValue = serverNameField.getString() {
        serverName = serverNameValue
        print("SERVER NAME: \(serverNameValue)")
      }
      
      DispatchQueue.main.async {
        callback?(err, serverName, serverVersion)
      }
    }
  }
  
  func sendSetClientUserInfo(username: String, iconID: UInt16, options: HotlineUserOptions = [], autoresponse: String? = nil, sent: ((Bool) -> Void)? = nil) {
    var t = HotlineTransaction(type: .setClientUserInfo)
    t.setFieldString(type: .userName, val: username)
    t.setFieldUInt16(type: .userIconID, val: iconID)
    t.setFieldUInt16(type: .options, val: options.rawValue)
    if let text = autoresponse {
      t.setFieldString(type: .automaticResponse, val: text)
    }
    
    self.sendTransaction(t, sent: sent)
  }
  
  func sendAgree(username: String, iconID: UInt16, options: HotlineUserOptions, sent: ((Bool) -> Void)? = nil) {
    let t = HotlineTransaction(type: .agreed)
//    t.setFieldString(type: .userName, val: username)
//    t.setFieldUInt16(type: .userIconID, val: iconID)
//    t.setFieldUInt8(type: .options, val: options.rawValue)
    self.sendTransaction(t, sent: sent)
  }
  
  func sendChat(message: String, encoding: String.Encoding = .utf8, sent sentCallback: ((Bool) -> Void)?) {
    var t = HotlineTransaction(type: .sendChat)
    t.setFieldString(type: .data, val: message, encoding: encoding)
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
  
  func sendGetNewsCategories(path: [String] = [], sent: ((Bool) -> Void)? = nil, reply: (([HotlineNewsCategory]) -> Void)?) {
    var t = HotlineTransaction(type: .getNewsCategoryNameList)
    if !path.isEmpty {
      t.setFieldPath(type: .newsPath, val: path)
    }
    
    self.sendTransaction(t, sent: sent, reply: { rt, err in
      var categories: [HotlineNewsCategory] = []
      for categoryListItem in rt.getFieldList(type: .newsCategoryListData15) {
        var c = categoryListItem.getNewsCategory()
        c.path = path + [c.name]
        categories.append(c)
        print("CATEGORY: \(c)")
      }
      DispatchQueue.main.async {
        reply?(categories)
      }
    })
  }
  
  func sendGetNewsArticle(id articleID: UInt32, path: [String], flavor: String, sent: ((Bool) -> Void)? = nil, reply: ((String?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getNewsArticleData)
    t.setFieldPath(type: .newsPath, val: path)
    t.setFieldUInt32(type: .newsArticleID, val: articleID)
    t.setFieldString(type: .newsArticleDataFlavor, val: flavor, encoding: .ascii)
    
    self.sendTransaction(t, sent: sent, reply: { r, err in
      if err != nil {
        reply?(nil)
        return
      }
      
      let articleData = r.getField(type: .newsArticleData)
      let articleString = articleData?.getString()
      
      DispatchQueue.main.async {
        reply?(articleString)
      }
    })
  }
  
  func postNewsArticle(title: String, text: String, path: [String] = [], parentID: UInt32? = nil, sent: ((Bool) -> Void)? = nil, reply: (([HotlineNewsArticle]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .postNewsArticle)
    if !path.isEmpty {
      t.setFieldPath(type: .newsPath, val: path)
    }
    if let parentID = parentID {
      t.setFieldUInt32(type: .newsArticleID, val: parentID)
    }
    t.setFieldString(type: .newsArticleTitle, val: title)
    t.setFieldString(type: .newsArticleDataFlavor, val: "text/plain")
    t.setFieldUInt32(type: .newsArticleFlags, val: 0)
    t.setFieldString(type: .newsArticleData, val: text)
    
    self.sendTransaction(t, sent: sent, reply: { r, err in
      if err != nil {
        reply?([])
        return
      }
      
      var articles: [HotlineNewsArticle] = []
//      let articleData = r.getField(type: .newsArticleListData)
      
//      print("ARTICLE DATA?", articleData)
      
      if let articleData = r.getField(type: .newsArticleListData) {
        let newsList = articleData.getNewsList()
        for art in newsList.articles {
          var blah = art
          blah.path = path
          articles.append(blah)
          
          print(blah.title)
        }
      }
      
      DispatchQueue.main.async {
        reply?(articles)
      }
    })
  }
  
  func sendGetNewsArticles(path: [String] = [], sent: ((Bool) -> Void)? = nil, reply: (([HotlineNewsArticle]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getNewsArticleNameList)
    if !path.isEmpty {
      t.setFieldPath(type: .newsPath, val: path)
    }
    self.sendTransaction(t, sent: sent, reply: { r, err in
      if err != nil {
        reply?([])
        return
      }
      
      var articles: [HotlineNewsArticle] = []
//      let articleData = r.getField(type: .newsArticleListData)
      
//      print("ARTICLE DATA?", articleData)
      
      if let articleData = r.getField(type: .newsArticleListData) {
        let newsList = articleData.getNewsList()
        for art in newsList.articles {
          var blah = art
          blah.path = path
          articles.append(blah)
          
          print(blah.title)
        }
      }
      
      DispatchQueue.main.async {
        reply?(articles)
      }
    })
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
  
  func sendDownloadFile(name fileName: String, path filePath: [String], preview: Bool = false, sent: ((Bool) -> Void)? = nil, reply: ((Bool, UInt32?, Int?, Int?, Int?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .downloadFile)
    t.setFieldString(type: .fileName, val: fileName)
    t.setFieldPath(type: .filePath, val: filePath)
    if preview {
      t.setFieldUInt32(type: .fileTransferOptions, val: 2)
    }
    
    print("DOWNLOAD \(fileName) AT PATH \(filePath)")
    
    self.sendTransaction(t, sent: sent, reply: { r, err in
      if err != nil {
        DispatchQueue.main.async {
          reply?(false, nil, nil, nil, nil)
        }
        return
      }
      
      if let transferSizeField = r.getField(type: .transferSize),
         let transferSize = transferSizeField.getInteger(),
         let transferReferenceField = r.getField(type: .referenceNumber),
         let referenceNumber = transferReferenceField.getUInt32(),
         let transferFileSizeField = r.getField(type: .fileSize),
         let transferFileSize = transferFileSizeField.getInteger() {
        
        let transferWaitingCountField = r.getField(type: .waitingCount)
        let transferWaitingCount = transferWaitingCountField?.getInteger()
        
        DispatchQueue.main.async {
          reply?(true, referenceNumber, transferSize, transferFileSize, transferWaitingCount)
        }
      }
      else {
        DispatchQueue.main.async {
          reply?(false, nil, nil, nil, nil)
        }
      }
    })
  }
  
  func sendDownloadBanner(sent: ((Bool) -> Void)? = nil, reply: ((Bool, UInt32?, Int?) -> Void)? = nil) {
    let t = HotlineTransaction(type: .downloadBanner)
    
    self.sendTransaction(t, sent: sent, reply: { r, err in
      if err != nil {
        DispatchQueue.main.async {
          reply?(false, nil, nil)
        }
        return
      }
      
      if let transferSizeField = r.getField(type: .transferSize),
         let transferSize = transferSizeField.getInteger(),
         let transferReferenceField = r.getField(type: .referenceNumber),
         let referenceNumber = transferReferenceField.getUInt32() {
        
        DispatchQueue.main.async {
          reply?(true, referenceNumber, transferSize)
        }
      }
      else {
        DispatchQueue.main.async {
          reply?(false, nil, nil)
        }
      }
    })
  }
  
  //  func sendGetNews(callback: (() -> Void)? = nil) {
  //    let t = HotlineTransaction(type: .getNewsFile)
  //    self.sendTransaction(t, callback: callback)
  //  }
  
  // MARK: - Incoming
  
  private func processReply(_ transaction: HotlineTransaction) {
    if transaction.errorCode != 0 {
      let errorField: HotlineTransactionField? = transaction.getField(type: .errorText)
      print("HotlineClient 😵 \(transaction.errorCode): \(errorField?.getString() ?? "")")
    }
    
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
    
    DispatchQueue.main.async {
      replyCallback?(transaction, nil)
    }
  }
    
  private func processTransaction(_ transaction: HotlineTransaction) {
    if transaction.type == .reply || transaction.isReply == 1 {
      print("HotlineClient <= \(transaction.type) to \(transaction.id):")
      print(transaction)
    }
    else {
      print("HotlineClient <= \(transaction.type) \(transaction.id)")
    }
    
    if transaction.isReply == 1 {
      self.processReply(transaction)
      return
    }
//    if self.transactionLog[transaction.id] != nil {
//      self.processReply(transaction)
//      return
//    }
    
    switch(transaction.type) {
    case .reply:
      self.processReply(transaction)
      
    case .chatMessage:
      print("HotlineClient: chat \(transaction)")
      if
        let chatTextParam = transaction.getField(type: .data),
        let chatText = chatTextParam.getString()
      {
        print("HotlineClient: \(chatText)")
        DispatchQueue.main.async { [weak self] in
          self?.delegate?.hotlineReceivedChatMessage(message: chatText)
        }
      }
      
    case .notifyOfUserChange:
      if let usernameField = transaction.getField(type: .userName),
         let username = usernameField.getString(),
         let userIDField = transaction.getField(type: .userID),
         let userID = userIDField.getUInt16(),
         let userIconIDField = transaction.getField(type: .userIconID),
         let userIconID = userIconIDField.getUInt16(),
         let userFlagsField = transaction.getField(type: .userFlags),
         let userFlags = userFlagsField.getUInt16() {
        print("HotlineClient: User changed \(username) icon: \(userIconID)")
        
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
      // Server disconnected us.
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
        // Server told us there is no agreement to show.
        return
      }
      if let agreementParam = transaction.getField(type: .data) {
        if let agreementText = agreementParam.getString() {
          DispatchQueue.main.async { [weak self] in
            self?.delegate?.hotlineReceivedAgreement(text: agreementText)
          }
        }
      }
      
    case .userAccess:
      print("HotlineClient: user access info \(transaction.getField(type: .userAccess).debugDescription)")
      if let accessParam = transaction.getField(type: .userAccess) {
        if let accessValue = accessParam.getUInt64() {
          let accessOptions = HotlineUserAccessOptions(rawValue: accessValue)
          DispatchQueue.main.async { [weak self] in
            self?.delegate?.hotlineReceivedUserAccess(options: accessOptions)
          }
        }
      }
      
    default:
      print("HotlineClient: UNKNOWN transaction \(transaction.type) with \(transaction.fields.count) parameters")
      print(transaction.fields)
    }
  }
  
  // MARK: - Utility

  private func updateConnectionStatus(_ status: HotlineClientStatus) {
    self.connectionStatus = status
    DispatchQueue.main.async { [weak self] in
      self?.delegate?.hotlineStatusChanged(status: status)
    }
  }

}
