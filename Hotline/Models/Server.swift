import SwiftUI

struct Server: Codable {
  var name: String?
  var description: String?
  var users: Int
  
  var address: String
  var port: Int
  var login: String
  var password: String
  
  init(name: String?, description: String?, address: String, port: Int = HotlinePorts.DefaultServerPort, users: Int = 0, login: String = "", password: String = "") {
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.users = users
    self.login = login
    self.password = password
  }
  
  init?(url: URL) {
    guard url.scheme?.lowercased() == "hotline" else {
      return nil
    }
    
    guard let host = url.host(percentEncoded: false) else {
      return nil
    }
    
    self.name = nil
    self.description = nil
    self.users = 0
    
    self.address = host.lowercased()
    self.port = url.port ?? HotlinePorts.DefaultServerPort
    
    self.login = url.user(percentEncoded: false) ?? ""
    self.password = url.password(percentEncoded: false) ?? ""
  }
  
  static func parseServerAddressAndPort(_ address: String) -> (String, Int) {
    let url = URL(string: "hotline://\(address)")
    let port = url?.port ?? HotlinePorts.DefaultServerPort
    let host = url?.host(percentEncoded: false) ?? ""
    return (host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), port)
  }
}

extension Server: Identifiable {
  var id: String { "\(address):\(port)" }
}

extension Server: Equatable {
  static func == (lhs: Server, rhs: Server) -> Bool {
    return (lhs.address == rhs.address) && (lhs.port == rhs.port) && (lhs.login == rhs.login) && (lhs.password == rhs.password)
  }
}

extension Server: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
