import SwiftUI

struct Server: Codable {
  static let defaultPort: Int = 5500
  
  var name: String?
  var description: String?
  var users: Int
  var address: String
  var port: Int
  
  init(name: String?, description: String?, address: String, port: Int, users: Int = 0) {
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.users = users
  }
}

extension Server: Identifiable {
  var id: String { "\(address):\(port)" }
}

extension Server: Equatable {
  static func == (lhs: Server, rhs: Server) -> Bool {
    return (lhs.address == rhs.address) && (lhs.port == rhs.port)
  }
}

extension Server: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
