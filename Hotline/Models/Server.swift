import SwiftUI

@Observable final class Server: Identifiable, Equatable {
  static let defaultPort: Int = 5500
  
  let id: UUID = UUID()
  let name: String
  let description: String?
  let users: Int
  let address: String
  let port: Int
  
  init(name: String, description: String?, address: String, port: Int, users: Int = 0) {
    self.name = name
    self.description = description
    self.address = address
    self.port = port
    self.users = users
  }
  
  static func == (lhs: Server, rhs: Server) -> Bool {
    return lhs.id == rhs.id
  }
  
  static func == (lhs: HotlineServer, rhs: Server) -> Bool {
    return lhs.name == rhs.name && lhs.address == rhs.address && lhs.port == rhs.port
  }
}
