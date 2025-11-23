import SwiftUI

// MARK: - Connection Status

enum HotlineConnectionStatus: Equatable {
  case disconnected
  case connecting
  case connected
  case loggedIn
  case failed(String)
  
  var isLoggingIn: Bool {
    self == .connecting || self == .connected
  }

  var isConnected: Bool {
    return self == .connected || self == .loggedIn
  }
}

struct FileSearchConfig: Equatable {
  /// Number of folders we process before we start applying delay backoff.
  var initialBurstCount: Int = 15
  /// Base delay applied between folder requests during the backoff phase.
  var initialDelay: TimeInterval = 0.02
  /// Multiplier used to increase the delay after each processed folder in backoff.
  var backoffMultiplier: Double = 1.1
  /// Maximum delay cap so searches don't stall out during long walks.
  var maxDelay: TimeInterval = 1.0
  /// Maximum recursion depth allowed during file search.
  var maxDepth: Int = 40
  /// Limit for repeated folder loops (guards against circular server listings).
  var loopRepetitionLimit: Int = 4
  /// Number of child folders that get prioritized after a matching parent is found.
  var hotBurstLimit: Int = 2
  /// Maximum age, in seconds, that a cached folder listing is treated as fresh.
  var cacheTTL: TimeInterval = 60 * 15
  /// Upper bound on the number of folder listings retained in the cache.
  var maxCachedFolders: Int = 1024 * 3
}

enum FileSearchStatus: Equatable {
  case idle
  case searching(processed: Int, pending: Int)
  case completed(processed: Int)
  case cancelled(processed: Int)
  case failed(String)

  var isActive: Bool {
    if case .searching = self {
      return true
    }
    return false
  }
}

// MARK: - HotlineState

@Observable @MainActor
class HotlineState: Equatable {
  let id: UUID = UUID()

  nonisolated static func == (lhs: HotlineState, rhs: HotlineState) -> Bool {
    return lhs.id == rhs.id
  }

  // MARK: - Static Icon Data

  #if os(macOS)
  static func getClassicIcon(_ index: Int) -> NSImage? {
    return NSImage(named: "Classic/\(index)")
  }
  #elseif os(iOS)
  static func getClassicIcon(_ index: Int) -> UIImage? {
    return UIImage(named: "Classic/\(index)")
  }
  #endif

  static let classicIconSet: [Int] = [
    141, 149, 150, 151, 172, 184, 204,
    2013, 2036, 2037, 2055, 2400, 2505, 2534,
    2578, 2592, 4004, 4015, 4022, 4104, 4131,
    4134, 4136, 4169, 4183, 4197, 4240, 4247,
    128, 129, 130, 131, 132, 133, 134,
    135, 136, 137, 138, 139, 140, 142,
    143, 144, 145, 146, 147, 148, 152,
    153, 154, 155, 156, 157, 158, 159,
    160, 161, 162, 163, 164, 165, 166,
    167, 168, 169, 170, 171, 173, 174,
    175, 176, 177, 178, 179, 180, 181,
    182, 183, 185, 186, 187, 188, 189,
    190, 191, 192, 193, 194, 195, 196,
    197, 198, 199, 200, 201, 202, 203,
    205, 206, 207, 208, 209, 212, 214,
    215, 220, 233, 236, 237, 243, 244,
    277, 410, 414, 500, 666, 1250, 1251,
    1968, 1969, 2000, 2001, 2002, 2003, 2004,
    2006, 2007, 2008, 2009, 2010, 2011, 2012,
    2014, 2015, 2016, 2017, 2018, 2019, 2020,
    2021, 2022, 2023, 2024, 2025, 2026, 2027,
    2028, 2029, 2030, 2031, 2032, 2033, 2034,
    2035, 2038, 2040, 2041, 2042, 2043, 2044,
    2045, 2046, 2047, 2048, 2049, 2050, 2051,
    2052, 2053, 2054, 2056, 2057, 2058, 2059,
    2060, 2061, 2062, 2063, 2064, 2065, 2066,
    2067, 2070, 2071, 2072, 2073, 2075, 2079,
    2098, 2100, 2101, 2102, 2103, 2104, 2105,
    2106, 2107, 2108, 2109, 2110, 2112, 2113,
    2115, 2116, 2117, 2118, 2119, 2120, 2121,
    2122, 2123, 2124, 2125, 2126, 4150, 2223,
    2401, 2402, 2403, 2404, 2500, 2501, 2502,
    2503, 2504, 2506, 2507, 2528, 2529, 2530,
    2531, 2532, 2533, 2535, 2536, 2537, 2538,
    2539, 2540, 2541, 2542, 2543, 2544, 2545,
    2546, 2547, 2548, 2549, 2550, 2551, 2552,
    2553, 2554, 2555, 2556, 2557, 2558, 2559,
    2560, 2561, 2562, 2563, 2564, 2565, 2566,
    2567, 2568, 2569, 2570, 2571, 2572, 2573,
    2574, 2575, 2576, 2577, 2579, 2580, 2581,
    2582, 2583, 2584, 2585, 2586, 2587, 2588,
    2589, 2590, 2591, 2593, 2594, 2595, 2596,
    2597, 2598, 2599, 2600, 4000, 4001, 4002,
    4003, 4005, 4006, 4007, 4008, 4009, 4010,
    4011, 4012, 4013, 4014, 4016, 4017, 4018,
    4019, 4020, 4021, 4023, 4024, 4025, 4026,
    4027, 4028, 4029, 4030, 4031, 4032, 4033,
    4034, 4035, 4036, 4037, 4038, 4039, 4040,
    4041, 4042, 4043, 4044, 4045, 4046, 4047,
    4048, 4049, 4050, 4051, 4052, 4053, 4054,
    4055, 4056, 4057, 4058, 4059, 4060, 4061,
    4062, 4063, 4064, 4065, 4066, 4067, 4068,
    4069, 4070, 4071, 4072, 4073, 4074, 4075,
    4076, 4077, 4078, 4079, 4080, 4081, 4082,
    4083, 4084, 4085, 4086, 4087, 4088, 4089,
    4090, 4091, 4092, 4093, 4094, 4095, 4096,
    4097, 4098, 4099, 4100, 4101, 4102, 4103,
    4105, 4106, 4107, 4108, 4109, 4110, 4111,
    4112, 4113, 4114, 4115, 4116, 4117, 4118,
    4119, 4120, 4121, 4122, 4123, 4124, 4125,
    4126, 4127, 4128, 4129, 4130, 4132, 4133,
    4135, 4137, 4138, 4139, 4140, 4141, 4142,
    4143, 4144, 4145, 4146, 4147, 4148, 4149,
    4151, 4152, 4153, 4154, 4155, 4156, 4157,
    4158, 4159, 4160, 4161, 4162, 4163, 4164,
    4165, 4166, 4167, 4168, 4170, 4171, 4172,
    4173, 4174, 4175, 4176, 4177, 4178, 4179,
    4180, 4181, 4182, 4184, 4185, 4186, 4187,
    4188, 4189, 4190, 4191, 4192, 4193, 4194,
    4195, 4196, 4198, 4199, 4200, 4201, 4202,
    4203, 4204, 4205, 4206, 4207, 4208, 4209,
    4210, 4211, 4212, 4213, 4214, 4215, 4216,
    4217, 4218, 4219, 4220, 4221, 4222, 4223,
    4224, 4225, 4226, 4227, 4228, 4229, 4230,
    4231, 4232, 4233, 4234, 4235, 4236, 4238,
    4241, 4242, 4243, 4244, 4245, 4246, 4248,
    4249, 4250, 4251, 4252, 4253, 4254, 31337,
    6001, 6002, 6003, 6004, 6005, 6008, 6009,
    6010, 6011, 6012, 6013, 6014, 6015, 6016,
    6017, 6018, 6023, 6025, 6026, 6027, 6028,
    6029, 6030, 6031, 6032, 6033, 6034, 6035
  ]

  // MARK: - Observable State

