import SwiftUI

// MARK: - Users & Administration

extension HotlineState {

  /// Loads the user list. What people do until it's in is held, and goes through after it, in
  /// order: a busy server can send word of what they did before the list, though they did it after
  /// the list was made, and the list would undo it, keeping someone who left for good, or leaving
  /// out someone who came.
  func getUserList() async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    // Unless it's held already, as while logging in, for that to go through.
    let holding = self.heldUserEvents == nil
    if holding {
      self.heldUserEvents = []
    }
    defer {
      if holding {
        self.releaseHeldUserEvents()
      }
    }

    let hotlineUsers = try await client.getUserList()
    self.users = hotlineUsers.map { User(hotlineUser: $0) }
    self.findOwnUser()
  }

  /// Goes through what people did while it was held, in the order they did it. Without sounds, as
  /// it all comes at once, as you arrive.
  func releaseHeldUserEvents() {
    guard let events = self.heldUserEvents else {
      return
    }
    self.heldUserEvents = nil
    for event in events {
      switch event {
      case .userChanged(let user):
        self.addOrUpdateHotlineUser(user, playsSound: false)
      case .userDisconnected(let userID):
        self.handleUserDisconnected(userID, playsSound: false)
      default:
        break
      }
    }
  }

  /// Finds which entry in the user list is you, if that isn't known: the one with your name, or of
  /// more than one, the one with your icon too, since a server can give you another, and of those,
  /// the last to connect, as user IDs count up. Once found, it's followed by its ID, through
  /// changes to your name and icon.
  func findOwnUser() {
    if let id = self.ownUserID, self.users.contains(where: { $0.id == id }) {
      return
    }
    let named = self.users.filter { $0.name == self.username }
    let alsoIcon = named.filter { Int($0.iconID) == self.iconID }
    self.ownUserID = (alsoIcon.isEmpty ? named : alsoIcon).max { $0.id < $1.id }?.id
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

  // MARK: - User Management

  func addOrUpdateHotlineUser(_ user: HotlineUser, playsSound: Bool = true) {
    print("HotlineState: users: \n\(self.users)")

    if let i = self.users.firstIndex(where: { $0.id == user.id }) {
      print("HotlineState: updating user \(self.users[i].name)")
      let oldName = self.users[i].name
      let renamed = user.name != oldName
      self.users[i] = User(hotlineUser: user)
      self.updatePrivateChats(for: self.users[i], renamedFrom: renamed ? oldName : nil)

      // Said in chat, so you can follow who's who.
      if renamed {
        var chatMessage = ChatMessage(text: "\(oldName) is now known as \(user.name)", type: .renamed, date: Date())
        chatMessage.isAdmin = user.isAdmin
        self.recordChatMessage(chatMessage)
      }
    } else {
      if playsSound && !self.users.isEmpty {
        if Prefs.shared.playSounds && Prefs.shared.playJoinSound {
          SoundEffects.play(.userLogin)
        }
      }

      print("HotlineState: added user: \(user.name)")
      self.users.append(User(hotlineUser: user))
      self.findOwnUser()

      if Prefs.shared.showJoinLeaveMessages {
        var chatMessage = ChatMessage(text: "\(user.name) connected", type: .joined, date: Date())
        chatMessage.isAdmin = user.isAdmin
        self.recordChatMessage(chatMessage)
      }
    }
  }
}
