import SwiftUI

@Observable
class ServerState: Equatable {
  var id: UUID = UUID()
  var selection: ServerNavigationType
  var serverName: String? = nil
  var serverBanner: NSImage? = nil
  var bannerColors: ColorArt? = nil

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
    case .accounts:
      return "Accounts"
    case .user(let userID):
      return String(userID)
    }
  }
  
  case chat
  case news
  case board
  case files
  case accounts
  case user(userID: UInt16)
}