  var status: HotlineConnectionStatus = .disconnected
  var server: Server? {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverVersion: UInt16 = 123
  var serverName: String? {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverTitle: String = ""
  var username: String = "guest"
  var iconID: Int = 414
  var access: HotlineUserAccessOptions?
  var agreed: Bool = false

  // Users
  var users: [User] = []

  // Chat
  var broadcastMessage: String = ""
  var chat: [ChatMessage] = []
  var chatInput: String = ""
  var unreadPublicChat: Bool = false

  // Instant Messages
  var instantMessages: [UInt16:[InstantMessage]] = [:]
  var unreadInstantMessages: [UInt16:UInt16] = [:]

  // Message Board
  var messageBoard: [String] = []
  var messageBoardLoaded: Bool = false

  // News
  var news: [NewsInfo] = []
  var newsLoaded: Bool = false
  private var newsLookup: [String:NewsInfo] = [:]

  // Files
  var files: [FileInfo] = []
  var filesLoaded: Bool = false

  // Accounts
  var accounts: [HotlineAccount] = []
  var accountsLoaded: Bool = false

  // Banner
  var bannerFileURL: URL? = nil
  var bannerImageFormat: Data.ImageFormat = .unknown
  #if os(macOS)
  var bannerImage: Image? = nil
  var bannerColors: ColorArt? = nil
  #elseif os(iOS)
  var bannerImage: UIImage? = nil
  #endif

  // Transfers (now stored globally in AppState)
  /// Returns all transfers associated with this server
  var transfers: [TransferInfo] {
    AppState.shared.transfers.filter { $0.serverID == self.id }
  }

  // Legacy transfer tracking (for old delegate-based downloads)
//  @ObservationIgnored private var downloads: [HotlineTransferClient] = []
  @ObservationIgnored private var bannerDownloadTask: Task<Void, Never>? = nil

  // File Search
  var fileSearchResults: [FileInfo] = []
  var fileSearchStatus: FileSearchStatus = .idle
  var fileSearchQuery: String = ""
  var fileSearchConfig = FileSearchConfig()
  var fileSearchScannedFolders: Int = 0
  var fileSearchCurrentPath: [String]? = nil
  @ObservationIgnored private var fileSearchSession: HotlineStateFileSearchSession? = nil
  @ObservationIgnored private var fileSearchResultKeys: Set<String> = []

  // File List Cache
  private struct FileListCacheEntry {
    let files: [FileInfo]
    let timestamp: Date
  }
  @ObservationIgnored private var fileListCache: [String: FileListCacheEntry] = [:]

  // Error Display
  var errorDisplayed: Bool = false
  var errorMessage: String? = nil

  // MARK: - Private State

  @ObservationIgnored private var client: HotlineClient?
  @ObservationIgnored private var eventTask: Task<Void, Never>?
  @ObservationIgnored private var chatSessionKey: ChatStore.SessionKey?
  @ObservationIgnored private var restoredChatSessionKey: ChatStore.SessionKey?
  @ObservationIgnored private var chatHistoryObserver: NSObjectProtocol?
  @ObservationIgnored private var lastPersistedMessageType: ChatMessageType?
  
  // MARK: - Initialization

  init() {
    self.chatHistoryObserver = NotificationCenter.default.addObserver(
      forName: ChatStore.historyClearedNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor [weak self] in
        self?.handleChatHistoryCleared()
      }
    }
  }

  deinit {
    if let observer = self.chatHistoryObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Connection

  @MainActor
  func login(server: Server, username: String, iconID: Int) async throws {
    print("HotlineState.login(): Starting login to \(server.address):\(server.port)")
    self.server = server
    self.username = username
    self.iconID = iconID
    self.status = .connecting
    print("HotlineState.login(): Status set to connecting")

    // Set up chat session
    let key = self.sessionKey(for: server)
    self.chatSessionKey = key
    self.restoredChatSessionKey = nil
    self.lastPersistedMessageType = nil
    self.chat = []
    self.restoreChatHistory(for: key)
    print("HotlineState.login(): Chat session set up")

    do {
      // Connect and login
      let loginInfo = HotlineLogin(
        login: server.login,
        password: server.password,
        username: username,
        iconID: UInt16(iconID)
      )

      print("HotlineState.login(): Calling HotlineClient.connect()...")
      let client = try await HotlineClient.connect(
        host: server.address,
        port: UInt16(server.port),
        login: loginInfo,
        useTLS: server.useTLS
      )
      print("HotlineState.login(): HotlineClient.connect() returned")

      self.client = client
      print("HotlineState.login(): Client stored")

      // Get server info
      print("HotlineState.login(): Getting server info...")
      if let serverInfo = await client.server {
        self.serverVersion = serverInfo.version
        if let name = serverInfo.name {
          self.serverName = name
        }
        print("HotlineState.login(): Server info retrieved: \(self.serverTitle) v\(serverInfo.version)")
      }

      self.status = .connected
      print("HotlineState.login(): Status set to connected")

      // Request initial data before starting event loop
      print("HotlineState.login(): Requesting user list...")
      try await self.getUserList()
      
      self.status = .loggedIn
      print("HotlineState.login(): Status set to loggedIn")

      if Prefs.shared.playSounds && Prefs.shared.playLoggedInSound {
        SoundEffects.play(.loggedIn)
      }

      print("HotlineState.login(): Connected to \(self.serverTitle)")
      print("HotlineState.login(): Scheduling post-login tasks...")

      // Defer event loop and post-login work to avoid layout recursion
      // This allows login() to return and SwiftUI to complete its layout pass
      // before we start receiving events that trigger state changes
      Task { @MainActor in
        print("HotlineState: Post-login: Starting event loop...")
        self.startEventLoop()

        print("HotlineState: Post-login: Sending preferences...")
        try? await self.sendUserPreferences()

        print("HotlineState: Post-login: Downloading banner...")
        self.downloadBanner()
      }

    }
    catch let clientError as HotlineClientError {
      switch clientError {
      case .connectionFailed(_):
        self.displayError(clientError, message: "This server appears to be offline.")
      case .loginFailed(let msg):
        self.displayError(clientError, message: msg)
      case .serverError(_, let msg):
        self.displayError(clientError, message: msg)
      default:
        self.displayError(clientError)
      }
      if let client = self.client {
        await client.disconnect()
        self.client = nil
      }
      self.status = .disconnected
      throw clientError
    }
    catch {
      print("HotlineState.login(): Login failed with error: \(error)")
      if let client = self.client {
        await client.disconnect()
        self.client = nil
      }
      self.status = .disconnected
      self.displayError(error)
      throw error
    }
  }
  
  private func displayError(_ error: Error, message: String? = nil) {
    self.errorDisplayed = true
    self.errorMessage = message ?? error.localizedDescription
  }

  /// Disconnect from the server (user-initiated)
  func disconnect() async {
    print("HotlineState.disconnect(): Called")
    guard let client = self.client else {
      print("HotlineState.disconnect(): No client, returning")
      return
    }

    // Stop event loop
    print("HotlineState.disconnect(): Cancelling event task...")
    self.eventTask?.cancel()
    self.eventTask = nil
    print("HotlineState.disconnect(): Event task cancelled")

    // Explicitly close the connection
    print("HotlineState.disconnect(): Calling client.disconnect()...")
    await client.disconnect()
    print("HotlineState.disconnect(): client.disconnect() returned")

    // Clean up state
    print("HotlineState.disconnect(): Calling handleConnectionClosed()...")
    self.handleConnectionClosed()
    print("HotlineState.disconnect(): disconnect() complete")
  }

  /// Handle connection closure (server-initiated or after user disconnect)
  private func handleConnectionClosed() {
    print("HotlineState: handleConnectionClosed() entered")
    guard self.client != nil else {
      print("HotlineState: handleConnectionClosed() - client already nil, returning")
      return
    }

    print("HotlineState: Handling connection closure - recording chat...")

    // Record disconnect in chat history
    if self.status == .loggedIn {
      let message = ChatMessage(text: "Disconnected", type: .signOut, date: Date())
      self.recordChatMessage(message, persist: true, display: false)
    }

    print("HotlineState: Cancelling banner and downloads...")

    self.bannerDownloadTask?.cancel()
    self.bannerDownloadTask = nil

    // Cancel all downloads (both old delegate-based and new async downloads)
//    self.downloads = []

    // Cancel all transfers for this server
//    self.cancelAllDownloads()

    // Cancel file search
    self.fileSearchSession?.cancel()
    self.fileSearchSession = nil

    // Clear client reference
    self.client = nil

    print("HotlineState: Resetting state properties...")

    // Reset state immediately (constraint loop was caused by something else)
    self.status = .disconnected
    self.serverVersion = 123
    self.serverName = nil
    self.access = nil
    self.agreed = false
    self.users = []
    self.chat = []
    self.instantMessages = [:]
    self.unreadInstantMessages = [:]
    self.unreadPublicChat = false
    self.messageBoard = []
    self.messageBoardLoaded = false
    self.news = []
    self.newsLoaded = false
    self.newsLookup = [:]
    self.files = []
    self.filesLoaded = false
    self.accounts = []
    self.accountsLoaded = false
    self.bannerImage = nil
    self.bannerColors = nil

    print("HotlineState: Resetting file search...")
    self.resetFileSearchState()

    self.chatSessionKey = nil
    self.restoredChatSessionKey = nil
    self.lastPersistedMessageType = nil

    print("HotlineState: Disconnected")
  }

  @MainActor
  func downloadBanner(force: Bool = false) {
    guard self.serverVersion >= 150 else {
      return
    }
    
    if force {
      self.bannerDownloadTask?.cancel()
      self.bannerDownloadTask = nil
      self.bannerImage = nil
      self.bannerImageFormat = .unknown
      self.bannerFileURL = nil
      self.bannerColors = nil
    } else if self.bannerDownloadTask != nil || self.bannerFileURL != nil {
      return
    }

    let task = Task { @MainActor [weak self] in
      defer {
        self?.bannerDownloadTask = nil
      }

      guard let self else { return }
      guard let client = self.client,
            let server = self.server,
            let result = try? await client.downloadBanner(),
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        return
      }

      do {
        print("HotlineState: Banner download info - reference: \(result.referenceNumber), transferSize: \(result.transferSize)")

        let previewClient = HotlineFilePreviewClient(
          fileName: "banner",
          address: address,
          port: UInt16(port),
          reference: result.referenceNumber,
          size: UInt32(result.transferSize),
          useTLS: server.useTLS
        )

        let fileURL = try await previewClient.preview()
        
        if let oldFileURL = self.bannerFileURL {
          try? FileManager.default.removeItem(at: oldFileURL)
        }

        guard self.client != nil else { return }

        let data = try Data(contentsOf: fileURL)
        self.bannerImageFormat = data.detectedImageFormat
        
        print("HotlineState: Banner download complete, data size: \(data.count) bytes")

#if os(macOS)
        guard let image = NSImage(data: data) else {
          print("HotlineState: Failed to create NSImage from banner data")
          return
        }
        let blah = Image(nsImage: image)
#elseif os(iOS)
        guard let image = UIImage(data: data) else {
          print("HotlineState: Failed to create UIImage from banner data")
          return
        }
        self.bannerImage = Image(uiImage: image)
#endif
        self.bannerFileURL = fileURL
        self.bannerImage = blah
        self.bannerColors = ColorArt.analyze(image: image)
        
      } catch {
        print("HotlineState: Banner download failed: \(error)")
      }
    }

    self.bannerDownloadTask = task
  }

  // MARK: - Event Loop

  private func startEventLoop() {
    print("HotlineState.startEventLoop(): Called")
    guard let client = self.client else {
      print("HotlineState.startEventLoop(): No client, returning")
      return
    }

    print("HotlineState.startEventLoop(): Creating event loop task")
    self.eventTask = Task { @MainActor [weak self, client] in
      guard let self else {
        print("HotlineState.startEventLoop(): Self is nil in task, exiting")
        return
      }

      print("HotlineState.startEventLoop(): Event loop started, awaiting events...")
      for await event in client.events {
        print("HotlineState.startEventLoop(): Received event: \(event)")
        self.handleEvent(event)
      }

      // Event stream ended - server disconnected us
      print("HotlineState.startEventLoop(): Event stream ended, calling handleConnectionClosed()...")
      self.handleConnectionClosed()
      print("HotlineState.startEventLoop(): handleConnectionClosed() returned, event loop task complete")
    }
    print("HotlineState.startEventLoop(): Event loop task created")
  }

  @MainActor
  private func handleEvent(_ event: HotlineEvent) {
    switch event {
    case .chatMessage(let text):
      self.handleChatMessage(text)

    case .userChanged(let user):
      self.handleUserChanged(user)

    case .userDisconnected(let userID):
      self.handleUserDisconnected(userID)

    case .serverMessage(let message):
      self.handleServerMessage(message)

    case .privateMessage(let userID, let message):
      self.handlePrivateMessage(userID: userID, message: message)

    case .newsPost(let message):
      self.handleNewsPost(message)

    case .agreementRequired(let text):
      let message = ChatMessage(text: text, type: .agreement, date: Date())
      self.recordChatMessage(message, persist: false)

    case .userAccess(let options):
      self.access = options
      print("HotlineState: Got access options")
      HotlineUserAccessOptions.printAccessOptions(options)
    }
  }

  // MARK: - Chat
  
  @MainActor
  func sendBroadcast(_ message: String) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }
    
