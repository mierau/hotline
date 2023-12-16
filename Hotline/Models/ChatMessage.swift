import SwiftUI

enum ChatMessageType {
  case agreement
  case status
  case message
  case server
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
