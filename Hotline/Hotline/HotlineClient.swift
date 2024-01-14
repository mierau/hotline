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

private struct HotlineLogin {
  let login: String?
  let password: String?
  let username: String
  let iconID: UInt16
  let callback: ((HotlineTransactionError?, String?, UInt16?) -> Void)?
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

enum HotlineClientStage {
  case handshake
  case packetHeader
  case packetBody
}

class HotlineClient: NetSocketDelegate {
  static let handshakePacket = Data([
    0x54, 0x52, 0x54, 0x50, // 'TRTP' protocol ID
    0x48, 0x4F, 0x54, 0x4C, // Sub-protocol ID
    0x00, 0x01, // Version
    0x00, 0x02, // Sub-version
  ])
  
  static let HandshakePacket: [UInt8] = [
    0x54, 0x52, 0x54, 0x50, // 'TRTP' protocol ID
    0x48, 0x4F, 0x54, 0x4C, // Sub-protocol ID
    0x00, 0x01, // Version
    0x00, 0x02, // Sub-version
  ]
  
  weak var delegate: HotlineClientDelegate?
  
  var connectionStatus: HotlineClientStatus = .disconnected
  var connectCallback: ((Bool) -> Void)?
  
  private var serverAddress: String? = nil
  private var serverPort: UInt16? = nil
  
//  private var connection: NWConnection?
  private var transactionLog: [UInt32:(HotlineTransactionType, ((HotlineTransaction, HotlineTransactionError?) -> Void)?)] = [:]
  
  private var socket: NetSocket?
  private var stage: HotlineClientStage = .handshake
  private var packet: HotlineTransaction? = nil
  private var loginDetails: HotlineLogin? = nil
    
  init() {}
  
  // MARK: - NetSocket Delegate
  
  @MainActor func netsocketConnected(socket: NetSocket) {
    self.updateConnectionStatus(.loggingIn)
    self.stage = .handshake
  }
  
  @MainActor func netsocketDisconnected(socket: NetSocket, error: Error?) {
    self.updateConnectionStatus(.disconnected)
    self.stage = .handshake
  }
  
  @MainActor func netsocketReceived(socket: NetSocket, bytes: [UInt8]) {
    switch self.stage {
    case .handshake:
      self.receiveHandshake()
    case .packetHeader:
      self.receivePacket()
    case .packetBody:
      self.receivePacket()
    }
  }
  
  // MARK: - Connect
  
  @MainActor func login(address: String, port: Int, login: String?, password: String?, username: String, iconID: UInt16, callback: ((HotlineTransactionError?, String?, UInt16?) -> Void)?) {
    if self.socket != nil {
      self.socket?.delegate = nil
      self.socket?.close()
      self.socket = nil
    }
    self.packet = nil
    
    self.loginDetails = HotlineLogin(login: login, password: password, username: username, iconID: iconID, callback: callback)
    
    self.socket = NetSocket()
    self.socket?.delegate = self
    
    self.updateConnectionStatus(.connecting)
    self.socket?.connect(host: address, port: port)
    self.socket?.write(HotlineClient.HandshakePacket)
  }
  
  @MainActor func receiveHandshake() {
    guard let socket = self.socket,
          self.stage == .handshake,
          socket.available >= 8 else {
      return
    }
    
    var handshake: [UInt8] = socket.read(count: 8)
    
    // Verify handshake data
    guard let protocolID = handshake.consumeUInt32(),
          protocolID == "TRTP".fourCharCode() else {
      // TODO: Close with appropriate error
      socket.close()
      return
    }
    
    // Check for error code
    guard let errorCode = handshake.consumeUInt32(),
          errorCode == 0 else {
      // TODO: Close with wrapped error
      socket.close()
      return
    }
    
    self.stage = .packetHeader
    
    let session = self.loginDetails!
    self.loginDetails = nil
    self.sendLogin(login: session.login ?? "", password: session.password ?? "", username: session.username, iconID: session.iconID) { err, serverName, serverVersion in
      session.callback?(err, serverName, serverVersion)
    }
    
    self.receivePacket()
  }
  
  @MainActor func disconnect() {
    self.transactionLog = [:]
    
    self.packet = nil
    
    self.socket?.close()
    self.socket?.delegate = nil
    self.socket = nil
  }
  
  // MARK: - Packets
  