    try await client.sendBroadcast(message)
  }

  @MainActor
  func sendChat(_ text: String, announce: Bool = false) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.sendChat(text, announce: announce)
  }

  @MainActor
  func sendInstantMessage(_ text: String, userID: UInt16) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let message = InstantMessage(
      direction: .outgoing,
      text: text.convertingLinksToMarkdown(),
      type: .message,
      date: Date()
    )

    if self.instantMessages[userID] == nil {
      self.instantMessages[userID] = [message]
    } else {
      self.instantMessages[userID]!.append(message)
    }

    try await client.sendInstantMessage(text, to: userID)

    if Prefs.shared.playPrivateMessageSound {
      SoundEffects.play(.chatMessage)
    }
  }

  @MainActor
  func sendAgree() async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.sendAgree()
    self.agreed = true
  }

  @MainActor
  /// Send current user preferences from Prefs to the server
  func sendUserPreferences() async throws {
    var options: HotlineUserOptions = []

    if Prefs.shared.refusePrivateMessages {
      options.update(with: .refusePrivateMessages)
    }

    if Prefs.shared.refusePrivateChat {
      options.update(with: .refusePrivateChat)
    }

    if Prefs.shared.enableAutomaticMessage {
      options.update(with: .automaticResponse)
    }

    print("HotlineState.sendUserPreferences(): Updating user info with server")

    try await self.sendUserInfo(
      username: Prefs.shared.username,
      iconID: Prefs.shared.userIconID,
      options: options,
      autoresponse: Prefs.shared.automaticMessage
    )
  }

  func sendUserInfo(username: String, iconID: Int, options: HotlineUserOptions = [], autoresponse: String? = nil) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    self.username = username
    self.iconID = iconID

    try await client.setClientUserInfo(
      username: username,
      iconID: UInt16(iconID),
      options: options,
      autoresponse: autoresponse
    )
  }

  func markPublicChatAsRead() {
    self.unreadPublicChat = false
  }

  func hasUnreadInstantMessages(userID: UInt16) -> Bool {
    return self.unreadInstantMessages[userID] != nil
  }

  func markInstantMessagesAsRead(userID: UInt16) {
    self.unreadInstantMessages.removeValue(forKey: userID)
  }

  @MainActor
  func searchChat(query: String) -> [ChatMessage] {
    guard !query.isEmpty else {
      return []
    }

    // Create a map of all messages by ID to deduplicate
    var messageMap: [UUID: ChatMessage] = [:]

    // Add current in-memory messages
    for message in self.chat {
      messageMap[message.id] = message
    }

    // Filter messages based on query
    let filteredMessages = messageMap.values.filter { message in
      // Never include agreement messages
      if message.type == .agreement {
        return false
      }

      // Always include disconnect messages to show session boundaries
      let isDisconnect = message.type == .signOut

      // Search in text and username
      let matchesText = message.text.localizedCaseInsensitiveContains(query)
      let matchesUsername = message.username?.localizedCaseInsensitiveContains(query) == true
      let matchesQuery = matchesText || matchesUsername

      return isDisconnect || matchesQuery
    }

    // Sort by date to maintain chronological order
    let sortedMessages = filteredMessages.sorted { $0.date < $1.date }

    // Remove consecutive disconnect messages to avoid visual clutter
    var deduplicated: [ChatMessage] = []
    var lastWasDisconnect = false

    for message in sortedMessages {
      let isDisconnect = message.type == .signOut

      if isDisconnect && lastWasDisconnect {
        continue
      }

      deduplicated.append(message)
      lastWasDisconnect = isDisconnect
    }

    // Remove leading disconnect message
    if deduplicated.first?.type == .signOut {
      deduplicated.removeFirst()
    }

    // Remove trailing disconnect message
    if deduplicated.last?.type == .signOut {
      deduplicated.removeLast()
    }

    return deduplicated
  }

  // MARK: - Users

  func getUserList() async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let hotlineUsers = try await client.getUserList()
    self.users = hotlineUsers.map { User(hotlineUser: $0) }
  }
  
  func getClientInfoText(id userID: UInt16) async throws -> HotlineUserClientInfo? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }
    
    do {
      return try await client.getClientInfoText(for: userID)
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }
    
    return nil
  }
  
  func disconnectUser(id userID: UInt16, options: HotlineUserDisconnectOptions?) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }
    
    do {
      try await client.disconnectUser(userID: userID, options: options)
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }
  }

  // MARK: - Files
  
  @discardableResult
  func getFileList(path: [String] = [], suppressErrors: Bool = false, preferCache: Bool = false) async throws -> [FileInfo]? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }
    
    // Check cache first if preferred
    if preferCache, let cached = self.cachedFileList(for: path, ttl: self.fileSearchConfig.cacheTTL, allowStale: false) {
      return cached.items
    }
    
    let hotlineFiles: [HotlineFile]
    do {
      hotlineFiles = try await client.getFileList(path: path)
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
      self.filesLoaded = true
      return nil
    }
    
    let newFiles = hotlineFiles.map { FileInfo(hotlineFile: $0) }

    // Update UI state
    if path.isEmpty {
      self.filesLoaded = true
      self.files = newFiles
    } else {
      // Update parent's children
      let parentFile = self.findFile(in: self.files, at: path)
      parentFile?.children = newFiles
    }

    // Cache the result
    self.storeFileListInCache(newFiles, for: path)

    return newFiles
  }

  func getFileDetails(_ fileName: String, path: [String]) async throws -> FileDetails? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    return try await client.getFileInfo(name: fileName, path: fullPath)
  }
  
  @discardableResult
  func setFileInfo(fileName: String, path filePath: [String], fileNewName: String?, comment: String?) async throws -> Bool {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }
    
    do {
      try await client.setFileInfo(name: fileName, path: filePath, newName: fileNewName, comment: comment)
      self.invalidateFileListCache(for: filePath, includingAncestors: true)
      return true
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }
    
    return false
  }
  
  @discardableResult
  func newFolder(name: String, parentPath: [String]) async throws -> Bool {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }
    
    do {
      try await client.newFolder(name: name, path: parentPath)
      self.invalidateFileListCache(for: parentPath, includingAncestors: true)
      return true
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }
    
    return false
  }

  @discardableResult
  @MainActor
  func deleteFile(_ fileName: String, path: [String]) async throws -> Bool {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }
    
    do {
      try await client.deleteFile(name: fileName, path: fullPath)
      self.invalidateFileListCache(for: fullPath, includingAncestors: true)
      return true
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }
    
    return false
  }

  /// Download a file from the server.
  ///
  /// - Parameters:
  ///   - fileName: Name of the file to download
  ///   - path: Path components to the file (includes the filename as last component)
  ///   - destination: Optional destination URL. If nil, downloads to Downloads folder.
  ///   - progressCallback: Optional callback for progress updates (receives TransferInfo and progress 0.0-1.0)
  ///   - callback: Optional completion callback (receives TransferInfo and final file URL)
  @MainActor
  func downloadFile(_ fileName: String, path: [String], to destination: URL? = nil, progress progressCallback: ((TransferInfo) -> Void)? = nil, complete callback: ((TransferInfo) -> Void)? = nil) {
    guard let client = self.client else { return }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      
      // Request download from server
      let result: (referenceNumber: UInt32, transferSize: Int, fileSize: Int, waitingCount: Int)?
      do {
        result = try await client.downloadFile(name: fileName, path: fullPath)
      }
      catch let error as HotlineClientError {
        self.displayError(error, message: error.userMessage)
        return
      }
      
      guard let result,
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        return
      }

      let referenceNumber = result.referenceNumber

      // Create transfer info for tracking (stored globally in AppState)
      let transfer = TransferInfo(
        reference: referenceNumber,
        title: fileName,
        size: UInt(result.transferSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.isUpload = false
      transfer.downloadCallback = callback
      transfer.progressCallback = progressCallback
      AppState.shared.addTransfer(transfer)

      // Create download client
      let downloadClient = HotlineFileDownloadClient(
        address: address,
        port: UInt16(port),
        reference: referenceNumber,
        size: UInt32(result.transferSize),
        useTLS: server.useTLS
      )

      // Create and store the download task
      let downloadTask = Task { @MainActor [weak self] in
        guard self != nil else { return }

        do {
          // Download file with progress tracking
          let location: HotlineDownloadLocation = if let destination {
            .url(destination)
          } else {
            .downloads(fileName)
          }

          let fileURL: URL = try await downloadClient.download(to: location) { progress in
            switch progress {
            case .preparing: break
            case .unconnected, .connected, .connecting:
              transfer.progressCallback?(transfer)
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
              transfer.progressCallback?(transfer)
            case .error(_):
              transfer.failed = true
            case .completed(url: let url):
              transfer.completed = true
              transfer.fileURL = url
            }
          }
          
          // Mark as completed
          transfer.progress = 1.0
          
          // Call completion callback
          transfer.downloadCallback?(transfer)
          fileURL.notifyDownloadFinished()

          print("HotlineState: Download complete - \(fileURL.path)")

        } catch is CancellationError {
          // Download was cancelled
          transfer.cancelled = true
          print("HotlineState: Download cancelled")
          
        } catch {
          // Mark as failed
          transfer.failed = true
          print("HotlineState: Download failed - \(error)")
        }
        
        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store the task in AppState so it can be cancelled later
      AppState.shared.registerTransferTask(downloadTask, transferID: transfer.id, client: downloadClient)
    }
  }

  /// Download a folder and its contents from the server.
  ///
  /// - Parameters:
  ///   - folderName: Name of the folder to download
  ///   - path: Path components to the folder (includes the foldername as last component)
  ///   - destination: Optional destination URL. If nil, downloads to Downloads folder.
  ///   - progressCallback: Optional callback for progress updates (receives TransferInfo)
  ///   - itemProgressCallback: Optional callback for per-item updates (receives TransferInfo with current file info)
  ///   - callback: Optional completion callback (receives TransferInfo and final folder URL)
  @MainActor
  func downloadFolder(
    _ folderName: String,
    path: [String],
    to destination: URL? = nil,
    progress progressCallback: ((TransferInfo) -> Void)? = nil,
//    itemProgress itemProgressCallback: ((TransferInfo, String, Int, Int) -> Void)? = nil,
    complete callback: ((TransferInfo) -> Void)? = nil
  ) {
    guard let client = self.client else { return }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    Task { @MainActor [weak self] in
      guard let self else { return }

      // Request folder download from server
      guard let result = try? await client.downloadFolder(name: folderName, path: fullPath),
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        return
      }

      let referenceNumber = result.referenceNumber

      // Create transfer info for tracking (stored globally in AppState)
      let transfer = TransferInfo(
        reference: referenceNumber,
        title: folderName,
        size: UInt(result.transferSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.isFolder = true
      transfer.folderName = folderName
      transfer.isUpload = false
      transfer.downloadCallback = callback
      transfer.progressCallback = progressCallback
      AppState.shared.addTransfer(transfer)

      // Create download client
      let downloadClient = HotlineFolderDownloadClient(
        address: address,
        port: UInt16(port),
        reference: referenceNumber,
        size: UInt32(result.transferSize),
        itemCount: result.itemCount,
        useTLS: server.useTLS
      )

      // Create and store the download task
      let downloadTask = Task { @MainActor [weak self] in
        guard self != nil else { return }

        do {
          // Download folder with progress tracking
          let location: HotlineDownloadLocation = if let destination {
            .url(destination)
          } else {
            .downloads(folderName)
          }

          let folderURL = try await downloadClient.download(to: location, progress: { progress in
            switch progress {
            case .preparing:
              break
            case .unconnected, .connected, .connecting:
              transfer.progressCallback?(transfer)
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
              transfer.progressCallback?(transfer)
            case .error(_):
              transfer.failed = true
            case .completed(url: let url):
              transfer.completed = true
              transfer.fileURL = url
            }
          }, items: { item in
            transfer.title = item.fileName
            transfer.fileName = item.fileName
          })

          // Mark as completed
          transfer.progress = 1.0
          transfer.fileName = nil
          transfer.title = folderName // Reset title to folder name

          // Call completion callback
          transfer.downloadCallback?(transfer)
          
          folderURL.notifyDownloadFinished()

          print("HotlineState: Folder download complete - \(folderURL.path)")

        } catch is CancellationError {
          // Download was cancelled
          print("HotlineState: Folder download cancelled")
        } catch {
          // Mark as failed
          transfer.failed = true
          print("HotlineState: Folder download failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store transfer
      AppState.shared.registerTransferTask(downloadTask, transferID: transfer.id)
    }
  }

  /// Upload a folder to the server.
  ///
  /// - Parameters:
  ///   - folderURL: URL to the folder on disk to upload
  ///   - path: Destination path on the server where the folder should be uploaded
  ///   - progressCallback: Optional callback for progress updates (receives TransferInfo)
  ///   - itemProgressCallback: Optional callback for per-item updates (receives TransferInfo with current file info)
  ///   - callback: Optional completion callback (receives TransferInfo when upload is complete)
  @MainActor
  func uploadFolder(
    url folderURL: URL,
    path: [String],
    progress progressCallback: ((TransferInfo) -> Void)? = nil,
    itemProgress itemProgressCallback: ((TransferInfo, String, Int, Int) -> Void)? = nil,
    complete callback: ((TransferInfo) -> Void)? = nil
  ) {
    guard let client = self.client else { return }

    let folderName = folderURL.lastPathComponent

    guard folderURL.isFileURL, !folderName.isEmpty else {
      print("HotlineState: Not a valid folder URL")
      return
    }

    let folderPath = folderURL.path(percentEncoded: false)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory),
          isDirectory.boolValue == true else {
      print("HotlineState: URL is not a folder")
      return
    }

    // Get the total size of the folder (all files)
    guard let (folderSize, fileCount) = FileManager.default.getFolderSize(folderURL) else {
      print("HotlineState: Could not determine folder size")
      return
    }

    print("HotlineState: Requesting upload for folder '\(folderName)' - \(fileCount) items, \(folderSize) bytes total")

    Task { @MainActor [weak self] in
      guard let self else { return }

      // Request folder upload from server.
      // The enumerator already omits the root folder, so report the full item count the server should expect.
      let reportedItemCount = fileCount
      print("HotlineState: Reporting \(reportedItemCount) items to server (enumerated count)")
      guard let referenceNumber = try? await client.uploadFolder(name: folderName, path: path, fileCount: reportedItemCount, totalSize: UInt32(folderSize)),
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        print("HotlineState: Failed to get upload reference from server")
        return
      }

      // Invalidate cache for the upload destination
      self.invalidateFileListCache(for: path, includingAncestors: true)

      print("HotlineState: Got folder upload reference: \(referenceNumber)")

      // Create upload client
      guard let uploadClient = HotlineFolderUploadClient(
        folderURL: folderURL,
        address: address,
        port: UInt16(port),
        reference: referenceNumber,
        useTLS: server.useTLS
      ) else {
        print("HotlineState: Failed to create folder upload client")
        return
      }

      // Create transfer info for tracking (stored globally in AppState)
      let transfer = TransferInfo(
        reference: referenceNumber,
        title: folderName,
        size: UInt(folderSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.isFolder = true
      transfer.isUpload = true
      transfer.uploadCallback = callback
      transfer.progressCallback = progressCallback
      AppState.shared.addTransfer(transfer)

      // Create and store the upload task
      let uploadTask = Task { @MainActor [weak self] in
        guard self != nil else { return }

        do {
          // Upload folder with progress tracking
          try await uploadClient.upload(progress: { progress in
            switch progress {
            case .preparing:
              break
            case .unconnected, .connected, .connecting:
              break
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
              transfer.progressCallback?(transfer)
            case .error(_):
              transfer.failed = true
            case .completed(url: _):
              transfer.completed = true
            }
          }, itemProgress: { itemInfo in
            // Update transfer title with current file being uploaded
            transfer.title = "\(itemInfo.fileName) (\(itemInfo.itemNumber)/\(itemInfo.totalItems))"
            itemProgressCallback?(transfer, itemInfo.fileName, itemInfo.itemNumber, itemInfo.totalItems)
          })

          // Mark as completed
          transfer.progress = 1.0
          transfer.title = folderName // Reset title to folder name

          // Call completion callback
          transfer.uploadCallback?(transfer)

          print("HotlineState: Folder upload complete - \(folderName)")

        } catch is CancellationError {
          // Upload was cancelled
          print("HotlineState: Folder upload cancelled")
        } catch {
          // Mark as failed
          transfer.failed = true
          print("HotlineState: Folder upload failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store the task in AppState so it can be cancelled later
      AppState.shared.registerTransferTask(uploadTask, transferID: transfer.id)
    }
  }

  func uploadFile(url fileURL: URL, path: [String], complete callback: ((TransferInfo) -> Void)? = nil) {
    guard let client = self.client else { return }

    let fileName = fileURL.lastPathComponent
    
    print("UPLOAD FILE: \(fileName) \(fileURL)")

    guard fileURL.isFileURL, !fileName.isEmpty else {
      print("HotlineState: Not a valid file URL")
      return
    }

    let filePath = fileURL.path(percentEncoded: false)

    var fileIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: filePath, isDirectory: &fileIsDirectory),
          fileIsDirectory.boolValue == false else {
      print("HotlineState: File is a directory")
      return
    }

    // Get the flattened file size (includes all forks and headers)
    guard let payloadSize = FileManager.default.getFlattenedFileSize(fileURL) else {
      print("HotlineState: Could not determine file size")
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      
      let referenceNumber: UInt32?
      
      do {
        referenceNumber = try await client.uploadFile(name: fileName, path: path)
      }
      catch let error as HotlineClientError {
        self.displayError(error, message: error.userMessage)
        return
      }
      

      // Request upload from server
      guard let referenceNumber,
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        print("HotlineState: Failed to get upload reference from server")
        return
      }
      
      // Invalidate cache for the upload destination
      self.invalidateFileListCache(for: path, includingAncestors: true)

      print("HotlineState: Got upload reference: \(referenceNumber)")

      // Create upload client
      guard let uploadClient = HotlineFileUploadClient(
        fileURL: fileURL,
        address: address,
        port: UInt16(port),
        reference: referenceNumber,
        useTLS: server.useTLS
      ) else {
        print("HotlineState: Failed to create upload client")
        return
      }

      // Create transfer info for tracking (stored globally in AppState)
      let transfer = TransferInfo(
        reference: referenceNumber,
        title: fileName,
        size: UInt(payloadSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.isUpload = true
      transfer.uploadCallback = callback
      AppState.shared.addTransfer(transfer)

      // Create and store the upload task
      let uploadTask = Task { @MainActor [weak self] in
        guard self != nil else { return }

        do {
          // Upload file with progress tracking
          try await uploadClient.upload { progress in
            switch progress {
            case .preparing:
              break
            case .unconnected, .connected, .connecting:
              break
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
            case .error(_):
              transfer.failed = true
            case .completed(url: _):
              transfer.completed = true
            }
          }

          // Mark as completed
          transfer.progress = 1.0

          // Call completion callback
          transfer.uploadCallback?(transfer)

          print("HotlineState: Upload complete - \(fileName)")

        } catch is CancellationError {
          // Upload was cancelled
          print("HotlineState: Upload cancelled")
        } catch {
          // Mark as failed
          transfer.failed = true
          print("HotlineState: Upload failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store the transfer
      AppState.shared.registerTransferTask(uploadTask, transferID: transfer.id)
    }
  }

  @MainActor
  func previewFile(_ fileName: String, path: [String], complete callback: ((PreviewFileInfo?) -> Void)? = nil) {
    guard let client = self.client else {
      callback?(nil)
      return
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    Task { @MainActor in
      guard let result = try? await client.downloadFile(name: fileName, path: fullPath, preview: true),
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        callback?(nil)
        return
      }

      let info = PreviewFileInfo(
        id: result.referenceNumber,
        address: address,
        port: port,
        size: result.transferSize,
        name: fileName,
        useTLS: server.useTLS
      )

      callback?(info)
    }
  }

  // MARK: - User Administration

  @MainActor
  func getAccounts() async throws -> [HotlineAccount] {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    self.accounts = try await client.getAccounts()
    self.accountsLoaded = true
    return self.accounts
  }

  @MainActor
  func createUser(name: String, login: String, password: String?, access: UInt64) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.createUser(name: name, login: login, password: password, access: access)

    // Refresh accounts list
    self.accounts = try await client.getAccounts()
  }

  @MainActor
  func setUser(name: String, login: String, newLogin: String?, password: String?, access: UInt64) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.setUser(name: name, login: login, newLogin: newLogin, password: password, access: access)

    // Refresh accounts list
    self.accounts = try await client.getAccounts()
  }

  @MainActor
  func deleteUser(login: String) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.deleteUser(login: login)

    // Refresh accounts list
    self.accounts = try await client.getAccounts()
  }

  // MARK: - Message Board

  @MainActor
  func getMessageBoard() async throws -> [String] {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    self.messageBoard = try await client.getMessageBoard()
    self.messageBoardLoaded = true
    return self.messageBoard
  }

  @MainActor
  func postToMessageBoard(text: String) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.postMessageBoard(text)
  }

  // MARK: - News

  @MainActor
  func getNewsList(at path: [String] = []) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let parentNewsGroup = self.findNews(in: self.news, at: path)

    // Send a categories request for bundle paths or root (empty path)
    if path.isEmpty || parentNewsGroup?.type == .bundle {
      print("HotlineState: Requesting categories at: /\(path.joined(separator: "/"))")

      let categories = try await client.getNewsCategories(path: path)

      // Create info for each category returned
      var newCategoryInfos: [NewsInfo] = []

      // Transform hotline categories into NewsInfo objects
      for category in categories {
        var newsCategoryInfo = NewsInfo(hotlineNewsCategory: category)

        if let lookupPath = newsCategoryInfo.lookupPath {
          // Merge returned category info with existing category info
          if let existingCategoryInfo = self.newsLookup[lookupPath] {
            print("HotlineState: Merging category into existing category at \(lookupPath)")

            existingCategoryInfo.count = newsCategoryInfo.count
            existingCategoryInfo.name = newsCategoryInfo.name
            existingCategoryInfo.path = newsCategoryInfo.path
            existingCategoryInfo.categoryID = newsCategoryInfo.categoryID
            newsCategoryInfo = existingCategoryInfo
          } else {
            print("HotlineState: New category added at \(lookupPath)")
            self.newsLookup[lookupPath] = newsCategoryInfo
          }
        }

        newCategoryInfos.append(newsCategoryInfo)
      }

      if let parent = parentNewsGroup {
        parent.children = newCategoryInfos
      } else if path.isEmpty {
        self.newsLoaded = true
        self.news = newCategoryInfos
      }
    } else {
      print("HotlineState: Requesting articles at: /\(path.joined(separator: "/"))")

      let articles = try await client.getNewsArticles(path: path)

      print("HotlineState: Organizing news at \(path.joined(separator: "/"))")

      // Create info for each article returned
      var newArticleInfos: [NewsInfo] = []

      for article in articles {
        var newsArticleInfo = NewsInfo(hotlineNewsArticle: article)

        if let lookupPath = newsArticleInfo.lookupPath {
          // Merge returned category info with existing category info
          if let existingArticleInfo = self.newsLookup[lookupPath] {
            print("HotlineState: Merging article into existing article at \(lookupPath)")

            existingArticleInfo.count = newsArticleInfo.count
            existingArticleInfo.name = newsArticleInfo.name
            existingArticleInfo.path = newsArticleInfo.path
            existingArticleInfo.articleUsername = newsArticleInfo.articleUsername
            existingArticleInfo.articleDate = newsArticleInfo.articleDate
            existingArticleInfo.articleFlavors = newsArticleInfo.articleFlavors
            existingArticleInfo.articleID = newsArticleInfo.articleID
            newsArticleInfo = existingArticleInfo
          } else {
            print("HotlineState: New article added at \(lookupPath)")
            self.newsLookup[lookupPath] = newsArticleInfo
          }
        }

        newArticleInfos.append(newsArticleInfo)
      }

      let organizedNewsArticles: [NewsInfo] = self.organizeNewsArticles(newArticleInfos)
      if let parent = parentNewsGroup {
        parent.children = organizedNewsArticles
      }
    }
  }

  @MainActor
  func getNewsArticle(id articleID: UInt, at path: [String], flavor: String = "text/plain") async throws -> String? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    return try await client.getNewsArticle(id: UInt32(articleID), path: path, flavor: flavor)
  }

  @MainActor
  func postNewsArticle(title: String, body: String, at path: [String], parentID: UInt32 = 0) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.postNewsArticle(title: title, text: body, path: path, parentID: parentID)
    print("HotlineState: News article posted")
  }

  // MARK: - File Search

  @MainActor
  func startFileSearch(query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      self.cancelFileSearch()
      return
    }

    self.fileSearchSession?.cancel()
    self.resetFileSearchState()
    self.fileSearchQuery = trimmed
    self.fileSearchStatus = .searching(processed: 0, pending: 0)
    self.fileSearchScannedFolders = 0
    self.fileSearchCurrentPath = []

    let session = HotlineStateFileSearchSession(hotlineState: self, query: trimmed, config: self.fileSearchConfig)
    self.fileSearchSession = session

    Task { await session.start() }
  }

  @MainActor
  func cancelFileSearch(clearResults: Bool = true) {
    guard let session = self.fileSearchSession else {
      if clearResults {
        self.resetFileSearchState()
      } else if !self.fileSearchResults.isEmpty {
        self.fileSearchStatus = .cancelled(processed: self.fileSearchScannedFolders)
        self.fileSearchCurrentPath = nil
      }
      return
    }

    session.cancel()
    self.fileSearchSession = nil
    self.fileSearchCurrentPath = nil

    if clearResults {
      self.resetFileSearchState()
    } else {
      self.fileSearchStatus = .cancelled(processed: self.fileSearchScannedFolders)
    }
  }

  @MainActor
  func clearFileListCache() {
    guard !self.fileListCache.isEmpty else {
      return
    }

    self.fileListCache.removeAll(keepingCapacity: false)
  }

  @MainActor
  fileprivate func searchSession(_ session: HotlineStateFileSearchSession, didEmit matches: [FileInfo], processed: Int, pending: Int) {
    guard self.fileSearchSession === session else {
      return
    }

    var appended: [FileInfo] = []
    for match in matches {
      let key = self.searchPathKey(for: match.path)
      if self.fileSearchResultKeys.insert(key).inserted {
        appended.append(match)
      }
    }

    if !appended.isEmpty {
      self.fileSearchResults.append(contentsOf: appended)
    }

    self.fileSearchScannedFolders = processed
    self.fileSearchStatus = .searching(processed: processed, pending: pending)
  }

  @MainActor
  fileprivate func searchSession(_ session: HotlineStateFileSearchSession, didFocusOn path: [String]) {
    guard self.fileSearchSession === session else {
      return
    }

    self.fileSearchCurrentPath = path
  }

  @MainActor
  fileprivate func searchSessionDidFinish(_ session: HotlineStateFileSearchSession, processed: Int, pending: Int, completed: Bool) {
    guard self.fileSearchSession === session else {
      return
    }

    self.fileSearchScannedFolders = processed
    self.fileSearchSession = nil
    self.fileSearchCurrentPath = nil

    if completed {
      self.fileSearchStatus = .completed(processed: processed)
    } else {
      self.fileSearchStatus = .cancelled(processed: processed)
    }
  }

  fileprivate func cachedListingForSearch(path: [String], ttl: TimeInterval) -> (items: [FileInfo], isFresh: Bool)? {
    self.cachedFileList(for: path, ttl: ttl, allowStale: true)
  }

  // MARK: - Event Handlers

  private func handleChatMessage(_ text: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.chatMessage)
    }

    let chatMessage = ChatMessage(text: text, type: .message, date: Date())
    self.recordChatMessage(chatMessage)
    self.unreadPublicChat = true
  }

  private func handleUserChanged(_ user: HotlineUser) {
    self.addOrUpdateHotlineUser(user)
  }

  private func handleUserDisconnected(_ userID: UInt16) {
    if let existingUserIndex = self.users.firstIndex(where: { $0.id == UInt(userID) }) {
      let user = self.users.remove(at: existingUserIndex)

      if Prefs.shared.showJoinLeaveMessages {
        let chatMessage = ChatMessage(text: "\(user.name) left", type: .left, date: Date())
        self.recordChatMessage(chatMessage)
      }

      if Prefs.shared.playSounds && Prefs.shared.playLeaveSound {
        SoundEffects.play(.userLogout)
      }
    }
  }

  private func handleServerMessage(_ message: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffects.play(.serverMessage)
    }

    print("HotlineState: received server message:\n\(message)")
    let chatMessage = ChatMessage(text: message, type: .server, date: Date())
    self.recordChatMessage(chatMessage)
  }

  private func handlePrivateMessage(userID: UInt16, message: String) {
    if let existingUserIndex = self.users.firstIndex(where: { $0.id == UInt(userID) }) {
      let user = self.users[existingUserIndex]
      print("HotlineState: received private message from \(user.name): \(message)")

      if Prefs.shared.playPrivateMessageSound {
        if self.unreadInstantMessages[userID] == nil {
          SoundEffects.play(.serverMessage)
        } else {
          SoundEffects.play(.chatMessage)
        }
      }

      let instantMessage = InstantMessage(
        direction: .incoming,
        text: message.convertingLinksToMarkdown(),
        type: .message,
        date: Date()
      )

      if self.instantMessages[userID] == nil {
        self.instantMessages[userID] = [instantMessage]
      } else {
        self.instantMessages[userID]!.append(instantMessage)
      }

      self.unreadInstantMessages[userID] = userID
    }
  }

  private func handleNewsPost(_ message: String) {
    let messageBoardRegex = /([\s\r\n]*[_\-]+[\s\r\n]+)/
    let matches = message.matches(of: messageBoardRegex)

    if matches.count == 1 {
      let range = matches[0].range
      self.messageBoard.insert(String(message[message.startIndex..<range.lowerBound]), at: 0)
    } else {
      self.messageBoard.insert(message, at: 0)
    }

    SoundEffects.play(.newNews)
  }

  // MARK: - User Management

  private func addOrUpdateHotlineUser(_ user: HotlineUser) {
    print("HotlineState: users: \n\(self.users)")

    if let i = self.users.firstIndex(where: { $0.id == user.id }) {
      print("HotlineState: updating user \(self.users[i].name)")
      self.users[i] = User(hotlineUser: user)
    } else {
      if !self.users.isEmpty {
        if Prefs.shared.playSounds && Prefs.shared.playJoinSound {
          SoundEffects.play(.userLogin)
        }
      }

      print("HotlineState: added user: \(user.name)")
      self.users.append(User(hotlineUser: user))

      if Prefs.shared.showJoinLeaveMessages {
        let chatMessage = ChatMessage(text: "\(user.name) joined", type: .joined, date: Date())
        self.recordChatMessage(chatMessage)
      }
    }
  }

  // MARK: - Chat Persistence

  private func sessionKey(for server: Server) -> ChatStore.SessionKey {
    ChatStore.SessionKey(address: server.address.lowercased(), port: server.port)
  }

  private func recordChatMessage(_ message: ChatMessage, persist: Bool = true, display: Bool = true) {
    let shouldPersist = persist && message.type != .agreement
    if shouldPersist,
       message.type == .signOut,
       self.lastPersistedMessageType == .signOut {
      return
    }

    if display {
      self.chat.append(message)
    }

    guard shouldPersist, let key = self.chatSessionKey else { return }
    self.lastPersistedMessageType = message.type

    let entry = ChatStore.Entry(
      id: message.id,
      body: message.text,
      username: message.username,
      type: message.type.storageKey,
      date: message.date
    )
    let serverName = self.serverName ?? self.server?.name

    Task {
      await ChatStore.shared.append(entry: entry, for: key, serverName: serverName)
    }
  }

  private func restoreChatHistory(for key: ChatStore.SessionKey) {
    if self.restoredChatSessionKey == key {
      return
    }

    Task { [weak self] in
      guard let self else { return }
      let result = await ChatStore.shared.loadHistory(for: key)

      await MainActor.run {
        guard self.chatSessionKey == key, self.restoredChatSessionKey != key else { return }

        let currentMessages = self.chat
        let historyMessages = result.entries.compactMap { entry -> ChatMessage? in
          guard let chatType = ChatMessageType(storageKey: entry.type) else { return nil }

          let renderedText: String
          if chatType == .message, let username = entry.username, !username.isEmpty {
            renderedText = "\(username): \(entry.body)"
          } else {
            renderedText = entry.body
          }

          var message = ChatMessage(text: renderedText, type: chatType, date: entry.date)
          message.metadata = entry.metadata
          return message
        }

        self.chat = historyMessages + currentMessages
        self.lastPersistedMessageType = historyMessages.last?.type
        self.unreadPublicChat = false
        self.restoredChatSessionKey = key
      }
    }
  }

  private func handleChatHistoryCleared() {
    self.chat = []
    self.unreadPublicChat = false
    self.restoredChatSessionKey = nil
    self.lastPersistedMessageType = nil
  }

  // MARK: - Utilities

  func updateServerTitle() {
    self.serverTitle = self.serverName ?? self.server?.name ?? self.server?.address ?? "Hotline"
  }

  // News helpers
  func organizeNewsArticles(_ flatArticles: [NewsInfo]) -> [NewsInfo] {
    // Place articles under their parent
    var organized: [NewsInfo] = []
    for article in flatArticles {
      if let parentLookupPath = article.parentArticleLookupPath,
         let parentArticle = self.newsLookup[parentLookupPath] {
        if parentArticle.children.firstIndex(of: article) == nil {
          article.expanded = true
          parentArticle.children.append(article)
        }
      } else {
        organized.append(article)
      }
    }

    return organized
  }

  private func findNews(in newsToSearch: [NewsInfo], at path: [String]) -> NewsInfo? {
    guard !path.isEmpty, !newsToSearch.isEmpty, let currentName = path.first else { return nil }

    for news in newsToSearch {
      if news.name == currentName {
        if path.count == 1 {
          return news
        } else if !news.children.isEmpty {
          let remainingPath = Array(path[1...])
          return self.findNews(in: news.children, at: remainingPath)
        }
      }
    }

    return nil
  }

  // File helpers
  private func findFile(in filesToSearch: [FileInfo], at path: [String]) -> FileInfo? {
    guard !path.isEmpty, !filesToSearch.isEmpty else { return nil }

    let currentName = path[0]

    for file in filesToSearch {
      if file.name == currentName {
        if path.count == 1 {
          return file
        } else if let subfiles = file.children {
          let remainingPath = Array(path[1...])
          return self.findFile(in: subfiles, at: remainingPath)
        }
      }
    }

    return nil
  }

  // File search helpers
  private func searchPathKey(for path: [String]) -> String {
    path.joined(separator: "\u{001F}")
  }

  private func resetFileSearchState() {
    self.fileSearchResults = []
    self.fileSearchResultKeys.removeAll(keepingCapacity: true)
    self.fileSearchStatus = .idle
    self.fileSearchQuery = ""
    self.fileSearchScannedFolders = 0
    self.fileSearchCurrentPath = nil
  }

  // File cache helpers
  private func shouldBypassFileCache(for path: [String]) -> Bool {
    guard let folderName = path.last else {
      return false
    }

    let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.range(of: "upload", options: [.caseInsensitive]) != nil {
      return true
    }

    if trimmed.range(of: "dropbox", options: [.caseInsensitive]) != nil {
      return true
    }

    if trimmed.range(of: "drop box", options: [.caseInsensitive]) != nil {
      return true
    }

    return false
  }

  private func cachedFileList(for path: [String], ttl: TimeInterval, allowStale: Bool) -> (items: [FileInfo], isFresh: Bool)? {
    guard ttl > 0 else {
      return nil
    }

    if self.shouldBypassFileCache(for: path) {
      return nil
    }

    let key = self.searchPathKey(for: path)
    guard let entry = self.fileListCache[key] else {
      return nil
    }

    let age = Date().timeIntervalSince(entry.timestamp)
    let isFresh = age <= ttl
    if !allowStale && !isFresh {
      return nil
    }

    return (entry.files, isFresh)
  }

  private func storeFileListInCache(_ files: [FileInfo], for path: [String]) {
    guard self.fileSearchConfig.cacheTTL > 0 else {
      return
    }

    if self.shouldBypassFileCache(for: path) {
      return
    }

    let key = self.searchPathKey(for: path)
    self.fileListCache[key] = FileListCacheEntry(files: files, timestamp: Date())
    self.pruneFileListCacheIfNeeded()
  }

  private func pruneFileListCacheIfNeeded() {
    let limit = self.fileSearchConfig.maxCachedFolders
    guard limit > 0, self.fileListCache.count > limit else {
      return
    }

    let excess = self.fileListCache.count - limit
    guard excess > 0 else { return }

    let sortedKeys = self.fileListCache.sorted { lhs, rhs in
      lhs.value.timestamp < rhs.value.timestamp
    }

    for index in 0..<excess {
      let key = sortedKeys[index].key
      self.fileListCache.removeValue(forKey: key)
    }
  }

  private func invalidateFileListCache(for path: [String], includingAncestors: Bool = false) {
    guard !self.fileListCache.isEmpty else {
      return
    }

    var currentPath = path
    while true {
      let key = self.searchPathKey(for: currentPath)
      self.fileListCache.removeValue(forKey: key)

      if !includingAncestors || currentPath.isEmpty {
        break
      }

      currentPath.removeLast()
      if currentPath.isEmpty {
        let rootKey = self.searchPathKey(for: currentPath)
        self.fileListCache.removeValue(forKey: rootKey)
        break
      }
    }
  }

  // MARK: - Transfer Delegates

