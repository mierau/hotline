import Foundation
import Network
import RegexBuilder

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
  func hotlineReceivedErrorMessage(code: UInt32, message: String?)
  func hotlineReceivedChatMessage(message: String)
  func hotlineReceivedUserList(users: [HotlineUser])
  func hotlineReceivedServerMessage(message: String)
  func hotlineReceivedPrivateMessage(userID: UInt16, message: String)
  func hotlineReceivedUserAccess(options: HotlineUserAccessOptions)
  func hotlineUserChanged(user: HotlineUser)
  func hotlineUserDisconnected(userID: UInt16)
  func hotlineReceivedNewsPost(message: String)
}

extension HotlineClientDelegate {
  func hotlineStatusChanged(status: HotlineClientStatus) {}
  func hotlineReceivedAgreement(text: String) {}
  func hotlineReceivedErrorMessage(code: UInt32, message: String?) {}
  func hotlineReceivedChatMessage(message: String) {}
  func hotlineReceivedUserList(users: [HotlineUser]) {}
  func hotlineReceivedServerMessage(message: String) {}
  func hotlineReceivedPrivateMessage(userID: UInt16, message: String) {}
  func hotlineReceivedUserAccess(options: HotlineUserAccessOptions) {}
  func hotlineUserChanged(user: HotlineUser) {}
  func hotlineUserDisconnected(userID: UInt16) {}
  func hotlineReceivedNewsPost(message: String) {}
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
  
  private struct TransactionContext {
    let type: HotlineTransactionType
    let callback: ((HotlineTransaction, HotlineTransactionError?) -> Void)?
    let suppressErrors: Bool
  }

  private var transactionLog: [UInt32: TransactionContext] = [:]
  
  private var socket: NetSocket?
  private var stage: HotlineClientStage = .handshake
  private var packet: HotlineTransaction? = nil
  private var serverVersion: UInt16? = nil
  private var loginDetails: HotlineLogin? = nil
  private var keepAliveTimer: Timer? = nil
    
  init() {}
  
  // MARK: - NetSocket Delegate
  
  @MainActor func netsocketConnected(socket: NetSocket) {
    self.updateConnectionStatus(.loggingIn)
    self.stage = .handshake
  }
  
