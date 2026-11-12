import SwiftUI

struct Server: Codable {
  var name: String?
  var description: String?
  var users: Int = 0

  var address: String
  var port: Int
  /// The port it takes TLS connections on, as a tracker lists it, or a bookmark has it, if it
  /// does. Once it's been connected to over TLS, that's known whichever way it's connected to (see
  /// `ServerTrust`).
  var tlsPort: Int?
  /// Whether it has to be connected to over TLS, as a bookmark set to be encrypted has it, rather
  /// than only tried over TLS first, as a tracker's listing has it. If it can't be, it isn't
  /// connected to without, unless that's chosen.
  var tlsRequired: Bool = false
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
    case name, description, address, port, tlsPort, tlsRequired, login, password
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
    self.tlsPort = try container.decodeIfPresent(Int.self, forKey: .tlsPort)
    self.tlsRequired = try container.decodeIfPresent(Bool.self, forKey: .tlsRequired) ?? false
    self.login = try container.decodeIfPresent(String.self, forKey: .login) ?? ""
    self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
  }

  init(name: String?, description: String?, address: String, port: Int = HotlinePorts.DefaultServerPort, tlsPort: Int? = nil, users: Int = 0, login: String? = nil, password: String? = nil) {
    self.name = name
    self.description = description
    self.address = address.lowercased()
    self.port = port
    self.tlsPort = tlsPort
    self.users = users
    self.login = login ?? ""
    self.password = password ?? ""
  }
  
  /// A server from a link to it: hotline://, or hotlines:// for one to connect to securely, as
  /// https:// is for the web, where the port is its TLS port, 5600 unless it says otherwise.
  init?(url: URL) {
    guard Self.isLink(url) else {
      return nil
    }
    
    guard let host = url.host(percentEncoded: false) else {
      return nil
    }
    // To a port a server can be on, as a link could say any.
    if let port = url.port, !HotlinePorts.valid.contains(port) {
      return nil
    }

    self.name = nil
    self.description = nil
    self.users = 0
    
    self.address = host.lowercased()
    if url.scheme?.lowercased() == Self.secureLinkScheme {
      self.port = HotlinePorts.DefaultServerPort
      self.tlsPort = url.port ?? HotlinePorts.DefaultTLSPort
      self.tlsRequired = true
    }
    else {
      self.port = url.port ?? HotlinePorts.DefaultServerPort
    }
    
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
  
  /// The schemes of links to servers: hotline://, and hotlines:// for one to connect to securely.
  static let linkSchemes: Set<String> = ["hotline", "hotlines"]
  static let secureLinkScheme = "hotlines"

  /// Whether a link is to a Hotline server, over a secure connection or not.
  static func isLink(_ url: URL) -> Bool {
    Self.linkSchemes.contains(url.scheme?.lowercased() ?? "")
  }

  /// A link to a server: hotline://, with its port if it isn't the usual one, or for one that's
  /// connected to securely, hotlines://, with its TLS port if it isn't the usual one.
  static func link(address: String, port: Int, tlsPort: Int?) -> String {
    let host = address.contains(":") ? "[\(address)]" : address
    guard let tlsPort else {
      return port == HotlinePorts.DefaultServerPort ? "hotline://\(host)" : "hotline://\(host):\(port)"
    }
    return tlsPort == HotlinePorts.DefaultTLSPort ? "\(Self.secureLinkScheme)://\(host)" : "\(Self.secureLinkScheme)://\(host):\(tlsPort)"
  }

  /// An address as it's typed, which can start with a login and password, as in
  /// user:password@hotline.example.com, or be a hotline:// link: its host and port, and the login
  /// and password, if it has them. A hotlines:// link is to connect securely, with its port the TLS
  /// port, 5600 unless it says otherwise, and the server's own port the usual one.
  static func parseServerAddress(_ address: String) -> (host: String, port: Int, login: String?, password: String?, tlsPort: Int?) {
    var rest = address.trimmingCharacters(in: .whitespacesAndNewlines)
    var secure = false
    if rest.lowercased().hasPrefix("hotline://") {
      rest = String(rest.dropFirst("hotline://".count))
    }
    else if rest.lowercased().hasPrefix("\(Self.secureLinkScheme)://") {
      rest = String(rest.dropFirst("\(Self.secureLinkScheme)://".count))
      secure = true
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
    let typedLogin = login?.isEmpty == false ? login : nil
    guard secure else {
      let (host, port) = self.parseHostAndPort(rest)
      return (host, port, typedLogin, password, nil)
    }
    let (host, tlsPort) = self.parseHostAndPort(rest, defaultPort: HotlinePorts.DefaultTLSPort)
    return (host, HotlinePorts.DefaultServerPort, typedLogin, password, tlsPort)
  }

  static func parseServerAddressAndPort(_ address: String) -> (String, Int) {
    let parsed = self.parseServerAddress(address)
    return (parsed.host, parsed.port)
  }

  private static func parseHostAndPort(_ address: String, defaultPort: Int = HotlinePorts.DefaultServerPort) -> (String, Int) {
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

        return (host.lowercased(), defaultPort)
      }
    }

    // Check if it's an IPv6 address without brackets
    // IPv6 addresses have multiple colons, IPv4:port has only one
    // Note: IPv6 may also have a zone identifier like fe80::1%en1
    let colonCount = trimmed.filter { $0 == ":" }.count
    if colonCount > 1 {
      // This is likely an IPv6 address without a port
      // Keep it as-is, including any zone identifier (e.g., %en1 for link-local)
      return (trimmed.lowercased(), defaultPort)
    }

    // Otherwise use URL parsing for IPv4 or hostnames
    let url = URL(string: "hotline://\(trimmed)")
    let port = url?.port ?? defaultPort
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
