import SwiftUI

@Observable
class ServerState: Equatable {
  var id: UUID = UUID()
  var selection: ServerNavigationType
  var serverName: String? = nil
  var columnVisibility: NavigationSplitViewVisibility = .all
  var accountsShown: Bool = false
  var broadcastShown: Bool = false
  var fileNavigationPath: [String]? = nil
  var fileFolderPath: [String] = []
  /// Someone to send a message to, from the user list or the chat.
  var composeMessageUser: User? = nil
  /// Someone's info to show, from the user list or the chat.
  var userInfo: HotlineUserClientInfo? = nil
  /// Someone to disconnect from the server, once that's confirmed.
  var disconnectUserTarget: User? = nil
  /// People to ask into a private chat, as they're being chosen.
  var privateChatInvite: PrivateChatInvite? = nil
  /// The private chat whose subject is being changed.
  var privateChatSubjectID: UInt32? = nil
  /// The private chat to leave, once that's confirmed.
  var privateChatToLeave: UInt32? = nil

  /// The window showing this server, so the banner toolbar can bring it forward.
  @ObservationIgnored weak var window: NSWindow? = nil
//  var serverBanner: NSImage? = nil
//  var bannerBackgroundColor: Color? = nil

  init(selection: ServerNavigationType) {
    self.selection = selection
  }

  static func == (lhs: ServerState, rhs: ServerState) -> Bool {
    return lhs.id == rhs.id
  }
}

enum ServerNavigationType: Identifiable, Hashable, Equatable {
  var id: String {
    switch self {
    case .chat:
      return "Chat"
    case .news:
      return "News"
    case .board:
      return "Board"
    case .files:
      return "Files"
//    case .accounts:
//      return "Accounts"
    case .user(let userID):
      return String(userID)
    case .privateChat(let chatID):
      return "Private Chat \(chatID)"
    }
  }
  
  case chat
  case news
  case board
  case files
//  case accounts
  case user(userID: UInt16)
  case privateChat(chatID: UInt32)
}

/// People to ask into a private chat: a new one, or one you're in.
struct PrivateChatInvite: Identifiable {
  let id = UUID()
  /// The chat they're asked into, or nil to start one.
  let chatID: UInt32?
  /// Who's chosen to begin with, as when it's from someone's menu.
  var chosen: Set<UInt16> = []
}