//  nonisolated func hotlineTransferStatusChanged(client: HotlineTransferClient, reference: UInt32, status: HotlineTransferStatus, timeRemaining: TimeInterval) {
//    Task { @MainActor in
//      // Update transfer info with progress
//      guard let transferIndex = self.transfers.firstIndex(where: { $0.id == reference }) else {
//        return
//      }
//
//      let transfer = self.transfers[transferIndex]
//      transfer.timeRemaining = timeRemaining
//
//      switch status {
//      case .progress(let p):
//        transfer.progress = p
//        transfer.progressCallback?(transfer)
//      case .completed:
//        transfer.completed = true
//        transfer.progress = 1.0
//      case .failed(_):
//        transfer.failed = true
//      default:
//        break
//      }
//    }
//  }

//  nonisolated func hotlineFileDownloadReceivedInfo(client: HotlineFileDownloadClient, reference: UInt32, info: HotlineFileInfoFork) {
//    // Info fork received (file metadata)
//  }

//  nonisolated func hotlineFileDownloadComplete(client: HotlineFileDownloadClient, reference: UInt32, at url: URL) {
//    Task { @MainActor in
//      // Find and remove the download client
//      if let downloadIndex = self.downloads.firstIndex(where: { $0.referenceNumber == reference }) {
//        self.downloads.remove(at: downloadIndex)
//      }
//
//      // Find and complete the transfer
//      guard let transferIndex = AppState.shared.transfers.firstIndex(where: { $0.id == reference }) else {
//        return
//      }
//
//      let transfer = AppState.shared.transfers[transferIndex]
//      transfer.fileURL = url
//      transfer.downloadCallback?(transfer)
//      AppState.shared.transfers.remove(at: transferIndex)
//    }
//  }

