import SwiftUI

/// A private chat: a room on the server apart from the public chat, for the people invited to it.
/// It's gone once everyone has left, so nothing said in it is kept.
struct PrivateChat: Identifiable {
  let id: UInt32
  /// What it's about, which anyone in it can set, or empty.
  var subject: String = ""
  /// Who's in it, you too.
  var users: [User] = []
  var messages: [ChatMessage] = []
  /// Who invited you, until you join. Nil once you're in, and for one you started.
  var invitation: Invitation? = nil
  /// Whether something's come since you last looked: a message, or the invitation.
  var unread: Bool = false

  struct Invitation {
    let userID: UInt16
    let name: String
  }
}
