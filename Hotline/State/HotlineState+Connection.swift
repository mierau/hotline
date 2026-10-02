import SwiftUI

// MARK: - Connection & Event Loop

extension HotlineState {

  // MARK: - App Nap Prevention

  #if os(macOS)
  static var activeConnectionCount = 0
  static var appNapActivity: NSObjectProtocol?

  static func connectionDidOpen() {
    self.activeConnectionCount += 1
    if self.activeConnectionCount == 1, self.appNapActivity == nil {
      self.appNapActivity = ProcessInfo.processInfo.beginActivity(
        options: .idleSystemSleepDisabled,
        reason: "Maintaining Hotline server connection"
      )
    }
  }

  static func connectionDidClose() {
    self.activeConnectionCount = max(0, self.activeConnectionCount - 1)
    if self.activeConnectionCount == 0, let activity = self.appNapActivity {
      ProcessInfo.processInfo.endActivity(activity)
      self.appNapActivity = nil
    }
  }
  #endif

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
    self.lastPersistedMessageDate = nil
    self.chat = []
    self.chatRenderedText = nil
    self.chatRenderedCount = 0
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
        login: loginInfo
      )
      print("HotlineState.login(): HotlineClient.connect() returned")

      // The window may have closed just as the connection finished.
      if Task.isCancelled {
        await client.disconnect()
        throw CancellationError()
      }

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

      // Start event loop so showAgreement and other events can flow through.
      self.startEventLoop()

      // Old servers (<150) don't use the agreement handshake, so proceed immediately.
      // For new servers, the event loop will receive showAgreement and either
      // show the agreement sheet or auto-agree.
      if self.serverVersion < 150 {
        print("HotlineState.login(): Old server, completing login immediately")
        try await self.completeLogin()
      }

    }
    catch let error where Task.isCancelled {
      // Cancelled because the window closed. A cancelled request can surface as any error
      // (even HotlineClientError.timeout), so check the task rather than the error type.
      print("HotlineState.login(): Cancelled")
      if let client = self.client {
        await client.disconnect()
        self.client = nil
      }
      self.status = .disconnected
      throw error
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

  func displayError(_ error: Error, message: String? = nil) {
    self.errorDisplayed = true
    self.errorMessage = message ?? error.localizedDescription
  }

  /// Complete the login process after agreement (or immediately if no agreement needed).
  /// Requests user list, sets status to loggedIn, and starts post-login tasks.
  @MainActor
  func completeLogin() async throws {
    print("HotlineState.completeLogin(): Requesting user list...")
    try await self.getUserList()

    if self.status != .loggedIn {
      self.status = .loggedIn
      print("HotlineState.completeLogin(): Status set to loggedIn")

      // Record session divider and a "joined" message for yourself.
      let divider = ChatMessage(text: "", type: .signOut, date: Date())
      self.recordChatMessage(divider)

      let username = Prefs.shared.username
      let selfUser = self.users.first(where: { $0.name == username })
      var joinedMessage = ChatMessage(text: "\(username) connected", type: .joined, date: Date())
      joinedMessage.isAdmin = selfUser?.isAdmin ?? false
      self.recordChatMessage(joinedMessage)
    }

    #if os(macOS)
    Self.connectionDidOpen()
    #endif

    if Prefs.shared.playSounds && Prefs.shared.playLoggedInSound {
      SoundEffects.play(.loggedIn)
    }

    print("HotlineState.completeLogin(): Connected to \(self.serverTitle)")

    // Defer event loop and post-login work to avoid layout recursion
    Task { @MainActor in
      guard let client = self.client else { return }

      print("HotlineState: Post-login: Starting keep-alive...")
      await client.startKeepAlive()

      if self.eventTask == nil {
        print("HotlineState: Post-login: Starting event loop...")
        self.startEventLoop()
      }

      print("HotlineState: Post-login: Sending preferences...")
      try? await self.sendUserPreferences()

      print("HotlineState: Post-login: Downloading banner...")
      self.downloadBanner()

      print("HotlineState: Post-login: Preloading files, news, and message board...")
      let _ = try? await self.getFileList()
      // If we connected via a deep link (hotline://host/section/...),
      // signal the view layer to navigate to the target section.
      if let section = self.server?.initialSection {
        let filePath = self.server?.initialFilePath
        self.server?.initialSection = nil
        self.server?.initialFilePath = nil
        self.pendingNavigation = (section: section, filePath: filePath)
      }
      try? await self.getNewsList()
      let _ = try? await self.getMessageBoard()
    }
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
      // Record a "left" message for yourself.
      let username = Prefs.shared.username
      let selfUser = self.users.first(where: { $0.name == username })
      var leftMessage = ChatMessage(text: "\(username) disconnected", type: .left, date: Date())
      leftMessage.isAdmin = selfUser?.isAdmin ?? false
      self.recordChatMessage(leftMessage, persist: true, display: false)
    }

    print("HotlineState: Cancelling banner and downloads...")

    self.bannerDownloadTask?.cancel()
    self.bannerDownloadTask = nil

    // Cancel file search
    self.fileSearchSession?.cancel()
    self.fileSearchSession = nil

    // Clear client reference
    self.client = nil

    print("HotlineState: Resetting state properties...")

    #if os(macOS)
    if self.status.isConnected {
      Self.connectionDidClose()
    }
    #endif

    // Reset state immediately (constraint loop was caused by something else)
    self.status = .disconnected
    self.serverVersion = 123
    self.serverName = nil
    self.access = nil
    self.agreed = false
    self.agreementText = nil
    self.users = []
    self.chat = []
    self.chatRenderedText = nil
    self.chatRenderedCount = 0
    self.privateMessages = [:]
    self.unreadPrivateMessages = [:]
    self.restoredPrivatePeers = []
    self.unreadPublicChat = false
    self.messageBoard = []
    self.messageBoardLoaded = false
    self.news = []
    self.newsLoaded = false
    self.newsLookup = [:]
    self.files = []
    self.filesLoaded = false
    self.pendingNavigation = nil
    self.accounts = []
    self.accountsLoaded = false
    self.bannerImage = nil
    self.bannerColors = nil
    self.bannerImageFormat = .unknown
    // Drop the banner file too, so the toolbar shows the default banner and the next login
    // downloads it again (downloadBanner() skips the download while a file is set).
    if let bannerFileURL = self.bannerFileURL {
      try? FileManager.default.removeItem(at: bannerFileURL)
      self.bannerFileURL = nil
    }

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
          size: UInt32(result.transferSize)
        )

        let fileURL = try await previewClient.preview()

        if let oldFileURL = self.bannerFileURL {
          try? FileManager.default.removeItem(at: oldFileURL)
        }

        guard self.client != nil else { return }

        let data = try Data(contentsOf: fileURL)
        let format = data.detectedImageFormat

        print("HotlineState: Banner download complete, data size: \(data.count) bytes")