//  nonisolated func hotlineFolderDownloadReceivedFileInfo(client: HotlineFolderDownloadClient, reference: UInt32, fileName: String, itemNumber: Int, totalItems: Int) {
//    Task { @MainActor in
//      // Update transfer info with current file being downloaded
//      guard let transferIndex = AppState.shared.transfers.firstIndex(where: { $0.id == reference }) else {
//        return
//      }
//
//      let transfer = AppState.shared.transfers[transferIndex]
//      transfer.title = "\(fileName) (\(itemNumber)/\(totalItems))"
//    }
//  }

//  nonisolated func hotlineFolderDownloadComplete(client: HotlineFolderDownloadClient, reference: UInt32, at url: URL) {
//    Task { @MainActor in
//      // Find and remove the download client
//      if let downloadIndex = self.downloads.firstIndex(where: { $0.referenceNumber == reference }) {
//        self.downloads.remove(at: downloadIndex)
//      }
//
//      // Find and complete the transfer
//      guard let transferIndex = AppState.shared.transfers.firstIndex(where: { $0.id == reference }) else {
//        return
//      }
//
//      let transfer = AppState.shared.transfers[transferIndex]
//      transfer.fileURL = url
//      transfer.downloadCallback?(transfer)
//      AppState.shared.transfers.remove(at: transferIndex)
//    }
//  }
}

