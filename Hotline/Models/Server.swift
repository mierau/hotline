import SwiftUI

@Observable final class Server: Identifiable, Equatable, Hashable, Codable {
  static let defaultPort: Int = 5500
  
  let id: UUID
  let name: String?
  let description: String?
  let users: Int
  let address: String
  let port: Int
  
  init(name: String?, description: String?, address: String, port: Int, users: Int = 0) {
    self.id = UUID()
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.users = users
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  static func == (lhs: Server, rhs: Server) -> Bool {
    return (lhs.address == rhs.address) && (lhs.port == rhs.port)
  }
}