  @MainActor private func sendPacket(_ t: HotlineTransaction, callback: ((HotlineTransaction, HotlineTransactionError?) -> Void)? = nil) {
    guard let socket = self.socket else {
      return
    }
    
    print("HotlineClient => \(t.id) \(t.type)")
    
    if callback != nil {
      self.transactionLog[t.id] = (t.type, callback)
    }
    
    socket.write(t.encoded())
  }
  
  @MainActor private func receivePacket() {
    guard let socket = self.socket else {
      return
    }
    
    var done: Bool = false
    repeat {
      switch self.stage {
      case .packetHeader:
        guard socket.has(HotlineTransaction.headerSize) else {
          done = true
          break
        }
        
        let headerData: [UInt8] = socket.read(count: HotlineTransaction.headerSize)
        guard let packet = HotlineTransaction(from: headerData) else {
          done = true
          break
        }
        
        self.packet = packet
        if packet.dataSize == 0 {
          self.stage = .packetHeader
          self.processPacket()
        }
        else {
          self.stage = .packetBody
        }
        
      case .packetBody:
        guard let packet = self.packet, socket.has(Int(packet.dataSize)) else {
          done = true
          break
        }
        
        let bodyData: [UInt8] = socket.read(count: Int(packet.dataSize))
        self.packet?.decodeFields(from: bodyData)
        self.stage = .packetHeader
        self.processPacket()
        
      default:
        done = true
        break
      }
    } while !done
  }
  
  @MainActor private func processPacket() {
    guard let packet = self.packet else {
      return
    }
    
    if packet.type == .reply || packet.isReply == 1 {
      print("HotlineClient <= \(packet.type) to \(packet.id):")
    }
    else {
      print("HotlineClient <= \(packet.type) \(packet.id)")
    }
    
    if packet.isReply == 1 || packet.type == .reply {
      self.processReplyPacket()
      return
    }
    
    // Mark packet is processed
    self.packet = nil
    
    switch(packet.type) {
    case .chatMessage:
      if
        let chatTextParam = packet.getField(type: .data),
        let chatText = chatTextParam.getString()
      {
        print("HotlineClient: \(chatText)")
        self.delegate?.hotlineReceivedChatMessage(message: chatText)
      }
      
    case .notifyOfUserChange:
      if let usernameField = packet.getField(type: .userName),
         let username = usernameField.getString(),
         let userIDField = packet.getField(type: .userID),
         let userID = userIDField.getUInt16(),
         let userIconIDField = packet.getField(type: .userIconID),
         let userIconID = userIconIDField.getUInt16(),
         let userFlagsField = packet.getField(type: .userFlags),
         let userFlags = userFlagsField.getUInt16() {
        print("HotlineClient: User changed \(username) icon: \(userIconID)")
        
        let user = HotlineUser(id: userID, iconID: userIconID, status: userFlags, name: username)
        self.delegate?.hotlineUserChanged(user: user)
      }
    case .notifyOfUserDelete:
      if let userIDField = packet.getField(type: .userID),
         let userID = userIDField.getUInt16() {
        self.delegate?.hotlineUserDisconnected(userID: userID)
      }
      
    case .disconnectMessage:
      // Server disconnected us.
      print("HotlineClient ❌")
      self.disconnect()
    
    case .serverMessage:
      if let messageField = packet.getField(type: .data),
         let message = messageField.getString() {
        self.delegate?.hotlineReceivedServerMessage(message: message)
      }
      
    case .showAgreement:
      if let _ = packet.getField(type: .noServerAgreement) {
        // Server told us there is no agreement to show.
        return
      }
      if let agreementParam = packet.getField(type: .data) {
        if let agreementText = agreementParam.getString() {
          self.delegate?.hotlineReceivedAgreement(text: agreementText)
        }
      }
      
    case .userAccess:
      print("HotlineClient: user access info \(packet.getField(type: .userAccess).debugDescription)")
      if let accessParam = packet.getField(type: .userAccess) {
        if let accessValue = accessParam.getUInt64() {
          let accessOptions = HotlineUserAccessOptions(rawValue: accessValue)
          self.delegate?.hotlineReceivedUserAccess(options: accessOptions)
        }
      }
      
    default:
      print("HotlineClient: UNKNOWN transaction \(packet.type) with \(packet.fields.count) parameters")
      print(packet.fields)
    }
  }
  
