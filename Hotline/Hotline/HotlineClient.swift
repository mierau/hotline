import Foundation
import Network

// MARK: - Events

/// Events that can be received from a Hotline server
///
/// These are unsolicited messages sent by the server (not replies to requests).
/// Subscribe to the `events` stream to receive them.
public enum HotlineEvent: Sendable {
  /// Server sent a chat message
  case chatMessage(String)
  /// A user's information changed (name, icon, status)
  case userChanged(HotlineUser)
  /// A user disconnected from the server
  case userDisconnected(UInt16)
  /// Server sent a broadcast message
  case serverMessage(String)
  /// Received a private message from a user
  case privateMessage(userID: UInt16, message: String)
  /// Server sent a news post notification
  case newsPost(String)
  /// Server sent agreement (nil text means no agreement required)
  case showAgreement(String?)
  /// Server sent user access permissions
  case userAccess(HotlineUserAccessOptions)
  /// Server sent a disconnect message (client should disconnect after receiving)
  case disconnectMessage(String)
}

// MARK: - Errors

/// Errors that can occur during Hotline operations
public enum HotlineClientError: Error {
  /// Connection failed
  case connectionFailed(Error)
  /// Server responded with an error code
  case serverError(code: UInt32, message: String?)
  /// Transaction timed out waiting for reply
  case timeout
  /// Client is not connected
  case notConnected
  /// Invalid response from server
  case invalidResponse
  /// Login failed
  case loginFailed(String?)
  
  var userMessage: String {
    switch self {
    case .connectionFailed:
      "Failed to connect to server"
    case .serverError(let code, let message):
      message ?? "Server error: \(code)"
    case .timeout:
      "Request could not be completed"
    case .notConnected:
      "Not connected"
    case .invalidResponse:
      "Server returned an invalid response"
    case .loginFailed(let message):
      message ?? "Login failed"
    }
  }
}

// MARK: - Login Info

/// Information needed to log in to a Hotline server
public struct HotlineLogin: Sendable {
  let login: String
  let password: String
  let username: String
  let iconID: UInt16

  public init(login: String, password: String, username: String, iconID: UInt16) {
    self.login = login
    self.password = password
    self.username = username
    self.iconID = iconID
  }
}

// MARK: - Server Info

/// Information about the connected server
public struct HotlineServerInfo: Sendable {
  let name: String?
  let version: UInt16

  public init(name: String?, version: UInt16) {
    self.name = name
    self.version = version
  }
}

// MARK: - Hotline Client

