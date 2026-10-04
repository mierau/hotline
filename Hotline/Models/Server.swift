import SwiftUI

struct Server: Codable {
  var name: String?
  var description: String?
  var users: Int = 0

  var address: String
  var port: Int
  var login: String = ""
  var password: String = ""

  /// Section to navigate to after connecting (transient, not persisted).
  var initialSection: ServerNavigationType?

  /// File path to navigate to within the Files section (transient, not persisted).
  var initialFilePath: [String]?

  /// Controls what SwiftUI persists for window state restoration.
  /// Must include credentials so restored windows reconnect properly.
  /// Name is included so the window title displays during reconnection.
  enum CodingKeys: String, CodingKey {
    case name, description, address, port, login, password
  }
  
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
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    self.description = try container.decodeIfPresent(String.self, forKey: .description)
    self.address = try container.decode(String.self, forKey: .address)
    self.port = try container.decode(Int.self, forKey: .port)
    self.login = try container.decodeIfPresent(String.self, forKey: .login) ?? ""
    self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
  }

  init(name: String?, description: String?, address: String, port: Int = HotlinePorts.DefaultServerPort, users: Int = 0, login: String? = nil, password: String? = nil) {
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.users = users
    self.login = login ?? ""
    self.password = password ?? ""
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

    // Parse path for deep-linking to a section after connecting.
    // Supported paths: /, /files/..., /news, /board
    let pathComponents = url.pathComponents.filter { $0 != "/" }
      .map { $0.removingPercentEncoding ?? $0 }
    if pathComponents.isEmpty {
      // hotline://host/ → chat (but hotline://host with no path → no section)
      if !url.path.isEmpty {
        self.initialSection = .chat
      }
    } else {
      switch pathComponents.first {
      case "files":
        self.initialSection = .files
        let filePath = Array(pathComponents.dropFirst())
        self.initialFilePath = filePath.isEmpty ? nil : filePath
      case "news":
        self.initialSection = .news
      case "board":
        self.initialSection = .board
      default:
        break
      }
    }
  }
  
  /// An address as it's typed, which can start with a login and password, as in
  /// user:password@hotline.example.com, or be a hotline:// link: its host and port, and the login
  /// and password, if it has them.
  static func parseServerAddress(_ address: String) -> (host: String, port: Int, login: String?, password: String?) {
    var rest = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if rest.lowercased().hasPrefix("hotline://") {
      rest = String(rest.dropFirst("hotline://".count))
    }
    var login: String?
    var password: String?
    // At the last @, since a password can have one in it, and an address can't.
    if let at = rest.lastIndex(of: "@") {
      let credentials = rest[..<at]
      rest = String(rest[rest.index(after: at)...])
      if let colon = credentials.firstIndex(of: ":") {
        login = String(credentials[..<colon])
        password = String(credentials[credentials.index(after: colon)...])
      }
      else {
        login = String(credentials)
      }
    }
    let (host, port) = self.parseHostAndPort(rest)
    return (host, port, login?.isEmpty == false ? login : nil, password)
  }

  static func parseServerAddressAndPort(_ address: String) -> (String, Int) {
    let parsed = self.parseServerAddress(address)
    return (parsed.host, parsed.port)
  }

  private static func parseHostAndPort(_ address: String) -> (String, Int) {
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
  /// Matches on address:port only, consistent with Hashable/id.
  /// This lets openWindow(id:value:) reuse an existing server window
  /// regardless of whether the new value has different credentials.
  static func == (lhs: Server, rhs: Server) -> Bool {
    return lhs.address == rhs.address && lhs.port == rhs.port
  }
}

extension Server: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
