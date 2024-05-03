import SwiftUI

enum InstantMessageType {
  case message
}

enum InstantMessageDirection {
  case incoming
  case outgoing
}

struct InstantMessage: Identifiable {
  let id = UUID()
  let direction: InstantMessageDirection
  let text: String
  let type: InstantMessageType
  let date: Date
}
