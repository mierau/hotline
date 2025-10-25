import SwiftUI

enum ChatMessageType {
  case agreement
  case status
  case joined
  case left
  case message
  case server
  case signOut
}

extension ChatMessageType {
  var storageKey: String {
    switch self {
    case .agreement:
      return "agreement"
    case .status:
      return "status"
    case .joined:
      return "joined"
    case .left:
      return "left"
    case .message:
      return "message"
    case .server:
      return "server"
    case .signOut:
      return "signOut"
    }
  }

  init?(storageKey: String) {
    switch storageKey {
    case "agreement":
      self = .agreement
    case "status":
      self = .status
    case "joined":
      self = .joined
    case "left":
      self = .left
    case "message":
      self = .message
    case "server":
      self = .server
    case "signOut":
      self = .signOut
    default:
      return nil
    }
  }
}

struct ChatMessage: Identifiable {
  let id = UUID()
  
  let text: String
  let type: ChatMessageType
  let date: Date
  let username: String?
  
  static let parser = /^\s*([^\:]+):\s*([\s\S]+)$/
  
  init(text: String, type: ChatMessageType, date: Date) {
    self.type = type
    self.date = date
    
    if
      type == .message,
      let match = text.firstMatch(of: ChatMessage.parser) {
      self.username = String(match.1)
      self.text = String(match.2)
    }
    else {
      self.username = nil
      self.text = text
    }
  }
}