  @MainActor func netsocketDisconnected(socket: NetSocket, error: Error?) {
    self.reset()
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
  
  @MainActor private func startKeepAliveTimer() {
    self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 60 * 3, repeats: true) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        self?.sendKeepAlive()
      }
    }
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
    self.sendLogin(login: session.login ?? "", password: session.password ?? "", username: session.username, iconID: session.iconID) { [weak self] err, serverName, serverVersion in
      self?.serverVersion = serverVersion
      self?.startKeepAliveTimer()
      session.callback?(err, serverName, serverVersion)
    }
    
    self.receivePacket()
  }
  
  @MainActor private func reset() {
    self.transactionLog = [:]
    self.packet = nil
    
    self.keepAliveTimer?.invalidate()
    self.keepAliveTimer = nil
    
    self.socket?.close()
    self.socket?.delegate = nil
    self.socket = nil
  }
  
  @MainActor func disconnect() {
    let wasConnected = self.connectionStatus != .disconnected
    self.reset()
    if wasConnected {
      self.updateConnectionStatus(.disconnected)
    }
  }
  
  // MARK: - Packets
  
  @MainActor private func sendPacket(_ t: HotlineTransaction, suppressErrors: Bool = false, callback: ((HotlineTransaction, HotlineTransactionError?) -> Void)? = nil) {
    guard let socket = self.socket else {
      return
    }
    
    print("HotlineClient => \(t.id) \(t.type)")
    
    if callback != nil || suppressErrors {
      self.transactionLog[t.id] = TransactionContext(type: t.type, callback: callback, suppressErrors: suppressErrors)
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
        print("HotlineClient: User changed \(userID) \(username) icon: \(userIconID)")
        
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
        
        if let userIDField = packet.getField(type: .userID),
           let userID = userIDField.getUInt16() {
          self.delegate?.hotlineReceivedPrivateMessage(userID: userID, message: message)
        }
        else {
          self.delegate?.hotlineReceivedServerMessage(message: message)
        }
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
    
    case .newMessage:
       if let messageField = packet.getField(type: .data),
          let message = messageField.getString() {
          self.delegate?.hotlineReceivedNewsPost(message: message)
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
    
    let context = self.transactionLog[packet.id]
    self.transactionLog[packet.id] = nil

    if packet.errorCode != 0 {
      let errorField: HotlineTransactionField? = packet.getField(type: .errorText)
      print("HotlineClient 😵 \(packet.errorCode): \(errorField?.getString() ?? "")")
      if context?.suppressErrors != true {
        self.delegate?.hotlineReceivedErrorMessage(code: packet.errorCode, message: errorField?.getString())
      }
    }

    if let context {
      print("HotlineClient reply in response to \(context.type)")
    }
    
    let replyCallback = context?.callback
    
    guard packet.errorCode == 0 else {
      let errorField: HotlineTransactionField? = packet.getField(type: .errorText)
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
  
  @MainActor func sendChat(message: String, encoding: String.Encoding = .utf8, announce: Bool = false) {
    var t = HotlineTransaction(type: .sendChat)
    t.setFieldString(type: .data, val: message, encoding: encoding)
    t.setFieldUInt16(type: .chatOptions, val: announce ? 1 : 0)
    self.sendPacket(t)
  }
  
  @MainActor func sendInstantMessage(message: String, userID: UInt16, encoding: String.Encoding = .utf8) {
    var t = HotlineTransaction(type: .sendInstantMessage)
    t.setFieldUInt16(type: .userID, val: userID)
    t.setFieldUInt32(type: .options, val: 1)
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
      let matches = text.matches(of: RegularExpressions.messageBoardDivider)
      var start = text.startIndex
      
      if matches.count > 0 {
        for match in matches {
          let range = match.range
          let messageText = String(text[start..<range.lowerBound])
          messages.append(messageText.convertingLinksToMarkdown())
          start = range.upperBound
        }
      }
      else {
        messages.append(text)
      }
      
      callback?(err, messages)
    }
  }
  
  @MainActor func sendPostMessageBoard(text: String) {
    guard text.count > 0 else {
      return
    }
    
    var t = HotlineTransaction(type: .oldPostNews)
    t.setFieldString(type: .data, val: text.convertingLineEndings(to: .cr), encoding: .macOSRoman)
    self.sendPacket(t)
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
  
  @MainActor func postNewsArticle(title: String, text: String, path: [String] = [], parentID: UInt32 = 0, callback: ((Bool) -> Void)? = nil) {
    guard !path.isEmpty else {
      callback?(false)
      return
    }
    
    var t = HotlineTransaction(type: .postNewsArticle)
    t.setFieldPath(type: .newsPath, val: path)
    t.setFieldUInt32(type: .newsArticleID, val: parentID)
    t.setFieldString(type: .newsArticleTitle, val: title)
    t.setFieldString(type: .newsArticleDataFlavor, val: "text/plain")
    t.setFieldUInt32(type: .newsArticleFlags, val: 0)
    t.setFieldString(type: .newsArticleData, val: text.convertingLineEndings(to: .cr))
    
    print("HotlineClient postings \(title) under \(parentID)")
    
    self.sendPacket(t) { reply, err in
      guard err == nil else {
        callback?(false)
        return
      }
      callback?(true)
    }
  }
  
  @MainActor func sendGetAccounts(callback: (([HotlineAccount]) -> Void)? = nil) {
    let t = HotlineTransaction(type: .getAccounts)
    
    self.sendPacket(t) { reply, err in
      guard err == nil else {
        callback?([])
        return
      }

      let accountFields = reply.getFieldList(type: .data)
      
      var accounts: [HotlineAccount] = []
      for data in accountFields {
        accounts.append(data.getAcccount())
      }
      
      accounts.sort { $0.login < $1.login }
      
      callback?(accounts)
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
  
  @MainActor func sendGetFileList(path: [String] = [], suppressErrors: Bool = false, callback: (([HotlineFile]) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getFileNameList)
    if !path.isEmpty {
      t.setFieldPath(type: .filePath, val: path)
    }
    
    self.sendPacket(t, suppressErrors: suppressErrors) { reply, err in
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
  
  @MainActor func sendDeleteFile(name fileName: String, path filePath: [String], callback: ((Bool) -> Void)? = nil) {
    var t = HotlineTransaction(type: .deleteFile)
    t.setFieldString(type: .fileName, val: fileName)
    t.setFieldPath(type: .filePath, val: filePath)
    self.sendPacket(t) { reply, err in
      callback?(err == nil)
    }
  }
  
  @MainActor func sendGetFileInfo(name fileName: String, path filePath: [String], callback: ((FileDetails?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .getFileInfo)
    t.setFieldString(type: .fileName, val: fileName)
    t.setFieldPath(type: .filePath, val: filePath)
    
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let fileName = reply.getField(type: .fileName)?.getString(),
            let fileCreator = reply.getField(type: .fileCreatorString)?.getString(),
            let fileType = reply.getField(type: .fileTypeString)?.getString(),
            let _ = reply.getField(type: .fileTypeString)?.getString(),
            let fileCreateDate = reply.getField(type: .fileCreateDate)?.data.readDate(at: 0),
            let fileModifyDate = reply.getField(type: .fileModifyDate)?.data.readDate(at: 0)
 else {
        callback?(nil)
        return
      }
      

      // Size field is not included in server reply for folders
      let fileSize = reply.getField(type: .fileSize)?.getInteger() ?? 0

      // Comment field is not included for if no comment present
      let fileComment = reply.getField(type: .fileComment)?.getString() ?? ""

      callback?(FileDetails(name: fileName, path: filePath, size: fileSize, comment: fileComment, type: fileType, creator: fileCreator,
                            created: fileCreateDate, modified: fileModifyDate))
    }
  }
  

  @MainActor func sendCreateUser(name: String, login: String,  password: String?, access: uint64) {
    var t = HotlineTransaction(type: .newUser)
    
    t.setFieldString(type: .userName, val: name)
    t.setFieldEncodedString(type: .userLogin, val: login)
    t.setFieldUInt64(type: .userAccess, val: access)
    
    if let password {
      t.setFieldEncodedString(type: .userPassword, val: password)
    }
    
    self.sendPacket(t)
    // TODO: handle errors
  }

  @MainActor func sendSetUser(name: String, login: String, newLogin: String?, password: String?, access: uint64) {
    var t = HotlineTransaction(type: .setUser)
    t.setFieldString(type: .userName, val: name)
    t.setFieldUInt64(type: .userAccess, val: access)
    
    if let newLogin {
      t.setFieldEncodedString(type: .data, val: login)
      t.setFieldEncodedString(type: .userLogin, val: newLogin)
    } else {
      t.setFieldEncodedString(type: .userLogin, val: login)
    }
     
    // In the setUser transaction, there are 3 possibilities for the password field:
    // 1. If the password was not modified, the password field is sent with a zero byte.
    if password == nil {
      t.setFieldUInt8(type: .userPassword, val: 0)
    }
    
    // 2. If the transaction should update the password, the password field is sent with the new password.
    if let password, password != "" {
      t.setFieldEncodedString(type: .userPassword, val: password)
    }

    // 3) If the transaction should remove the password, the password field is omitted from the transaction.
    self.sendPacket(t)
    // TODO: handle errors
  }
  
  @MainActor func sendDeleteUser(login: String) {
    var t = HotlineTransaction(type: .deleteUser)
    t.setFieldEncodedString(type: .userLogin, val: login)
    
    self.sendPacket(t)
    // TODO: handle errors
  }
  
  @MainActor func sendSetFileInfo(fileName: String, path filePath: [String], fileNewName: String?, comment: String?, encoding: String.Encoding = .utf8) {
    var t = HotlineTransaction(type: .setFileInfo)
    t.setFieldString(type: .fileName, val: fileName, encoding: encoding)
    t.setFieldPath(type: .filePath, val: filePath)

    if fileNewName != nil {
      t.setFieldString(type: .fileNewName, val: fileNewName!, encoding: encoding)
    }
    
    if comment != nil {
      t.setFieldString(type: .fileComment, val: comment!, encoding: encoding)
    }

    self.sendPacket(t)
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
            let referenceNumber = transferReferenceField.getUInt32() else {
        callback?(false, nil, nil, nil, nil)
        return
      }
    
      let transferFileSizeField = reply.getField(type: .fileSize)
      let transferFileSize = transferFileSizeField?.getInteger()
      let transferWaitingCountField = reply.getField(type: .waitingCount)
      let transferWaitingCount = transferWaitingCountField?.getInteger()
      
      callback?(true, referenceNumber, transferSize, transferFileSize ?? transferSize, transferWaitingCount)
    }
  }
  
  @MainActor func sendUploadFile(name fileName: String, path filePath: [String], callback: ((Bool, UInt32?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .uploadFile)
    t.setFieldString(type: .fileName, val: fileName)
    t.setFieldPath(type: .filePath, val: filePath)
    
    self.sendPacket(t) { reply, err in
      guard err == nil,
            let transferReferenceField = reply.getField(type: .referenceNumber),
            let referenceNumber = transferReferenceField.getUInt32() else {
        callback?(false, nil)
        return
      }
    
      callback?(true, referenceNumber)
    }
  }
  
  @MainActor func sendDownloadFolder(name folderName: String, path folderPath: [String], callback: ((Bool, UInt32?, Int?, Int?, Int?) -> Void)? = nil) {
    var t = HotlineTransaction(type: .downloadFolder)
    t.setFieldString(type: .fileName, val: folderName)
    t.setFieldPath(type: .filePath, val: folderPath)

    self.sendPacket(t) { reply, err in
      guard err == nil,
            let transferSizeField = reply.getField(type: .transferSize),
            let transferSize = transferSizeField.getInteger(),
            let transferReferenceField = reply.getField(type: .referenceNumber),
            let referenceNumber = transferReferenceField.getUInt32() else {
        callback?(false, nil, nil, nil, nil)
        return
      }

      let folderItemCountField = reply.getField(type: .folderItemCount)
      let folderItemCount = folderItemCountField?.getInteger()
      let transferWaitingCountField = reply.getField(type: .waitingCount)
      let transferWaitingCount = transferWaitingCountField?.getInteger()

      callback?(true, referenceNumber, transferSize, folderItemCount, transferWaitingCount)
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
  
  @MainActor private func sendKeepAlive() {
    print("HotlineClient: Sending keep alive")
    if let v = self.serverVersion, v >= 185 {
      let t = HotlineTransaction(type: .connectionKeepAlive)
      self.sendPacket(t)
    }
    else {
      let t = HotlineTransaction(type: .getUserNameList)
      self.sendPacket(t)
    }
  }
  
  
  // MARK: - Utility

  @MainActor private func updateConnectionStatus(_ status: HotlineClientStatus) {
    self.connectionStatus = status
    self.delegate?.hotlineStatusChanged(status: status)
  }

}