// MARK: - File Search Session

@MainActor
final class HotlineStateFileSearchSession {
  private struct FolderTask {
    let path: [String]
    let depth: Int
    let isHot: Bool
  }

  private weak var hotlineState: HotlineState?
  private let queryTokens: [String]
  private let config: FileSearchConfig

  private var queue: [FolderTask] = []
  private var visited: Set<String> = []
  private var loopHistogram: [String: Int] = [:]

  private var processedCount: Int = 0
  private var currentDelay: TimeInterval
  private var isCancelled = false

  init(hotlineState: HotlineState, query: String, config: FileSearchConfig) {
    self.hotlineState = hotlineState
    self.queryTokens = query.lowercased().split(separator: " ").map(String.init)
    self.config = config
    self.currentDelay = config.initialDelay
  }

  func start() async {
    guard let hotlineState else {
      return
    }

    await Task.yield()

    if !hotlineState.filesLoaded {
      hotlineState.searchSession(self, didFocusOn: [])
      let rootFiles = try? await hotlineState.getFileList(path: [], suppressErrors: true, preferCache: true)
      self.processedCount = max(self.processedCount, 1)
      self.processListing(rootFiles ?? [], depth: 0, parentPath: [], parentIsHot: false)
    } else {
      hotlineState.searchSession(self, didFocusOn: [])
      self.processedCount = max(self.processedCount, 1)
      self.processListing(hotlineState.files, depth: 0, parentPath: [], parentIsHot: false)
    }

    while !self.queue.isEmpty && !self.isCancelled {
      await Task.yield()

      guard let task = self.dequeueNextTask() else {
        continue
      }

      if self.shouldSkip(path: task.path, depth: task.depth) {
        hotlineState.searchSession(self, didEmit: [], processed: self.processedCount, pending: self.queue.count)
        continue
      }

      hotlineState.searchSession(self, didFocusOn: task.path)
      self.visited.insert(self.pathKey(for: task.path))

      if let cached = hotlineState.cachedListingForSearch(path: task.path, ttl: self.config.cacheTTL) {
        if cached.isFresh {
          self.processedCount += 1
          self.processListing(cached.items, depth: task.depth, parentPath: task.path, parentIsHot: task.isHot)
          continue
        } else {
          self.processListing(cached.items, depth: task.depth, parentPath: task.path, parentIsHot: task.isHot)
        }
      }

      let children = try? await hotlineState.getFileList(path: task.path, suppressErrors: true)
      self.processedCount += 1

      if self.isCancelled {
        break
      }

      self.processListing(children ?? [], depth: task.depth, parentPath: task.path, parentIsHot: task.isHot)

      await self.applyBackoff()
    }

    hotlineState.searchSessionDidFinish(self, processed: self.processedCount, pending: self.queue.count, completed: !self.isCancelled)
  }

