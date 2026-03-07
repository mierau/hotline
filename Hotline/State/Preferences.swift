import SwiftUI
import AppKit

struct HighlightWord: Codable, Hashable {
  var word: String
  var color: String  // "primary", "red", "orange", "yellow", "green", "blue", "purple", "pink"

  static let allColors: [String] = ["primary", "red", "orange", "yellow", "green", "blue", "purple", "pink"]

  var nsBackgroundColor: NSColor {
    switch self.color {
    case "red":    return .systemRed
    case "orange": return .systemOrange
    case "yellow": return .systemYellow
    case "green":  return .systemGreen
    case "blue":   return .systemBlue
    case "purple": return .systemPurple
    case "pink":   return NSColor(srgbRed: 1.0, green: 0.34, blue: 0.67, alpha: 1.0)
    default:       return .textColor
    }
  }

  var nsForegroundColor: NSColor {
    switch self.color {
    case "yellow": return .black
    case "primary": return .textBackgroundColor
    default:       return .white
    }
  }

  var swiftUIColor: Color {
    switch self.color {
    case "red":    return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green":  return .green
    case "blue":   return .blue
    case "purple": return .purple
    case "pink":   return Color(red: 1.0, green: 0.34, blue: 0.67)
    default:       return Color(white: 0.5)
    }
  }
}

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
  case showPrivateMessageNotifications = "show private message notifications"
  case showWatchWordNotifications = "show watch word notifications"
  case showTransferNotifications = "show transfer notifications"
  case showMentionNotifications = "show mention notifications"
  case highlightMentions = "highlight mentions"
  case mentionHighlightColor = "mention highlight color"
  case showBannerToolbar = "show banner toolbar"
  case showJoinLeaveMessages = "show join leave messages"
  case downloadFolderBookmark = "download folder bookmark"
  case filesViewMode = "files view mode"
  case watchWords = "watch words"
  case hasCompletedOnboarding = "has completed onboarding"
}

@Observable
class Prefs {
  static let shared = Prefs()
  