  @MainActor private func processReplyPacket() {
    guard let packet = self.packet else {
      return
    }
    
    if packet.errorCode != 0 {
      let errorField: HotlineTransactionField? = packet.getField(type: .errorText)
      print("HotlineClient 😵 \(packet.errorCode): \(errorField?.getString() ?? "")")
    }
    
    guard let replyCallbackInfo = self.transactionLog[packet.id] else {
      print("Hmm, no reply waiting though")
      return
    }
    
    self.transactionLog[packet.id] = nil
    
    print("HotlineClient reply in response to \(replyCallbackInfo.0)")
    
    let replyCallback = replyCallbackInfo.1
    
    guard packet.errorCode == 0 else {
      let errorField: HotlineTransactionField? = packet.getField(type: .errorText)
      print("HotlineClient 😵 \(packet.errorCode): \(errorField?.getString() ?? "")")
      replyCallback?(packet, .error(packet.errorCode, errorField?.getString()))
      return
    }
    
    replyCallback?(packet, nil)
  }
  
  // MARK: - Messages
  
  @MainActor func sendLogin(login: String, password: String, username: String, iconID: UInt16, callback: ((HotlineTransactionError?, String?, UInt16?) -> Void)?) {
    var t = HotlineTransaction(type: .login)
    t.setFieldEncodedString(type: .userLogin, val: login)
    t.setFieldEncodedString(type: .userPassword, val: password)
    t.setFieldUInt16(type: .userIconID, val: iconID)
    t.setFieldString(type: .userName, val: username)
    t.setFieldUInt32(type: .versionNumber, val: 123)
      
    self.sendPacket(t) { [weak self] reply, err in
      self?.updateConnectionStatus(.loggedIn)
      
      var serverVersion: UInt16?
      var serverName: String?
      
      if
        let serverVersionField = reply.getField(type: .versionNumber),
        let serverVersionValue = serverVersionField.getUInt16() {
        serverVersion = serverVersionValue
        print("SERVER VERSION: \(serverVersionValue)")
      }
      
      if
        let serverNameField = reply.getField(type: .serverName),
        let serverNameValue = serverNameField.getString() {
        serverName = serverNameValue
        print("SERVER NAME: \(serverNameValue)")
      }
      
      callback?(err, serverName, serverVersion)
    }
  }
  
  @MainActor func sendSetClientUserInfo(username: String, iconID: UInt16, options: HotlineUserOptions = [], autoresponse: String? = nil) {
    var t = HotlineTransaction(type: .setClientUserInfo)
    t.setFieldString(type: .userName, val: username)
    t.setFieldUInt16(type: .userIconID, val: iconID)
    t.setFieldUInt16(type: .options, val: options.rawValue)
    if let text = autoresponse {
      t.setFieldString(type: .automaticResponse, val: text)
    }
    
    self.sendPacket(t)
  }
  
  @MainActor func sendAgree(username: String, iconID: UInt16, options: HotlineUserOptions) {
    let t = HotlineTransaction(type: .agreed)
//    t.setFieldString(type: .userName, val: username)
//    t.setFieldUInt16(type: .userIconID, val: iconID)
//    t.setFieldUInt8(type: .options, val: options.rawValue)
    self.sendPacket(t)
  }
  
  @MainActor func sendChat(message: String, encoding: String.Encoding = .utf8) {
    var t = HotlineTransaction(type: .sendChat)
    t.setFieldString(type: .data, val: message, encoding: encoding)
    self.sendPacket(t)
  }
  
  @MainActor func sendGetUserList() {
    let t = HotlineTransaction(type: .getUserNameList)
    self.sendPacket(t) { [weak self] reply, err in
      var newUsers: [UInt16:HotlineUser] = [:]
      var newUserList: [HotlineUser] = []
      for u in reply.getFieldList(type: .userNameWithInfo) {
        let user = u.getUser()
        newUsers[user.id] = user
        newUserList.append(user)
      }
      self?.delegate?.hotlineReceivedUserList(users: newUserList)
    }
  }
  
  @MainActor func sendGetMessageBoard(callback: ((HotlineTransactionError?, [String]) -> Void)?) {
    let t = HotlineTransaction(type: .getMessageBoard)
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let textField = reply.getField(type: .data),
            let text = textField.getString() else {
        callback?(err, [])
        return
      }
      
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
      
      callback?(err, messages)
    }
  }
  