  func cancel() {
    self.isCancelled = true
  }

  private func processListing(_ items: [FileInfo], depth: Int, parentPath: [String], parentIsHot: Bool) {
    guard let hotlineState else {
      return
    }

    var matches: [FileInfo] = []
    var folderEntries: [(file: FileInfo, isHot: Bool)] = []
    var hasFileMatch = false

    for file in items {
      let matchesName = self.nameMatchesQuery(file.name)

      if matchesName {
        matches.append(file)
        if !file.isFolder {
          hasFileMatch = true
        }
      }

      if file.isFolder && !file.isAppBundle {
        folderEntries.append((file, matchesName))
      }
    }

    var remainingBurst = 0
    if self.config.hotBurstLimit > 0 && (parentIsHot || hasFileMatch) {
      remainingBurst = self.config.hotBurstLimit
    }

    if remainingBurst > 0 {
      var candidateIndices: [Int] = []
      for index in folderEntries.indices where !folderEntries[index].isHot {
        candidateIndices.append(index)
      }

      if !candidateIndices.isEmpty {
        candidateIndices.shuffle()
        for index in candidateIndices {
          folderEntries[index].isHot = true
          remainingBurst -= 1
          if remainingBurst == 0 {
            break
          }
        }
      }
    }

    for entry in folderEntries {
      self.enqueueFolder(entry.file, depth: depth + 1, markHot: entry.isHot)
    }

    hotlineState.searchSession(self, didEmit: matches, processed: self.processedCount, pending: self.queue.count)
  }

