import SwiftUI

extension EnvironmentValues {
  @Entry var preferences: Prefs = Prefs.shared
}

enum PrefsKeys: String {
  case username = "username"
  case userIconID = "user icon id"
  case refusePrivateMessages = "refuse private messages"
  case refusePrivateChat = "refuse private chat"
  case enableAutomaticMessage = "enable automatic message"
  case automaticMessage = "automatic message"
  case playSounds = "play sounds"
  case playChatSound = "play chat sound"
  case playFileTransferCompleteSound = "play file transfer complete sound"
  case playPrivateMessageSound = "play private message sound"
  case playJoinSound = "play join sound"
  case playLeaveSound = "play leave sound"
  case playLoggedInSound = "play logged in sound"
  case playErrorSound = "play error sound"
  case playChatInvitationSound = "play chat invitation sound"
  case showBannerToolbar = "show banner toolbar"
  case showJoinLeaveMessages = "show join leave messages"
}

@Observable
class Prefs {
  static let shared = Prefs()
  
  private init() {
    UserDefaults.standard.register(defaults:[
      PrefsKeys.username.rawValue: "guest",
      PrefsKeys.userIconID.rawValue: 191,
      PrefsKeys.refusePrivateMessages.rawValue: false,
      PrefsKeys.refusePrivateChat.rawValue: false,
      PrefsKeys.enableAutomaticMessage.rawValue: false,
      PrefsKeys.automaticMessage.rawValue: "",
      PrefsKeys.playSounds.rawValue: true,
      PrefsKeys.playChatSound.rawValue: true,
      PrefsKeys.playFileTransferCompleteSound.rawValue: true,
      PrefsKeys.playPrivateMessageSound.rawValue: true,
      PrefsKeys.playJoinSound.rawValue: true,
      PrefsKeys.playLeaveSound.rawValue: true,
      PrefsKeys.playLoggedInSound.rawValue: true,
      PrefsKeys.playErrorSound.rawValue: true,
      PrefsKeys.playChatInvitationSound.rawValue: true,
      PrefsKeys.showBannerToolbar.rawValue: true,
      PrefsKeys.showJoinLeaveMessages.rawValue: true,
    ])
    
    self.username = UserDefaults.standard.string(forKey: PrefsKeys.username.rawValue)!
    self.userIconID = UserDefaults.standard.integer(forKey: PrefsKeys.userIconID.rawValue)
    self.refusePrivateMessages = UserDefaults.standard.bool(forKey: PrefsKeys.refusePrivateMessages.rawValue)
    self.refusePrivateChat = UserDefaults.standard.bool(forKey: PrefsKeys.refusePrivateChat.rawValue)
    self.enableAutomaticMessage = UserDefaults.standard.bool(forKey: PrefsKeys.enableAutomaticMessage.rawValue)
    self.automaticMessage = UserDefaults.standard.string(forKey: PrefsKeys.automaticMessage.rawValue)!
    self.playSounds = UserDefaults.standard.bool(forKey: PrefsKeys.playSounds.rawValue)
    self.playChatSound = UserDefaults.standard.bool(forKey: PrefsKeys.playChatSound.rawValue)
    self.playFileTransferCompleteSound = UserDefaults.standard.bool(forKey: PrefsKeys.playFileTransferCompleteSound.rawValue)
    self.playPrivateMessageSound = UserDefaults.standard.bool(forKey: PrefsKeys.playPrivateMessageSound.rawValue)
    self.playJoinSound = UserDefaults.standard.bool(forKey: PrefsKeys.playJoinSound.rawValue)
    self.playLeaveSound = UserDefaults.standard.bool(forKey: PrefsKeys.playLeaveSound.rawValue)
    self.playLoggedInSound = UserDefaults.standard.bool(forKey: PrefsKeys.playLoggedInSound.rawValue)
    self.playErrorSound = UserDefaults.standard.bool(forKey: PrefsKeys.playErrorSound.rawValue)
    self.playChatInvitationSound = UserDefaults.standard.bool(forKey: PrefsKeys.playChatInvitationSound.rawValue)
    self.showBannerToolbar = UserDefaults.standard.bool(forKey: PrefsKeys.showBannerToolbar.rawValue)
    self.showJoinLeaveMessages = UserDefaults.standard.bool(forKey: PrefsKeys.showJoinLeaveMessages.rawValue)
  }

  var username: String {
    didSet { UserDefaults.standard.set(self.username, forKey: PrefsKeys.username.rawValue) }
  }
  
  var userIconID: Int {
    didSet { UserDefaults.standard.set(self.userIconID, forKey: PrefsKeys.userIconID.rawValue) }
  }
  
  var refusePrivateMessages: Bool {
    didSet { UserDefaults.standard.set(self.refusePrivateMessages, forKey: PrefsKeys.refusePrivateMessages.rawValue) }
  }
  
  var playSounds: Bool {
    didSet { UserDefaults.standard.set(self.playSounds, forKey: PrefsKeys.playSounds.rawValue) }
  }
  
  var playChatSound: Bool {
    didSet { UserDefaults.standard.set(self.playChatSound, forKey: PrefsKeys.playChatSound.rawValue) }
  }
  
  var playFileTransferCompleteSound: Bool {
    didSet { UserDefaults.standard.set(self.playFileTransferCompleteSound, forKey: PrefsKeys.playFileTransferCompleteSound.rawValue) }
  }
  
  var playPrivateMessageSound: Bool {
    didSet { UserDefaults.standard.set(self.playPrivateMessageSound, forKey: PrefsKeys.playPrivateMessageSound.rawValue) }
  }
  
  var playJoinSound: Bool {
    didSet { UserDefaults.standard.set(self.playJoinSound, forKey: PrefsKeys.playJoinSound.rawValue) }
  }
  
  var playLeaveSound: Bool {
    didSet { UserDefaults.standard.set(self.playLeaveSound, forKey: PrefsKeys.playLeaveSound.rawValue) }
  }
  
  var playLoggedInSound: Bool {
    didSet { UserDefaults.standard.set(self.playLoggedInSound, forKey: PrefsKeys.playLoggedInSound.rawValue) }
  }
  
  var playErrorSound: Bool {
    didSet { UserDefaults.standard.set(self.playErrorSound, forKey: PrefsKeys.playErrorSound.rawValue) }
  }
  
  var playChatInvitationSound: Bool {
    didSet { UserDefaults.standard.set(self.playChatInvitationSound, forKey: PrefsKeys.playChatInvitationSound.rawValue) }
  }
  
  var refusePrivateChat: Bool {
    didSet { UserDefaults.standard.set(self.refusePrivateChat, forKey: PrefsKeys.refusePrivateChat.rawValue) }
  }
  
  var enableAutomaticMessage: Bool {
    didSet { UserDefaults.standard.set(self.enableAutomaticMessage, forKey: PrefsKeys.enableAutomaticMessage.rawValue) }
  }
  
  var automaticMessage: String {
    didSet { UserDefaults.standard.set(self.automaticMessage, forKey: PrefsKeys.automaticMessage.rawValue) }
  }
  
  var showBannerToolbar: Bool {
    didSet { UserDefaults.standard.set(self.showBannerToolbar, forKey: PrefsKeys.showBannerToolbar.rawValue) }
  }
  
  var showJoinLeaveMessages: Bool {
    didSet { UserDefaults.standard.set(self.showJoinLeaveMessages, forKey: PrefsKeys.showJoinLeaveMessages.rawValue) }
  }
}