  @MainActor func sendGetNewsCategories(path: [String] = [], callback: (([HotlineNewsCategory]) -> Void)?) {
    var t = HotlineTransaction(type: .getNewsCategoryNameList)
    if !path.isEmpty {
      t.setFieldPath(type: .newsPath, val: path)
    }
    
    self.sendPacket(t) { reply, err in
      var categories: [HotlineNewsCategory] = []
      for categoryListItem in reply.getFieldList(type: .newsCategoryListData15) {
        var c = categoryListItem.getNewsCategory()
        c.path = path + [c.name]
        categories.append(c)
      }
      callback?(categories)
    }
  }
  
  @MainActor func sendGetNewsArticle(id articleID: UInt32, path: [String], flavor: String, callback: ((String?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getNewsArticleData)
    t.setFieldPath(type: .newsPath, val: path)
    t.setFieldUInt32(type: .newsArticleID, val: articleID)
    t.setFieldString(type: .newsArticleDataFlavor, val: flavor, encoding: .ascii)
    
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let articleData = reply.getField(type: .newsArticleData),
            let articleString = articleData.getString() else {
        callback?(nil)
        return
      }
      
      callback?(articleString)
    }
  }
  
  @MainActor func postNewsArticle(title: String, text: String, path: [String] = [], parentID: UInt32? = nil, callback: (([HotlineNewsArticle]) -> Void)? = nil) {
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
    
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let articleData = reply.getField(type: .newsArticleListData) else {
        callback?([])
        return
      }
      
      var articles: [HotlineNewsArticle] = []
      let newsList = articleData.getNewsList()
      for art in newsList.articles {
        var blah = art
        blah.path = path
        articles.append(blah)
      }
      
      callback?(articles)
    }
  }
  
  @MainActor func sendGetNewsArticles(path: [String] = [], callback: (([HotlineNewsArticle]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getNewsArticleNameList)
    if !path.isEmpty {
      t.setFieldPath(type: .newsPath, val: path)
    }
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let articleData = reply.getField(type: .newsArticleListData) else {
        callback?([])
        return
      }
      
      var articles: [HotlineNewsArticle] = []
      let newsList = articleData.getNewsList()
      for art in newsList.articles {
        var blah = art
        blah.path = path
        articles.append(blah)
      }

      callback?(articles)
    }
  }
  
  @MainActor func sendGetFileList(path: [String] = [], callback: (([HotlineFile]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getFileNameList)
    if !path.isEmpty {
      t.setFieldPath(type: .filePath, val: path)
    }
    
    self.sendPacket(t) { reply, err in
      guard err == nil else {
        callback?([])
        return
      }
      
      var files: [HotlineFile] = []
      for fi in reply.getFieldList(type: .fileNameWithInfo) {
        let file = fi.getFile()
        file.path = path + [file.name]
        files.append(file)
      }
      
      callback?(files)
    }
  }
  
  @MainActor func sendDownloadFile(name fileName: String, path filePath: [String], preview: Bool = false, callback: ((Bool, UInt32?, Int?, Int?, Int?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .downloadFile)
    t.setFieldString(type: .fileName, val: fileName)
    t.setFieldPath(type: .filePath, val: filePath)
    if preview {
      t.setFieldUInt32(type: .fileTransferOptions, val: 2)
    }
    
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let transferSizeField = reply.getField(type: .transferSize),
            let transferSize = transferSizeField.getInteger(),
            let transferReferenceField = reply.getField(type: .referenceNumber),
            let referenceNumber = transferReferenceField.getUInt32(),
            let transferFileSizeField = reply.getField(type: .fileSize),
            let transferFileSize = transferFileSizeField.getInteger() else {
        callback?(false, nil, nil, nil, nil)
        return
      }
    
      let transferWaitingCountField = reply.getField(type: .waitingCount)
      let transferWaitingCount = transferWaitingCountField?.getInteger()
      
      callback?(true, referenceNumber, transferSize, transferFileSize, transferWaitingCount)
    }
  }
  
  @MainActor func sendDownloadBanner(callback: ((Bool, UInt32?, Int?) -> Void)? = nil) {
    let t = HotlineTransaction(type: .downloadBanner)
    
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let transferSizeField = reply.getField(type: .transferSize),
            let transferSize = transferSizeField.getInteger(),
            let transferReferenceField = reply.getField(type: .referenceNumber),
            let referenceNumber = transferReferenceField.getUInt32() else {
        callback?(false, nil, nil)
        return
      }

      callback?(true, referenceNumber, transferSize)
    }
  }
  
  
  // MARK: - Utility

  @MainActor private func updateConnectionStatus(_ status: HotlineClientStatus) {
    self.connectionStatus = status
    self.delegate?.hotlineStatusChanged(status: status)
  }

}
