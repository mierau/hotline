import SwiftUI

struct Server: Codable {
  var name: String?
  var description: String?
  var users: Int
  var address: String
  var port: Int
  
  init(name: String?, description: String?, address: String, port: Int = HotlinePorts.DefaultServerPort, users: Int = 0) {
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.users = users
  }
  
  static func parseServerAddressAndPort(_ address: String) -> (String, Int) {
    let url = URL(string: "hotline://\(address)")
    let port = url?.port ?? HotlinePorts.DefaultServerPort
    let host = url?.host(percentEncoded: false) ?? address
    return (host, port)
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