/// A client for connecting to and interacting with Hotline servers.
///
/// Example usage:
/// ```swift
/// let client = try await HotlineClient.connect(
///   host: "server.example.com",
///   port: 5500,
///   login: HotlineLogin(login: "unnamed", password: "", username: "John", iconID: 414)
/// )
///
/// // Listen for events
/// Task {
///   for await event in client.events {
///     switch event {
///     case .chatMessage(let text):
///       print("Chat: \(text)")
///     case .userChanged(let user):
///       print("User changed: \(user.name)")
///     default:
///       break
///     }
///   }
/// }
///
/// // Send chat message
/// try await client.sendChat("Hello world!")
///
/// // Get user list
/// let users = try await client.getUserList()
/// ```
public actor HotlineClient {
  // MARK: - Properties

  private let socket: NetSocket
  private var serverInfo: HotlineServerInfo?
  private var loginInfo: HotlineLogin?
  private var isConnected: Bool = true

  /// Information about the connected server (name and version)
  public var server: HotlineServerInfo? {
    return serverInfo
  }

  // Event streaming
  private let eventContinuation: AsyncStream<HotlineEvent>.Continuation
  public let events: AsyncStream<HotlineEvent>

  // Transaction tracking for request/reply pattern
  private var pendingTransactions: [UInt32: CheckedContinuation<HotlineTransaction, Error>] = [:]

  // Server version from login
  public private(set) var serverVersion: UInt16 = 0

  // Receive loop task
  private var receiveTask: Task<Void, Never>?

  // Keep-alive timer
  private var keepAliveTask: Task<Void, Never>?

  // Transaction IDs
  private var nextTransactionID: UInt32 = 1
  private func generateTransactionID() -> UInt32 {
    defer { self.nextTransactionID += 1 }
    return self.nextTransactionID
  }

  // MARK: - Connection

  /// Connect to a Hotline server and log in
  ///
  /// This method:
  /// 1. Establishes TCP connection
  /// 2. Performs handshake
  /// 3. Logs in with provided credentials
  /// 4. Starts event streaming and keep-alive
  ///
  /// - Parameters:
  ///   - host: Server hostname or IP address
  ///   - port: Server port (default: 5500)
  ///   - login: Login credentials and user info
  ///   - tls: TLS policy (default: disabled for Hotline)
  /// - Returns: Connected and logged-in client
  /// - Throws: `HotlineClientError` if connection or login fails
  public static func connect(
    host: String,
    port: UInt16 = 5500,
    login: HotlineLogin
  ) async throws -> HotlineClient {
    print("HotlineClient.connect(): Starting connection to \(host):\(port) as '\(login.username)'")

    // Connect socket
    print("HotlineClient.connect(): Connecting socket...")
    let socket: NetSocket
    do {
      var config = NetSocket.Config()
      config.enableKeepAlive = true
      config.keepAliveIdleTime = 60
      socket = try await NetSocket.connect(host: host, port: port, config: config)
    }
    catch let socketError as NetSocketError {
      if case .failed(_) = socketError {
        throw HotlineClientError.connectionFailed(socketError)
      }
      throw socketError
    }
    print("HotlineClient.connect(): Socket connected")

    // Perform handshake
    print("HotlineClient.connect(): Sending handshake...")
    try await socket.write(Data(endian: .big, {
      "TRTP".fourCharCode() // 'TRTP' protocol ID
      "HOTL".fourCharCode() // 'HOTL' sub-protocol ID
      UInt16(0x0001) // Version
      UInt16(0x0002) // Sub-version
    }))
    let handshakeResponse = try await socket.read(8)
    print("HotlineClient.connect(): Handshake response received")

    // Verify handshake
    guard handshakeResponse.prefix(4) == Data([0x54, 0x52, 0x54, 0x50]) else {
      print("HotlineClient.connect(): Invalid handshake response")
      throw HotlineClientError.connectionFailed(
        NSError(domain: "HotlineClient", code: -1, userInfo: [
          NSLocalizedDescriptionKey: "Invalid handshake response"
        ])
      )
    }

    let errorCode = handshakeResponse.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
    guard errorCode.bigEndian == 0 else {
      print("HotlineClient.connect(): Handshake failed with error code \(errorCode)")
      throw HotlineClientError.connectionFailed(
        NSError(domain: "HotlineClient", code: Int(errorCode), userInfo: [
          NSLocalizedDescriptionKey: "Handshake failed with error code \(errorCode)"
        ])
      )
    }

    // Create client
    print("HotlineClient.connect(): Creating client instance")
    let client = HotlineClient(socket: socket)

    // Start receive loop
    print("HotlineClient.connect(): Starting receive loop")
    await client.startReceiveLoop()

    // Perform login
    print("HotlineClient.connect(): Performing login")
    let serverInfo = try await client.performLogin(login)
    await client.setServerInfo(serverInfo)
    await client.setLoginInfo(login)
    await client.setServerVersion(serverInfo.version)
    print("HotlineClient.connect(): Login successful, server v\(serverInfo.version)")

    return client
  }

  private init(socket: NetSocket) {
    self.socket = socket

    // Set up event stream
    var continuation: AsyncStream<HotlineEvent>.Continuation!
    self.events = AsyncStream { cont in
      continuation = cont
    }
    self.eventContinuation = continuation
  }

  private func setServerInfo(_ info: HotlineServerInfo) {
    self.serverInfo = info
  }

  private func setLoginInfo(_ login: HotlineLogin) {
    self.loginInfo = login
  }

  private func setServerVersion(_ version: UInt16) {
    self.serverVersion = version
  }

  // MARK: - Login

  private func performLogin(_ login: HotlineLogin) async throws -> HotlineServerInfo {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .login)
    transaction.setFieldEncodedString(type: .userLogin, val: login.login)
    transaction.setFieldEncodedString(type: .userPassword, val: login.password)
    transaction.setFieldUInt16(type: .userIconID, val: login.iconID)
    transaction.setFieldString(type: .userName, val: login.username)
    transaction.setFieldUInt32(type: .versionNumber, val: 123)

    let reply = try await sendTransaction(transaction)
    
    guard reply.errorCode == 0 else {
      let errorText = reply.getField(type: .errorText)?.getString()
      throw HotlineClientError.loginFailed(errorText)
    }

    // All servers send a server version.
    let serverVersion = reply.getField(type: .versionNumber)?.getUInt16() ?? 123
    
    // Later clients send a name and banner ID.
    let serverName = reply.getField(type: .serverName)?.getString()
//    let serverBannerID = reply.getField(type: .communityBannerID)?.getInteger()

    return HotlineServerInfo(name: serverName, version: serverVersion)
  }

  // MARK: - Disconnect

  /// Disconnect from the server
  ///
  /// Closes the socket and stops all background tasks.
  public func disconnect() async {
    guard isConnected else {
      return
    }

    isConnected = false

    print("HotlineClient.disconnect(): Starting disconnect")
    self.receiveTask?.cancel()
    self.keepAliveTask?.cancel()
    await self.socket.close()
    self.failAllPendingTransactions(HotlineClientError.notConnected)
    self.eventContinuation.finish()
    print("HotlineClient.disconnect(): Disconnect complete")
  }

  // MARK: - Receive Loop

  private func startReceiveLoop() {
    print("HotlineClient.startReceiveLoop(): Creating receive task")
    self.receiveTask = Task { [weak self] in
      guard let self else {
        return
      }

      do {
        while !Task.isCancelled {
          // Read transaction from socket
          let transaction = try await self.socket.receive(HotlineTransaction.self, endian: .big)
          await self.handleTransaction(transaction)
        }
        print("HotlineClient.startReceiveLoop(): Task cancelled, exiting loop")
      } catch {
        if Task.isCancelled || error is CancellationError {
          print("HotlineClient.startReceiveLoop(): Receive loop cancelled")
        } else {
          print("HotlineClient.startReceiveLoop(): Receive loop error: \(error)")
          await self.disconnect()
        }
      }
      print("HotlineClient.startReceiveLoop(): Receive loop ended")
    }
  }

  private func handleTransaction(_ transaction: HotlineTransaction) {
    print("HotlineClient: <= \(transaction.type) [\(transaction.id)]")

    // Check if this is a reply to a pending transaction
    if transaction.isReply == 1 || transaction.type == .reply {
      handleReply(transaction)
      return
    }

    // Handle unsolicited server messages (events)
    handleEvent(transaction)
  }

  private func handleReply(_ transaction: HotlineTransaction) {
    guard let continuation = pendingTransactions.removeValue(forKey: transaction.id) else {
      print("HotlineClient: Received reply for unknown transaction \(transaction.id)")
      return
    }

    if transaction.errorCode != 0 {
      let errorText = transaction.getField(type: .errorText)?.getString()
      continuation.resume(throwing: HotlineClientError.serverError(
        code: transaction.errorCode,
        message: errorText
      ))
    } else {
      continuation.resume(returning: transaction)
    }
  }

  private func handleEvent(_ transaction: HotlineTransaction) {
    switch transaction.type {
    case .chatMessage:
      if let text = transaction.getField(type: .data)?.getString() {
        eventContinuation.yield(.chatMessage(text))
      }

    case .notifyOfUserChange:
      if let usernameField = transaction.getField(type: .userName),
         let username = usernameField.getString(),
         let userID = transaction.getField(type: .userID)?.getUInt16(),
         let iconID = transaction.getField(type: .userIconID)?.getUInt16(),
         let flags = transaction.getField(type: .userFlags)?.getUInt16() {
        let user = HotlineUser(id: userID, iconID: iconID, status: flags, name: username)
        eventContinuation.yield(.userChanged(user))
      }

    case .notifyOfUserDelete:
      if let userID = transaction.getField(type: .userID)?.getUInt16() {
        eventContinuation.yield(.userDisconnected(userID))
      }

    case .serverMessage:
      if let message = transaction.getField(type: .data)?.getString() {
        if let userID = transaction.getField(type: .userID)?.getUInt16() {
          eventContinuation.yield(.privateMessage(userID: userID, message: message))
        } else {
          eventContinuation.yield(.serverMessage(message))
        }
      }

    case .showAgreement:
      let text: String?
      if transaction.getField(type: .noServerAgreement) == nil,
         let agreementText = transaction.getField(type: .data)?.getString() {
        text = agreementText
      } else {
        text = nil
      }
      eventContinuation.yield(.showAgreement(text))

    case .userAccess:
      if let accessValue = transaction.getField(type: .userAccess)?.getUInt64() {
        eventContinuation.yield(.userAccess(HotlineUserAccessOptions(rawValue: accessValue)))
      }

    case .newMessage:
      if let message = transaction.getField(type: .data)?.getString() {
        eventContinuation.yield(.newsPost(message))
      }

    case .disconnectMessage:
      let message = transaction.getField(type: .data)?.getString() ?? "You have been disconnected."
      eventContinuation.yield(.disconnectMessage(message))
      Task {
        await self.disconnect()
      }

    default:
      print("HotlineClient: Unhandled event type \(transaction.type)")
    }
  }

  // MARK: - Transaction Sending

  @discardableResult
  private func sendTransaction(_ transaction: HotlineTransaction, timeout: TimeInterval = 30.0) async throws -> HotlineTransaction {
    print("HotlineClient: => \(transaction.type) [\(transaction.id)]")

    let transactionID = transaction.id

    try await self.socket.send(transaction, endian: .big)

    do {
      return try await Task.withTimeout(seconds: timeout) {
        try await self.awaitReply(for: transactionID)
      }
    } catch is TaskTimeoutError {
      throw HotlineClientError.timeout
    } catch let error as HotlineClientError {
      print("Hotline Client Error: \(error)")
      throw error
    } catch {
      throw error
    }
  }

  private func storePendingTransaction(id: UInt32, continuation: CheckedContinuation<HotlineTransaction, Error>) {
    self.pendingTransactions[id] = continuation
  }

  private func awaitReply(for transactionID: UInt32) async throws -> HotlineTransaction {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.storePendingTransaction(id: transactionID, continuation: continuation)
      }
    } onCancel: { [weak self] in
      Task { await self?.failPendingTransaction(id: transactionID, error: HotlineClientError.timeout) }
    }
  }

  private func failPendingTransaction(id: UInt32, error: Error) {
    guard let continuation = self.pendingTransactions.removeValue(forKey: id) else { return }
    continuation.resume(throwing: error)
  }

  private func failAllPendingTransactions(_ error: Error) {
    guard !self.pendingTransactions.isEmpty else { return }
    let continuations = self.pendingTransactions
    self.pendingTransactions.removeAll()
    for (_, continuation) in continuations {
      continuation.resume(throwing: error)
    }
  }

  // MARK: - Keep-Alive

  public func startKeepAlive() {
    self.keepAliveTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 180_000_000_000) // 3 minutes
        await self?.sendKeepAlive()
      }
    }
  }
  
  private func sendKeepAlive() async {
    do {
      if let version = self.serverInfo?.version, version >= 185 {
        let transaction = HotlineTransaction(id: self.generateTransactionID(), type: .connectionKeepAlive)
        try await self.socket.send(transaction, endian: .big)
      } else {
        // Older servers: send getUserNameList as keep-alive
        let _ = try? await self.getUserList()
      }
    } catch {
      print("HotlineClient: Keep-alive failed: \(error)")
    }
  }

  // MARK: - Chat
  
  /// Broadcast a message to the server
  ///
  /// - Parameters:
  ///   - message: Text to send
  ///   - encoding: Text encoding (default: UTF-8)
  public func sendBroadcast(_ message: String, encoding: String.Encoding = .utf8, announce: Bool = false) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .userBroadcast)
    transaction.setFieldString(type: .data, val: message, encoding: encoding)
    try await socket.send(transaction, endian: .big)
  }

  /// Send a chat message to the server
  ///
  /// - Parameters:
  ///   - message: Text to send
  ///   - encoding: Text encoding (default: UTF-8)
  ///   - announce: Whether this is an announcement (admin only, default: false)
  public func sendChat(_ message: String, encoding: String.Encoding = .utf8, announce: Bool = false) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .sendChat)
    transaction.setFieldString(type: .data, val: message, encoding: encoding)
    transaction.setFieldUInt16(type: .chatOptions, val: announce ? 1 : 0)

    try await socket.send(transaction, endian: .big)
  }

  // MARK: - Users

  /// Get the list of users currently connected to the server
  ///
  /// - Returns: Array of connected users
  public func getUserList() async throws -> [HotlineUser] {
    let transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getUserNameList)
    let reply = try await sendTransaction(transaction)

    var users: [HotlineUser] = []
    for field in reply.getFieldList(type: .userNameWithInfo) {
      users.append(field.getUser())
    }

    return users
  }

  /// Send a private instant message to a user
  ///
  /// - Parameters:
  ///   - message: Text to send
  ///   - userID: Target user ID
  ///   - encoding: Text encoding (default: UTF-8)
  public func sendInstantMessage(_ message: String, to userID: UInt16, encoding: String.Encoding = .utf8) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .sendInstantMessage)
    transaction.setFieldUInt16(type: .userID, val: userID)
    transaction.setFieldUInt32(type: .options, val: 1)
    transaction.setFieldString(type: .data, val: message.convertingLineEndings(to: .cr), encoding: encoding)

    try await socket.send(transaction, endian: .big)
  }
  
  /// Get information text about a user
  ///
  /// - Parameters:
  ///   - userID: Target user ID
  public func getClientInfoText(for userID: UInt16) async throws -> HotlineUserClientInfo? {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getClientInfoText)
    transaction.setFieldUInt16(type: .userID, val: userID)

    let reply = try await self.sendTransaction(transaction)
    
    if let username = reply.getField(type: .userName)?.getString(),
       let info = reply.getField(type: .data)?.getString() {
      return HotlineUserClientInfo(username: username, details: info)
    }
    
    return nil
  }

  /// Update this client's user info (name, icon, options)
  ///
  /// - Parameters:
  ///   - username: Display name
  ///   - iconID: Icon ID
  ///   - options: User options flags
  ///   - autoresponse: Optional auto-response text
  public func setClientUserInfo(
    username: String,
    iconID: UInt16,
    options: HotlineUserOptions = [],
    autoresponse: String? = nil
  ) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .setClientUserInfo)
    transaction.setFieldString(type: .userName, val: username)
    transaction.setFieldUInt16(type: .userIconID, val: iconID)
    transaction.setFieldUInt16(type: .options, val: options.rawValue)

    if let autoresponse {
      transaction.setFieldString(type: .automaticResponse, val: autoresponse)
    }

    try await socket.send(transaction, endian: .big)
  }
  
  /// Force a user to disconnect from the server
  ///
  /// - Parameters:
  ///   - userID: Target user ID
  ///   - options: If specified, temporarily or permanently ban the user
  public func disconnectUser(userID: UInt16, options: HotlineUserDisconnectOptions? = nil) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .disconnectUser)
    
    transaction.setFieldUInt16(type: .userID, val: userID)
    if let options {
      transaction.setFieldUInt16(type: .options, val: options.rawValue)
    }
    
    try await self.sendTransaction(transaction)
  }

  // MARK: - Agreement

  /// Send agreement acceptance to the server
  ///
  /// The agreed transaction includes user info fields (username, icon, options)
  /// which the server uses to set up the client's identity.
  public func sendAgree(options: HotlineUserOptions = [], autoresponse: String? = nil) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .agreed)

    if let loginInfo {
      transaction.setFieldString(type: .userName, val: loginInfo.username)
      transaction.setFieldUInt16(type: .userIconID, val: loginInfo.iconID)
    }

    transaction.setFieldUInt16(type: .options, val: options.rawValue)

    if let autoresponse {
      transaction.setFieldString(type: .automaticResponse, val: autoresponse)
    }

    try await self.sendTransaction(transaction)
  }

  // MARK: - Files

  /// Get the file list for a directory
  ///
  /// - Parameter path: Directory path (empty for root)
  /// - Returns: Array of files and folders
  public func getFileList(path: [String] = []) async throws -> [HotlineFile] {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getFileNameList)
    if !path.isEmpty {
      transaction.setFieldPath(type: .filePath, val: path)
    }

    let reply = try await self.sendTransaction(transaction)

    var files: [HotlineFile] = []
    for field in reply.getFieldList(type: .fileNameWithInfo) {
      let file = field.getFile()
      file.path = path + [file.name]
      files.append(file)
    }

    return files
  }
  
  /// Get detailed information about a file
  ///
  /// - Parameters:
  ///   - name: File name
  ///   - path: Directory path containing the file
  /// - Returns: File details or nil if not found
  public func getFileInfo(name: String, path: [String]) async throws -> FileDetails? {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getFileInfo)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)

    let reply = try await sendTransaction(transaction)

    guard
      let fileName = reply.getField(type: .fileName)?.getString(),
      let fileCreator = reply.getField(type: .fileCreatorString)?.getString(),
      let fileType = reply.getField(type: .fileTypeString)?.getString(),
      let fileCreateDate = reply.getField(type: .fileCreateDate)?.data.readDate(at: 0),
      let fileModifyDate = reply.getField(type: .fileModifyDate)?.data.readDate(at: 0)
    else {
      return nil
    }

    // Size field is not included in server reply for folders
    let fileSize = reply.getField(type: .fileSize)?.getInteger() ?? 0
    let fileComment = reply.getField(type: .fileComment)?.getString() ?? ""

    return FileDetails(
      name: fileName,
      path: path,
      size: fileSize,
      comment: fileComment,
      type: fileType,
      creator: fileCreator,
      created: fileCreateDate,
      modified: fileModifyDate
    )
  }
  
  /// Set a file's information (name/comment)
  ///
  /// - Parameters:
  ///   - name: File name
  ///   - path: Directory path containing the file
  ///   - newName: Name to set the file to
  ///   - comment: Comment to set on the file
  public func setFileInfo(name: String, path: [String], newName: String? = nil, comment: String? = nil, encoding: String.Encoding = .utf8) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .setFileInfo)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)
    
    if let newName {
      transaction.setFieldString(type: .fileNewName, val: newName)
    }
    
    if let comment {
      transaction.setFieldString(type: .fileComment, val: comment)
    }

    try await sendTransaction(transaction)
  }

  /// Delete a file or folder
  ///
  /// - Parameters:
  ///   - name: File or folder name
  ///   - path: Directory path containing the item
  /// - Returns: True if deletion succeeded
  public func deleteFile(name: String, path: [String]) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .deleteFile)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)

    try await self.sendTransaction(transaction)
  }
  
  /// Create a folder
  ///
  /// - Parameters:
  ///   - name: New folder name
  ///   - path: Directory path for the new folder
  /// - Returns: True if creation succeeded
  public func newFolder(name: String, path: [String]) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .newFolder)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)
    try await self.sendTransaction(transaction)
  }

  // MARK: - News

  /// Get news categories at a path
  ///
  /// - Parameter path: Category path (empty for root)
  /// - Returns: Array of news categories
  public func getNewsCategories(path: [String] = []) async throws -> [HotlineNewsCategory] {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getNewsCategoryNameList)
    if !path.isEmpty {
      transaction.setFieldPath(type: .newsPath, val: path)
    }

    let reply = try await self.sendTransaction(transaction)

    var categories: [HotlineNewsCategory] = []
    for field in reply.getFieldList(type: .newsCategoryListData15) {
      var category = field.getNewsCategory()
      category.path = path + [category.name]
      categories.append(category)
    }

    return categories
  }

  /// Get news articles in a category
  ///
  /// - Parameter path: Category path
  /// - Returns: Array of news articles
  public func getNewsArticles(path: [String] = []) async throws -> [HotlineNewsArticle] {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getNewsArticleNameList)
    if !path.isEmpty {
      transaction.setFieldPath(type: .newsPath, val: path)
    }

    let reply = try await self.sendTransaction(transaction)

    guard let articleData = reply.getField(type: .newsArticleListData) else {
      return []
    }

    let newsList = articleData.getNewsList()
    return newsList.articles.map { article in
      var a = article
      a.path = path
      return a
    }
  }

  /// Get the content of a news article
  ///
  /// - Parameters:
  ///   - id: Article ID
  ///   - path: Category path
  ///   - flavor: Content flavor (default: "text/plain")
  /// - Returns: Article content as string
  public func getNewsArticle(id: UInt32, path: [String], flavor: String = "text/plain") async throws -> String? {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getNewsArticleData)
    transaction.setFieldPath(type: .newsPath, val: path)
    transaction.setFieldUInt32(type: .newsArticleID, val: id)
    transaction.setFieldString(type: .newsArticleDataFlavor, val: flavor, encoding: .ascii)

    let reply = try await self.sendTransaction(transaction)
    return reply.getField(type: .newsArticleData)?.getString()
  }

  /// Post a news article
  ///
  /// - Parameters:
  ///   - title: Article title
  ///   - text: Article body
  ///   - path: Category path
  ///   - parentID: Parent article ID (for replies, default: 0)
  public func postNewsArticle(
    title: String,
    text: String,
    path: [String],
    parentID: UInt32 = 0
  ) async throws {
    guard !path.isEmpty else {
      throw HotlineClientError.invalidResponse
    }

    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .postNewsArticle)
    transaction.setFieldPath(type: .newsPath, val: path)
    transaction.setFieldUInt32(type: .newsArticleID, val: parentID)
    transaction.setFieldString(type: .newsArticleTitle, val: title)
    transaction.setFieldString(type: .newsArticleDataFlavor, val: "text/plain")
    transaction.setFieldUInt32(type: .newsArticleFlags, val: 0)
    transaction.setFieldString(type: .newsArticleData, val: text)

    try await self.sendTransaction(transaction)
  }

  /// Create a new news folder (bundle) on the server
  ///
  /// - Parameters:
  ///   - name: Folder name
  ///   - path: Parent news path (empty for root)
  public func newNewsFolder(name: String, path: [String] = []) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .newNewsFolder)
    transaction.setFieldString(type: .fileName, val: name)
    if !path.isEmpty {
      transaction.setFieldPath(type: .newsPath, val: path)
    }

    try await self.sendTransaction(transaction)
  }

  /// Create a new news category on the server
  ///
  /// - Parameters:
  ///   - name: Category name
  ///   - path: Parent news path (empty for root)
  public func newNewsCategory(name: String, path: [String] = []) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .newNewsCategory)
    transaction.setFieldString(type: .newsCategoryName, val: name)
    if !path.isEmpty {
      transaction.setFieldPath(type: .newsPath, val: path)
    }

    try await self.sendTransaction(transaction)
  }

  /// Delete a news folder or category from the server
  ///
  /// - Parameter path: Full path to the folder or category to delete
  public func deleteNewsItem(path: [String]) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .deleteNewsItem)
    transaction.setFieldPath(type: .newsPath, val: path)

    try await self.sendTransaction(transaction)
  }

  /// Delete a news article from the server
  ///
  /// - Parameters:
  ///   - id: Article ID
  ///   - path: Category path containing the article
  ///   - recursive: Whether to delete child articles (replies)
  public func deleteNewsArticle(id: UInt32, path: [String], recursive: Bool = true) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .deleteNewsArticle)
    transaction.setFieldPath(type: .newsPath, val: path)
    transaction.setFieldUInt32(type: .newsArticleID, val: id)
    transaction.setFieldUInt32(type: .newsArticleRecursiveDelete, val: recursive ? 1 : 0)

    try await self.sendTransaction(transaction)
  }

  // MARK: - Message Board

  /// Get message board posts
  ///
  /// - Returns: Tuple of message strings and optional divider signature label
  public func getMessageBoard() async throws -> (posts: [String], dividerSignature: String?) {
    let transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getMessageBoard)
    let reply = try await self.sendTransaction(transaction)

    guard let field = reply.getField(type: .data) else {
      return (posts: [], dividerSignature: nil)
    }

    // Split raw bytes on dividers BEFORE decoding, so each post gets
    // decoded individually.  This handles mixed-encoding boards where
    // some posts are UTF-8 and others are Mac OS Roman.
    return Self.parseMessageBoardData(Data(field.data))
  }

  /// Split raw message board bytes into individual posts, decoding each
  /// post separately so mixed-encoding boards are handled correctly.
  /// Returns the posts and the divider signature label (if any).
  static func parseMessageBoardData(_ data: Data) -> (posts: [String], dividerSignature: String?) {
    if data.isEmpty { return (posts: [], dividerSignature: nil) }

    // Split raw bytes on line endings (\r, \r\n)
    let lines = Self.splitRawLines(data)

    // Find the canonical divider character and label for this board.
    // All real dividers on a server use the same separator char.
    let canonical = Self.findCanonicalDivider(in: lines)
    let canonicalChar = canonical?.char

    var posts: [String] = []
    var currentPostBytes = Data()

    for line in lines {
      if let info = Self.classifyDividerLine(line), info.leadChar == canonicalChar {
        if !currentPostBytes.isEmpty {
          if let post = Self.decodePostBytes(currentPostBytes) {
            posts.append(post)
          }
          currentPostBytes = Data()
        }
      } else {
        if !currentPostBytes.isEmpty {
          currentPostBytes.append(0x0A)
        }
        currentPostBytes.append(contentsOf: line)
      }
    }

    // Capture trailing post after last divider
    if let post = Self.decodePostBytes(currentPostBytes) {
      posts.append(post)
    }

    return (posts: posts, dividerSignature: canonical?.label)
  }

  /// Split message board text (already decoded) into individual posts.
  /// Used by handleNewsPost which receives already-decoded strings.
  private static let dividerRegex = /^[ \t]*([_\-=~*]{15,}|[_\-=~*]{5,}.+[_\-=~*]{5,})[ \t]*$/
  private static let dividerLeadCharRegex = /^[ \t]*([_\-=~*])/

  static func parseMessageBoard(_ text: String) -> (posts: [String], dividerSignature: String?) {
    let normalized = text.replacing(/\r\n?/, with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

    // Find the canonical divider character and label for this board.
    let canonical = Self.findCanonicalDivider(in: lines)
    let canonicalChar = canonical?.char

    var posts: [String] = []
    var currentLines: [Substring] = []

    for line in lines {
      if line.wholeMatch(of: Self.dividerRegex) != nil,
         let m = line.firstMatch(of: Self.dividerLeadCharRegex),
         m.1.first == canonicalChar {
        let postText = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !postText.isEmpty {
          posts.append(postText)
        }
        currentLines = []
      } else {
        currentLines.append(line)
      }
    }

    let lastPost = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if !lastPost.isEmpty {
      posts.append(lastPost)
    }

    return (posts: posts, dividerSignature: canonical?.label)
  }

  // MARK: - Message Board Byte Helpers

  /// Split raw data on \r and \r\n line endings, returning each line as Data.
  private static func splitRawLines(_ data: Data) -> [Data] {
    var lines: [Data] = []
    var start = data.startIndex
    var i = data.startIndex

    while i < data.endIndex {
      if data[i] == 0x0D { // \r
        lines.append(data[start..<i])
        // Skip \n if \r\n
        let next = data.index(after: i)
        if next < data.endIndex && data[next] == 0x0A {
          i = data.index(after: next)
        } else {
          i = next
        }
        start = i
      } else {
        i = data.index(after: i)
      }
    }

    // Remaining bytes after last line ending
    if start < data.endIndex {
      lines.append(data[start..<data.endIndex])
    }

    return lines
  }

  /// A divider's signature: the leading separator character used,
  /// plus any embedded label text (e.g. "higher intellect" from
  /// `___ [ higher intellect ] ___`).
  /// Servers use a consistent divider style, so we match against
  /// whichever character appears most often across all divider lines.
  struct DividerInfo {
    let leadChar: UInt8
    let label: String?
  }

  /// Check if a line of raw bytes is a divider. Returns the divider's
  /// signature if it is, or nil if not.
  private static func classifyDividerLine(_ line: Data) -> DividerInfo? {
    let separators: Set<UInt8> = [0x5F, 0x2D, 0x3D, 0x7E, 0x2A] // _ - = ~ *
    let whitespace: Set<UInt8> = [0x20, 0x09] // space, tab

    // Trim leading/trailing whitespace
    let bytes = Array(line)
    let start = bytes.firstIndex(where: { !whitespace.contains($0) }) ?? bytes.count
    let end = (bytes.lastIndex(where: { !whitespace.contains($0) }) ?? -1) + 1
    guard start < end else { return nil }
    let trimmed = bytes[start..<end]
    guard let leadChar = trimmed.first, separators.contains(leadChar) else { return nil }

    // All separators, 15+ long — pure divider, no label
    if trimmed.count >= 15 && trimmed.allSatisfy({ separators.contains($0) }) {
      return DividerInfo(leadChar: leadChar, label: nil)
    }

    // 5+ separators on each side with anything between
    var leadCount = 0
    for byte in trimmed {
      if separators.contains(byte) { leadCount += 1 } else { break }
    }
    var trailCount = 0
    for byte in trimmed.reversed() {
      if separators.contains(byte) { trailCount += 1 } else { break }
    }
    if leadCount >= 5 && trailCount >= 5 {
      // Extract the label text between the separator runs
      let labelBytes = trimmed.dropFirst(leadCount).dropLast(trailCount)
      let labelData = Data(labelBytes)
      let label = labelData.readString(at: 0, length: labelData.count)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return DividerInfo(leadChar: leadChar, label: label?.isEmpty == true ? nil : label)
    }

    return nil
  }

  /// Find the canonical divider character by picking the most common
  /// leading separator character across all divider lines.
  /// Also returns the first label found among matching dividers.
  private static func findCanonicalDivider(in lines: [Data]) -> (char: UInt8, label: String?)? {
    var counts: [UInt8: Int] = [:]
    var order: [UInt8: Int] = [:]  // first-seen index for tiebreaking
    var labels: [UInt8: String] = [:]
    for line in lines {
      if let info = classifyDividerLine(line) {
        if order[info.leadChar] == nil {
          order[info.leadChar] = order.count
        }
        counts[info.leadChar, default: 0] += 1
        if let label = info.label, labels[info.leadChar] == nil {
          labels[info.leadChar] = label
        }
      }
    }
    // Pick the most common separator char; break ties by first occurrence.
    guard let best = counts.max(by: {
      $0.value != $1.value ? $0.value < $1.value : (order[$0.key] ?? 0) > (order[$1.key] ?? 0)
    }) else { return nil }
    return (char: best.key, label: labels[best.key])
  }

  /// String-based variant: find canonical divider character and label.
  private static func findCanonicalDivider(in lines: [Substring]) -> (char: Character, label: String?)? {
    let separators: Set<Character> = ["_", "-", "=", "~", "*"]
    var counts: [Character: Int] = [:]
    var order: [Character: Int] = [:]  // first-seen index for tiebreaking
    var labels: [Character: String] = [:]

    let pureDivider = /^[ \t]*([_\-=~*]{15,})[ \t]*$/
    let decoratedDivider = /^[ \t]*([_\-=~*]{5,})(.+?)[_\-=~*]{5,}[ \t]*$/

    for line in lines {
      let leadChar: Character?
      var lineLabel: String? = nil
      if let m = line.wholeMatch(of: pureDivider) {
        leadChar = m.1.first
      } else if let m = line.wholeMatch(of: decoratedDivider) {
        leadChar = m.1.first
        lineLabel = String(m.2).trimmingCharacters(in: .whitespacesAndNewlines)
        if lineLabel?.isEmpty == true { lineLabel = nil }
      } else {
        leadChar = nil
      }
      if let c = leadChar, separators.contains(c) {
        if order[c] == nil {
          order[c] = order.count
        }
        counts[c, default: 0] += 1
        if let label = lineLabel, labels[c] == nil {
          labels[c] = label
        }
      }
    }
    // Pick the most common separator char; break ties by first occurrence.
    guard let best = counts.max(by: {
      $0.value != $1.value ? $0.value < $1.value : (order[$0.key] ?? 0) > (order[$1.key] ?? 0)
    }) else { return nil }
    return (char: best.key, label: labels[best.key])
  }

  /// Decode a post's raw bytes into a string, trimming whitespace.
  /// Returns nil if the bytes are empty after trimming.
  private static func decodePostBytes(_ data: Data) -> String? {
    guard !data.isEmpty,
          let str = data.readString(at: 0, length: data.count) else {
      return nil
    }
    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Pattern matching a "From" header line: `From <name> (<date>)`
  /// Used to validate divider lines — only split when followed by a real
  /// header, not body text that happens to start with "From ".
  private static let fromHeaderPattern = /^From\s+\S.*\([^)]+\)/

  /// Check whether the next non-empty line after `index` looks like a
  /// "From" header, or there is no more content after the line.
  /// Used to validate that a divider line is a real post separator rather
  /// than ASCII art or decorative content.
  private static func nextNonEmptyLineIsHeader(in lines: [Data], after index: Int) -> Bool {
    for j in (index + 1)..<lines.count {
      let line = lines[j]
      if line.isEmpty || line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
        continue
      }
      // Decode as UTF-8, then Mac OS Roman for classic clients with
      // non-ASCII usernames.
      guard let str = String(data: line, encoding: .utf8)
              ?? String(data: line, encoding: .macOSRoman) else {
        return false
      }
      return str.firstMatch(of: fromHeaderPattern) != nil
    }
    // No more content after this divider — treat as a real trailing divider.
    return true
  }

  /// String-based variant of the header check.
  private static func nextNonEmptyLineIsHeader(in lines: [Substring], after index: Int) -> Bool {
    for j in (index + 1)..<lines.count {
      let line = lines[j]
      if line.allSatisfy(\.isWhitespace) {
        continue
      }
      return line.firstMatch(of: fromHeaderPattern) != nil
    }
    // No more content after this divider — treat as a real trailing divider.
    return true
  }

  /// Post to the message board
  ///
  /// - Parameter text: Message text
  public func postMessageBoard(_ text: String) async throws {
    guard !text.isEmpty else { return }

    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .oldPostNews)
    transaction.setFieldString(type: .data, val: text, encoding: .macOSRoman)

    try await self.socket.send(transaction, endian: .big)
  }

  // MARK: - Administration

  /// Get list of user accounts (requires admin access)
  ///
  /// - Returns: Array of user accounts sorted by login
  public func getAccounts() async throws -> [HotlineAccount] {
    let transaction = HotlineTransaction(id: self.generateTransactionID(), type: .getAccounts)
    let reply = try await self.sendTransaction(transaction)

    let accountFields = reply.getFieldList(type: .data)
    var accounts: [HotlineAccount] = []

    for data in accountFields {
      accounts.append(data.getAcccount())
    }

    accounts.sort { $0.name < $1.name }

    return accounts
  }

  /// Create a new user account (requires admin access)
  ///
  /// - Parameters:
  ///   - name: Display name for the user
  ///   - login: Login username
  ///   - password: Optional password (nil for no password)
  ///   - access: Access permissions bitmask
  public func createUser(name: String, login: String, password: String?, access: UInt64) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .newUser)

    transaction.setFieldString(type: .userName, val: name)
    transaction.setFieldEncodedString(type: .userLogin, val: login)
    transaction.setFieldUInt64(type: .userAccess, val: access)

    if let password {
      transaction.setFieldEncodedString(type: .userPassword, val: password)
    }

    try await self.sendTransaction(transaction)
  }

  /// Update an existing user account (requires admin access)
  ///
  /// - Parameters:
  ///   - name: Display name for the user
  ///   - login: Current login username
  ///   - newLogin: New login username (nil to keep current)
  ///   - password: Password update - nil to keep current, "" to remove, or new password string
  ///   - access: Access permissions bitmask
  public func setUser(name: String, login: String, newLogin: String?, password: String?, access: UInt64) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .setUser)
    transaction.setFieldString(type: .userName, val: name)
    transaction.setFieldUInt64(type: .userAccess, val: access)

    if let newLogin {
      transaction.setFieldEncodedString(type: .data, val: login)
      transaction.setFieldEncodedString(type: .userLogin, val: newLogin)
    } else {
      transaction.setFieldEncodedString(type: .userLogin, val: login)
    }

    // Password field handling:
    // - nil: Keep current password (send zero byte)
    // - "": Remove password (omit field)
    // - other: Set new password
    if password == nil {
      transaction.setFieldUInt8(type: .userPassword, val: 0)
    }
    else if password == "" {
      // Don't add password to transaction (password will be removed)
    }
    else {
      transaction.setFieldEncodedString(type: .userPassword, val: password!)
    }

    try await self.sendTransaction(transaction)
  }

  /// Delete a user account (requires admin access)
  ///
  /// - Parameter login: Login username to delete
  public func deleteUser(login: String) async throws {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .deleteUser)
    transaction.setFieldEncodedString(type: .userLogin, val: login)

    try await self.sendTransaction(transaction)
  }

  // MARK: - Banners

  /// Request to download the server banner image
  ///
  /// - Returns: Tuple of (referenceNumber, transferSize) for the banner download
  /// - Throws: HotlineClientError if not connected or server doesn't support banners
  public func downloadBanner() async throws -> (referenceNumber: UInt32, transferSize: Int)? {
    let transaction = HotlineTransaction(id: self.generateTransactionID(), type: .downloadBanner)
    let reply = try await self.sendTransaction(transaction)

    guard
      let transferSizeField = reply.getField(type: .transferSize),
      let transferSize = transferSizeField.getInteger(),
      let transferReferenceField = reply.getField(type: .referenceNumber),
      let referenceNumber = transferReferenceField.getUInt32()
    else {
      return nil
    }

    return (referenceNumber, transferSize)
  }

  // MARK: - Transfers

  /// Request to download a file
  ///
  /// - Parameters:
  ///   - name: File name to download
  ///   - path: Directory path containing the file
  ///   - preview: If true, request preview mode (smaller transfer)
  /// - Returns: Tuple of (referenceNumber, transferSize, fileSize, waitingCount) for the download
  public func downloadFile(name: String, path: [String], preview: Bool = false) async throws -> (referenceNumber: UInt32, transferSize: Int, fileSize: Int, waitingCount: Int)? {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .downloadFile)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)

    if preview {
      transaction.setFieldUInt32(type: .fileTransferOptions, val: 2)
    }

    let reply = try await self.sendTransaction(transaction)

    guard
      let transferSizeField = reply.getField(type: .transferSize),
      let transferSize = transferSizeField.getInteger(),
      let transferReferenceField = reply.getField(type: .referenceNumber),
      let referenceNumber = transferReferenceField.getUInt32()
    else {
      return nil
    }

    let fileSize = reply.getField(type: .fileSize)?.getInteger() ?? transferSize
    let waitingCount = reply.getField(type: .waitingCount)?.getInteger() ?? 0

    return (referenceNumber, transferSize, fileSize, waitingCount)
  }

  /// Request to download a folder
  ///
  /// - Parameters:
  ///   - name: Folder name to download
  ///   - path: Directory path containing the folder
  /// - Returns: Tuple of (referenceNumber, transferSize, itemCount, waitingCount) for the download
  public func downloadFolder(name: String, path: [String]) async throws -> (referenceNumber: UInt32, transferSize: Int, itemCount: Int, waitingCount: Int)? {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .downloadFolder)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)

    let reply = try await self.sendTransaction(transaction)

    guard
      let transferSizeField = reply.getField(type: .transferSize),
      let transferSize = transferSizeField.getInteger(),
      let transferReferenceField = reply.getField(type: .referenceNumber),
      let referenceNumber = transferReferenceField.getUInt32()
    else {
      return nil
    }

    let itemCount = reply.getField(type: .folderItemCount)?.getInteger() ?? 0
    let waitingCount = reply.getField(type: .waitingCount)?.getInteger() ?? 0

    return (referenceNumber, transferSize, itemCount, waitingCount)
  }

  /// Uploads a file to the server
  /// - Parameters:
  ///   - name: File name to upload
  ///   - path: Directory path where the file should be uploaded
  /// - Returns: Reference number for the upload transfer
  public func uploadFile(name: String, path: [String]) async throws -> UInt32? {
    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .uploadFile)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)

    let reply = try await self.sendTransaction(transaction)

    guard
      let transferReferenceField = reply.getField(type: .referenceNumber),
      let referenceNumber = transferReferenceField.getUInt32()
    else {
      return nil
    }

    return referenceNumber
  }
  
  /// Request to upload a folder
  ///
  /// - Parameters:
  ///   - name: Folder name to upload
  ///   - path: Directory path where the folder should be uploaded
  /// - Returns: Reference number for the upload transfer
  public func uploadFolder(name: String, path: [String], fileCount: UInt32, totalSize: UInt32) async throws -> UInt32? {
    print("HotlineClient: uploadFolder request - name='\(name)', path=\(path), fileCount=\(fileCount), totalSize=\(totalSize)")

    var transaction = HotlineTransaction(id: self.generateTransactionID(), type: .uploadFolder)
    transaction.setFieldString(type: .fileName, val: name)
    transaction.setFieldPath(type: .filePath, val: path)
    transaction.setFieldUInt32(type: .transferSize, val: totalSize)
    transaction.setFieldUInt16(type: .folderItemCount, val: UInt16(truncatingIfNeeded: fileCount))

    let reply = try await self.sendTransaction(transaction)

    guard
      let transferReferenceField = reply.getField(type: .referenceNumber),
      let referenceNumber = transferReferenceField.getUInt32()
    else {
      return nil
    }

    return referenceNumber
  }
}
