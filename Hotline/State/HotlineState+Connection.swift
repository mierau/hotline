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

    // Show cached banner while connecting.
    self.showCachedBanner(for: server)

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
        login: loginInfo,
        willLogIn: { @MainActor [weak self] in
          self?.status = .loggingIn
        }
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

      // What people do waits for the user list, and you, to be in. See `getUserList()`.
      self.heldUserEvents = []

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
      self.stopDownloadingBanner()
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
      self.stopDownloadingBanner()
      self.status = .disconnected
      throw clientError
    }
    catch {
      print("HotlineState.login(): Login failed with error: \(error)")
      if let client = self.client {
        await client.disconnect()
        self.client = nil
      }
      self.stopDownloadingBanner()
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
    // What people did while you logged in goes through once you're in, after the line saying so.
    defer {
      self.releaseHeldUserEvents()
    }

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
    self.ownUserID = nil
    self.heldUserEvents = nil
    self.privateChats = []
    self.privateChatDrafts = [:]
    self.boardPostAnnouncement?.cancel()
    self.boardPostAnnouncement = nil
    self.boardPostToReveal = nil
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
    // The server stays in the connect form, and so does its banner: the one cached for it, or the
    // default if it couldn't be kept.
    self.stopDownloadingBanner()
    if let server = self.server {
      self.previewBanner(for: server)
    }

    print("HotlineState: Resetting file search...")
    self.resetFileSearchState()

    self.chatSessionKey = nil
    self.restoredChatSessionKey = nil
    self.lastPersistedMessageType = nil

    print("HotlineState: Disconnected")
  }

  // MARK: - Banner

  /// Downloads the server's banner, and caches it for next time. While connecting, the toolbar
  /// shows the banner cached from last time, so this only changes what's on screen when the server
  /// has a new banner (which fades in) or no longer has one (back to the default).
  @MainActor
  func downloadBanner(force: Bool = false) {
    guard self.serverVersion >= 150 else {
      return
    }

    if force {
      self.bannerDownloadTask?.cancel()
      self.bannerDownloadTask = nil
    }
    else if self.bannerDownloadTask != nil || self.bannerDownloaded {
      return
    }

    let task = Task { @MainActor [weak self] in
      defer {
        self?.bannerDownloadTask = nil
      }

      guard let self,
            let client = self.client,
            let server = self.server else {
        return
      }

      // An error reply means the server has no banner. Anything else, like a timeout, might be
      // temporary, so keep showing the cached banner.
      let transfer: (referenceNumber: UInt32, transferSize: Int)?
      do {
        transfer = try await client.downloadBanner()
      }
      catch HotlineClientError.serverError {
        transfer = nil
      }
      catch {
        print("HotlineState: Banner request failed: \(error)")
        return
      }

      guard let transfer else {
        print("HotlineState: Server has no banner")
        await self.forgetBanner(for: server)
        return
      }

      print("HotlineState: Banner download info - reference: \(transfer.referenceNumber), transferSize: \(transfer.transferSize)")

      let previewClient = HotlineFilePreviewClient(
        fileName: "banner",
        address: server.address,
        port: UInt16(server.port),
        reference: transfer.referenceNumber,
        size: UInt32(transfer.transferSize)
      )

      let downloadURL: URL
      let data: Data
      do {
        downloadURL = try await previewClient.preview()
        data = try Data(contentsOf: downloadURL)
      }
      catch {
        print("HotlineState: Banner download failed: \(error)")
        previewClient.cleanup()
        return
      }

      print("HotlineState: Banner download complete, data size: \(data.count) bytes")

      // Keep it for next time. When it's the same banner as last time, this is the file that's
      // already showing.
      let cachedURL = await BannerCache.shared.store(data, forAddress: server.address, port: server.port)
      if cachedURL != nil {
        previewClient.cleanup()
      }
      let fileURL = cachedURL ?? downloadURL

      guard !Task.isCancelled, self.client != nil else {
        if cachedURL == nil {
          previewClient.cleanup()
        }
        return
      }
      self.bannerDownloaded = true

      // The same banner as last time is the one already showing, so nothing changes on screen.
      guard fileURL.path(percentEncoded: false) != self.bannerFileURL?.path(percentEncoded: false) else {
        return
      }

      guard let banner = await Self.loadBanner(at: fileURL) else {
        print("HotlineState: Banner isn't an image that can be shown")
        if cachedURL == nil {
          previewClient.cleanup()
        }
        await self.forgetBanner(for: server)
        return
      }

      guard !Task.isCancelled, self.client != nil else {
        if cachedURL == nil {
          previewClient.cleanup()
        }
        return
      }

      // In place of the cached banner, if one was showing. The toolbar fades between them.
      self.showBanner(banner, temporary: cachedURL == nil)
    }

    self.bannerDownloadTask = task
  }

  /// Shows the banner cached from an earlier visit to the server, if there is one.
  @MainActor
  private func showCachedBanner(for server: Server) {
    self.bannerCacheTask?.cancel()
    self.bannerCacheTask = Task { @MainActor [weak self] in
      guard let fileURL = await BannerCache.shared.banner(forAddress: server.address, port: server.port),
            // Already showing, from typing the server in.
            fileURL != self?.bannerFileURL,
            let banner = await Self.loadBanner(at: fileURL),
            let self,
            !Task.isCancelled,
            // The download is newer. It can't normally finish first, but if it did, it wins.
            !self.bannerDownloaded else {
        return
      }
      self.showBanner(banner)
    }
  }

  /// Before connecting, the banner cached from an earlier visit to the server in the connect form,
  /// or the default banner if there isn't one, so the banner follows what's typed or chosen.
  @MainActor
  func previewBanner(for server: Server) {
    guard self.status == .disconnected else {
      return
    }
    self.bannerCacheTask?.cancel()
    self.bannerCacheTask = Task { @MainActor [weak self] in
      // A moment after typing stops, rather than on the way through each keystroke.
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else {
        return
      }
      let fileURL = server.address.isEmpty ? nil : await BannerCache.shared.banner(forAddress: server.address, port: server.port)
      guard let self, !Task.isCancelled, self.status == .disconnected else {
        return
      }
      guard let fileURL else {
        self.hideBanner()
        return
      }
      guard fileURL != self.bannerFileURL,
            let banner = await Self.loadBanner(at: fileURL),
            !Task.isCancelled,
            self.status == .disconnected else {
        return
      }
      self.showBanner(banner)
    }
  }

  /// For a connection that doesn't go through: stops downloading the banner, but keeps the one
  /// cached for the server, which is still in the connect form. One that came with the connection
  /// and couldn't be cached goes with it.
  @MainActor
  private func stopDownloadingBanner() {
    self.bannerDownloadTask?.cancel()
    self.bannerDownloadTask = nil
    self.bannerDownloaded = false
    if self.bannerTemporaryFileURL != nil {
      self.hideBanner()
    }
  }

  /// For a server that no longer has a banner, or has one that can't be shown: forgets the cached
  /// one and goes back to the default.
  @MainActor
  private func forgetBanner(for server: Server) async {
    await BannerCache.shared.removeBanner(forAddress: server.address, port: server.port)
    guard !Task.isCancelled, self.client != nil else {
      return
    }
    self.bannerDownloaded = true
    self.hideBanner()
  }

  /// A banner ready to show, with the colors the toolbar takes from it.
  struct LoadedBanner {
    let fileURL: URL
    let format: Data.ImageFormat
    #if os(macOS)
    let image: NSImage
    let colors: ColorArt?
    #elseif os(iOS)
    let image: UIImage
    #endif
  }

  /// Reads and decodes a banner and works out its colors, off the main thread. Nil if it isn't an
  /// image.
  nonisolated static func loadBanner(at fileURL: URL) async -> LoadedBanner? {
    await Task.detached(priority: .userInitiated) {
      guard let data = try? Data(contentsOf: fileURL) else {
        return nil
      }
      #if os(macOS)
      guard let image = NSImage(data: data) else {
        return nil
      }
      return LoadedBanner(fileURL: fileURL, format: data.detectedImageFormat, image: image, colors: ColorArt.analyze(image: image))
      #elseif os(iOS)
      guard let image = UIImage(data: data) else {
        return nil
      }
      return LoadedBanner(fileURL: fileURL, format: data.detectedImageFormat, image: image)
      #endif
    }.value
  }

  /// Shows a banner in place of whatever was showing. A temporary banner's file is deleted once
  /// it's replaced or the connection ends.
  @MainActor
  private func showBanner(_ banner: LoadedBanner, temporary: Bool = false) {
    let previousTemporaryFileURL = self.bannerTemporaryFileURL

    // Set all banner properties together so SwiftUI coalesces into one layout pass
    self.bannerImageFormat = banner.format
    self.bannerFileURL = banner.fileURL
    #if os(macOS)
    self.bannerImage = Image(nsImage: banner.image)
    self.bannerColors = banner.colors
    #elseif os(iOS)
    self.bannerImage = banner.image
    #endif

    self.bannerTemporaryFileURL = temporary ? banner.fileURL : nil
    if let previousTemporaryFileURL, previousTemporaryFileURL != banner.fileURL {
      HotlineFilePreviewClient.removeDownload(at: previousTemporaryFileURL)
    }
  }

  @MainActor
  private func hideBanner() {
    self.bannerImageFormat = .unknown
    self.bannerFileURL = nil
    self.bannerImage = nil
    #if os(macOS)
    self.bannerColors = nil
    #endif

    if let temporaryFileURL = self.bannerTemporaryFileURL {
      self.bannerTemporaryFileURL = nil
      HotlineFilePreviewClient.removeDownload(at: temporaryFileURL)
    }
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

    case .chatInvitation(let chatID, let userID, let name, let subject):
      self.handleChatInvitation(chatID: chatID, userID: userID, name: name, subject: subject)

    case .privateChatMessage(let chatID, let text):
      self.handlePrivateChatMessage(chatID: chatID, text: text)

    case .privateChatUserChanged(let chatID, let user):
      self.handlePrivateChatUserChanged(chatID: chatID, user: user)

    case .privateChatUserLeft(let chatID, let userID):
      self.handlePrivateChatUserLeft(chatID: chatID, userID: userID)

    case .privateChatSubject(let chatID, let subject):
      self.handlePrivateChatSubject(chatID: chatID, subject: subject)
    }
  }
}