#if os(macOS)
        guard let nsImage = NSImage(data: data) else {
          print("HotlineState: Failed to create NSImage from banner data")
          return
        }
        let swiftUIImage = Image(nsImage: nsImage)
        let colors = ColorArt.analyze(image: nsImage)
#elseif os(iOS)
        guard let uiImage = UIImage(data: data) else {
          print("HotlineState: Failed to create UIImage from banner data")
          return
        }
        let swiftUIImage = Image(uiImage: uiImage)
        let colors: ColorArt? = nil
#endif

        // Set all banner properties together so SwiftUI coalesces into one layout pass
        self.bannerImageFormat = format
        self.bannerFileURL = fileURL
        self.bannerImage = swiftUIImage
        self.bannerColors = colors

      } catch {
        print("HotlineState: Banner download failed: \(error)")
      }
    }

    self.bannerDownloadTask = task
  }

  // MARK: - Event Loop

  func startEventLoop() {
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

    case .showAgreement(let text):
      if let text {
        // Server has agreement text — show the sheet
        self.agreementText = text
      } else if self.status != .loggedIn {
        // No agreement required — auto-agree and complete login
        Task {
          do {
            try await self.sendAgree()
          } catch {
            print("HotlineState: Auto-agree failed: \(error)")
          }
        }
      }

    case .userAccess(let options):
      self.access = options
      print("HotlineState: Got access options")
      HotlineUserAccessOptions.printAccessOptions(options)

    case .disconnectMessage(let message):
      print("HotlineState: Server sent disconnect message: \(message)")
      self.disconnectMessage = message
    }
  }
}