  private init() {
    UserDefaults.standard.register(defaults:[
      PrefsKeys.username.rawValue: "unnamed",
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
      PrefsKeys.showPrivateMessageNotifications.rawValue: true,
      PrefsKeys.showTransferNotifications.rawValue: true,
      PrefsKeys.showWatchWordNotifications.rawValue: true,
      PrefsKeys.showMentionNotifications.rawValue: true,
      PrefsKeys.highlightMentions.rawValue: true,
      PrefsKeys.mentionHighlightColor.rawValue: "primary",
      PrefsKeys.showBannerToolbar.rawValue: true,
      PrefsKeys.showJoinLeaveMessages.rawValue: true,
      PrefsKeys.filesViewMode.rawValue: "grid",
      PrefsKeys.hasCompletedOnboarding.rawValue: false,
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
    self.showPrivateMessageNotifications = UserDefaults.standard.bool(forKey: PrefsKeys.showPrivateMessageNotifications.rawValue)
    self.showTransferNotifications = UserDefaults.standard.bool(forKey: PrefsKeys.showTransferNotifications.rawValue)
    self.showWatchWordNotifications = UserDefaults.standard.bool(forKey: PrefsKeys.showWatchWordNotifications.rawValue)
    self.showMentionNotifications = UserDefaults.standard.bool(forKey: PrefsKeys.showMentionNotifications.rawValue)
    self.highlightMentions = UserDefaults.standard.bool(forKey: PrefsKeys.highlightMentions.rawValue)
    self.mentionHighlightColor = UserDefaults.standard.string(forKey: PrefsKeys.mentionHighlightColor.rawValue)!
    self.showBannerToolbar = UserDefaults.standard.bool(forKey: PrefsKeys.showBannerToolbar.rawValue)
    self.showJoinLeaveMessages = UserDefaults.standard.bool(forKey: PrefsKeys.showJoinLeaveMessages.rawValue)
    self.downloadFolderBookmark = UserDefaults.standard.data(forKey: PrefsKeys.downloadFolderBookmark.rawValue)
    self.filesViewMode = UserDefaults.standard.string(forKey: PrefsKeys.filesViewMode.rawValue)!

    self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: PrefsKeys.hasCompletedOnboarding.rawValue)

    if let watchWordsData = UserDefaults.standard.data(forKey: PrefsKeys.watchWords.rawValue) {
      if let decoded = try? JSONDecoder().decode([HighlightWord].self, from: watchWordsData) {
        self.watchWords = decoded
      } else if let legacy = try? JSONDecoder().decode([String].self, from: watchWordsData) {
        self.watchWords = legacy.map { HighlightWord(word: $0, color: "primary") }
      } else {
        self.watchWords = []
      }
    } else {
      self.watchWords = []
    }
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
  
  var showPrivateMessageNotifications: Bool {
    didSet { UserDefaults.standard.set(self.showPrivateMessageNotifications, forKey: PrefsKeys.showPrivateMessageNotifications.rawValue) }
  }

  var showTransferNotifications: Bool {
    didSet { UserDefaults.standard.set(self.showTransferNotifications, forKey: PrefsKeys.showTransferNotifications.rawValue) }
  }

  var showWatchWordNotifications: Bool {
    didSet { UserDefaults.standard.set(self.showWatchWordNotifications, forKey: PrefsKeys.showWatchWordNotifications.rawValue) }
  }

  var showMentionNotifications: Bool {
    didSet { UserDefaults.standard.set(self.showMentionNotifications, forKey: PrefsKeys.showMentionNotifications.rawValue) }
  }

  var highlightMentions: Bool {
    didSet { UserDefaults.standard.set(self.highlightMentions, forKey: PrefsKeys.highlightMentions.rawValue) }
  }

  var mentionHighlightColor: String {
    didSet { UserDefaults.standard.set(self.mentionHighlightColor, forKey: PrefsKeys.mentionHighlightColor.rawValue) }
  }

  var showBannerToolbar: Bool {
    didSet { UserDefaults.standard.set(self.showBannerToolbar, forKey: PrefsKeys.showBannerToolbar.rawValue) }
  }
  
  var showJoinLeaveMessages: Bool {
    didSet { UserDefaults.standard.set(self.showJoinLeaveMessages, forKey: PrefsKeys.showJoinLeaveMessages.rawValue) }
  }

  var filesViewMode: String {
    didSet { UserDefaults.standard.set(self.filesViewMode, forKey: PrefsKeys.filesViewMode.rawValue) }
  }

  var watchWords: [HighlightWord] {
    didSet {
      if let encoded = try? JSONEncoder().encode(self.watchWords) {
        UserDefaults.standard.set(encoded, forKey: PrefsKeys.watchWords.rawValue)
      }
    }
  }

  var hasCompletedOnboarding: Bool {
    didSet { UserDefaults.standard.set(self.hasCompletedOnboarding, forKey: PrefsKeys.hasCompletedOnboarding.rawValue) }
  }

  var downloadFolderBookmark: Data? {
    didSet { UserDefaults.standard.set(self.downloadFolderBookmark, forKey: PrefsKeys.downloadFolderBookmark.rawValue) }
  }

  var resolvedDownloadFolder: URL {
    guard let bookmarkData = self.downloadFolderBookmark else {
      return .downloadsDirectory
    }

    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
      self.downloadFolderBookmark = nil
      return .downloadsDirectory
    }

    if isStale {
      // Re-create the bookmark with current data
      if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
        self.downloadFolderBookmark = newBookmark
      } else {
        self.downloadFolderBookmark = nil
        return .downloadsDirectory
      }
    }

    // Verify the folder still exists
    guard FileManager.default.fileExists(atPath: url.path) else {
      self.downloadFolderBookmark = nil
      return .downloadsDirectory
    }

    _ = url.startAccessingSecurityScopedResource()
    return url
  }

  var downloadFolderDisplay: String? {
    guard self.downloadFolderBookmark != nil else { return nil }
    let url = self.resolvedDownloadFolder
    if url == .downloadsDirectory { return nil }
    return url.lastPathComponent
  }

}
