import SwiftUI

struct Server: Codable {
  var name: String?
  var description: String?
  var users: Int

  var address: String
  var port: Int
  var login: String
  var password: String
  var useTLS: Bool
  
  var displayAddress: String {
    if self.port == HotlinePorts.DefaultServerPort {
      return self.address
    }
    else {
      // Wrap IPv6 addresses in brackets when displaying with port
      if self.address.contains(":") {
        return "[\(self.address)]:\(String(self.port))"
      } else {
        return "\(self.address):\(String(self.port))"
      }
    }
  }
  
  init(name: String?, description: String?, address: String, port: Int = HotlinePorts.DefaultServerPort, users: Int = 0, login: String? = nil, password: String? = nil, useTLS: Bool = false) {
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.users = users
    self.login = login ?? ""
    self.password = password ?? ""
    self.useTLS = useTLS
  }
  
  init?(url: URL) {
    guard url.scheme?.lowercased() == "hotline" || url.scheme?.lowercased() == "hotlines" else {
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
    self.useTLS = url.scheme?.lowercased() == "hotlines"
  }
  
  static func parseServerAddressAndPort(_ address: String) -> (String, Int) {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check if this looks like an IPv6 address (contains colons but no port delimiter)
    // IPv6 addresses can be:
    // - fe80::1234
    // - [fe80::1234]:5500 (with port)
    // - 2001:db8::1
    // - [2001:db8::1]:6500 (with port)

    // If it starts with [, it's bracketed IPv6 with optional port
    if trimmed.hasPrefix("[") {
      // Find the closing bracket
      if let closeBracketIndex = trimmed.firstIndex(of: "]") {
        let hostEndIndex = trimmed.index(after: closeBracketIndex)
        let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracketIndex])

        // Check if there's a port after the bracket
        if hostEndIndex < trimmed.endIndex && trimmed[closeBracketIndex...].contains(":") {
          let portString = trimmed[trimmed.index(after: hostEndIndex)...]
          if let port = Int(portString) {
            return (host.lowercased(), port)
          }
        }

        return (host.lowercased(), HotlinePorts.DefaultServerPort)
      }
    }

    // Check if it's an IPv6 address without brackets
    // IPv6 addresses have multiple colons, IPv4:port has only one
    // Note: IPv6 may also have a zone identifier like fe80::1%en1
    let colonCount = trimmed.filter { $0 == ":" }.count
    if colonCount > 1 {
      // This is likely an IPv6 address without a port
      // Keep it as-is, including any zone identifier (e.g., %en1 for link-local)
      return (trimmed.lowercased(), HotlinePorts.DefaultServerPort)
    }

    // Otherwise use URL parsing for IPv4 or hostnames
    let url = URL(string: "hotline://\(trimmed)")
    let port = url?.port ?? HotlinePorts.DefaultServerPort
    let host = url?.host(percentEncoded: false) ?? ""
    return (host.lowercased(), port)
  }
}

extension Server: Identifiable {
  var id: String { "\(address):\(port)" }
}

extension Server: Equatable {
  static func == (lhs: Server, rhs: Server) -> Bool {
    return (lhs.address == rhs.address) && (lhs.port == rhs.port) && (lhs.login == rhs.login) && (lhs.password == rhs.password) && (lhs.useTLS == rhs.useTLS)
  }
}

extension Server: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