  private func enqueueFolder(_ folder: FileInfo, depth: Int, markHot: Bool) {
    guard !self.isCancelled else { return }
    guard depth <= self.config.maxDepth else { return }

    let path = folder.path
    let key = self.pathKey(for: path)
    guard !self.visited.contains(key) else { return }

    if self.exceedsLoopThreshold(for: path) {
      return
    }

    self.queue.append(FolderTask(path: path, depth: depth, isHot: markHot))
  }

  private func dequeueNextTask() -> FolderTask? {
    guard !self.queue.isEmpty else {
      return nil
    }

    if self.queue.count == 1 {
      return self.queue.removeFirst()
    }

    let currentDepth = self.queue[0].depth
    var lastSameDepthIndex = 0
    var hotIndices: [Int] = []

    for index in 0..<self.queue.count {
      let candidate = self.queue[index]
      if candidate.depth == currentDepth {
        lastSameDepthIndex = index
        if candidate.isHot {
          hotIndices.append(index)
        }
      } else {
        break
      }
    }

    let selectionPool: [Int]
    if !hotIndices.isEmpty {
      selectionPool = hotIndices
    } else {
      selectionPool = Array(0...lastSameDepthIndex)
    }

    let randomIndex = selectionPool.randomElement() ?? 0
    return self.queue.remove(at: randomIndex)
  }

  private func shouldSkip(path: [String], depth: Int) -> Bool {
    if self.isCancelled {
      return true
    }

    if depth > self.config.maxDepth {
      return true
    }

    let key = self.pathKey(for: path)
    if self.visited.contains(key) {
      return true
    }

    return false
  }

  private func nameMatchesQuery(_ name: String) -> Bool {
    guard !self.queryTokens.isEmpty else { return false }
    let lowercased = name.lowercased()
    return self.queryTokens.allSatisfy { lowercased.contains($0) }
  }

  private func exceedsLoopThreshold(for path: [String]) -> Bool {
    guard self.config.loopRepetitionLimit > 0 else { return false }
    guard let last = path.last else { return false }
    let parent = path.dropLast()

    guard let previousIndex = parent.lastIndex(of: last) else {
      return false
    }

    let suffix = Array(path[previousIndex...])
    let key = suffix.joined(separator: "\u{001F}")
    let count = (self.loopHistogram[key] ?? 0) + 1
    self.loopHistogram[key] = count
    return count > self.config.loopRepetitionLimit
  }

  private func pathKey(for path: [String]) -> String {
    path.joined(separator: "\u{001F}")
  }

  private func applyBackoff() async {
    guard !self.isCancelled else { return }

    if self.processedCount > self.config.initialBurstCount {
      self.currentDelay = min(self.config.maxDelay, max(self.config.initialDelay, self.currentDelay * self.config.backoffMultiplier))
    }

    guard self.currentDelay > 0 else {
      return
    }

    let nanoseconds = UInt64(self.currentDelay * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanoseconds)
  }
}
