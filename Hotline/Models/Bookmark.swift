import Foundation
import NetSocket
import SwiftData

enum BookmarkType: String, Codable {
  case tracker = "tracker"
  case server = "server"
}

struct BookmarkServer: Hashable, Identifiable {
  let id = UUID()
  let name: String?
  let address: String
  let port: Int
  /// The port it takes TLS connections on, as the tracker lists it, if it does.
  let tlsPort: Int?
  let description: String?
  let users: Int
  
  var server: Server {
    Server(name: self.name, description: self.description, address: self.address, port: self.port, tlsPort: self.tlsPort, users: self.users)
  }
  
  init(server: Server) {
    self.name = server.name
    self.address = server.address
    self.port = server.port
    self.tlsPort = server.tlsPort
    self.description = server.description
    self.users = server.users
  }
}

@Model
final class Bookmark: Hashable {
  // Provide explicit Hashable using stable object identity.
  // SwiftData's synthesized Hashable can be inconsistent for
  // newly inserted objects, causing SwiftUI ForEach crashes.
  static func == (lhs: Bookmark, rhs: Bookmark) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
  var type: BookmarkType = BookmarkType.server
  var order: Int = 0
  
  var name: String = ""
  var address: String = ""
  var port: Int = HotlinePorts.DefaultServerPort
  
  @Attribute(.allowsCloudEncryption)
  var login: String?

  @Attribute(.allowsCloudEncryption)
  var password: String?

  /// The port its server takes TLS connections on, for a server bookmark that's set to be connected
  /// to over TLS, or nil.
  var tlsPort: Int? = nil

  @Transient
  var displayAddress: String {
    switch self.type {
    case .tracker:
      if self.port == HotlinePorts.DefaultTrackerPort {
        return self.address
      }
      else {
        return "\(self.address):\(String(self.port))"
      }

    case .server:
      if self.port == HotlinePorts.DefaultServerPort {
        return self.address
      }
      else {
        return "\(self.address):\(String(self.port))"
      }
    }
  }
  
  @Transient
  var server: Server? {
    switch self.type {
    case .tracker:
      return nil

    case .server:
      var server = Server(name: self.name, description: nil, address: self.address, port: self.port, tlsPort: self.tlsPort, login: self.login, password: self.password)
      server.tlsRequired = self.tlsPort != nil
      return server
    }
  }

  /// Whether its server is connected to over TLS: it's set to be, or it's been connected to over
  /// TLS before, which it is from then on.
  @Transient
  var isSecure: Bool {
    self.tlsPort != nil || ServerTrust.shared.record(address: self.address, port: self.port) != nil
  }
  
  static let DefaultBookmarks: [Bookmark] = [
    Bookmark(type: .server, name: "The Mobius Strip", address: "mobius.trtphotl.com", port: HotlinePorts.DefaultServerPort),
    Bookmark(type: .server, name: "MacDomain", address: "hotline.system7today.com", port: HotlinePorts.DefaultServerPort),
    Bookmark(type: .tracker, name: "Featured Servers", address: "hltracker.com", port: HotlinePorts.DefaultTrackerPort)
  ]
  
  init(type: BookmarkType, name: String, address: String, port: Int, tlsPort: Int? = nil, login: String? = nil, password: String? = nil) {
    self.type = type
    self.name = name
    self.address = address
    self.port = port
    self.tlsPort = tlsPort

    self.login = login
    self.password = password
  }

  init?(fileData: Data, name: String? = nil) {
    guard fileData.count <= 2000 else {
      return nil
    }
    
    var fileDataArray: [UInt8] = [UInt8](fileData)
      
    guard let headerValue = fileDataArray.consume(UInt32.self),
          headerValue.fourCharCode() == "HTsc",
          let versionNumber = fileDataArray.consume(UInt16.self),
          versionNumber == 1,
          let reserved: Data = fileDataArray.consumeBytes(128),
          let loginLength = fileDataArray.consume(UInt16.self),
          let loginData: Data = fileDataArray.consumeBytes(32),
          let passwordLength = fileDataArray.consume(UInt16.self),
          let passwordData: Data = fileDataArray.consumeBytes(32),
          let addressLength = fileDataArray.consume(UInt16.self),
          let addressData: Data = fileDataArray.consumeBytes(256),
          // No longer than their fields, whatever a file says.
          let addressString = String(data: addressData.prefix(Int(addressLength)), encoding: .ascii),
          let loginString = String(data: loginData.prefix(Int(loginLength)), encoding: .ascii),
          let passwordString = String(data: passwordData.prefix(Int(passwordLength)), encoding: .ascii) else {
      return nil
    }
      
    let (addressHost, addressPort) = Server.parseServerAddressAndPort(addressString)
    
    self.type = .server
    if let name = name, !name.isEmpty {
      self.name = name
    }
    else {
      self.name = addressHost
    }
    self.address = addressHost
    self.port = addressPort
    self.login = loginString.isEmpty ? nil : loginString
    self.password = passwordString.isEmpty ? nil : passwordString
    self.tlsPort = Self.tlsPort(inReserved: reserved)
  }

  /// The four characters that start a TLS port in a bookmark file's reserved bytes: 'TLS '.
  private static let tlsPortTag: [UInt8] = [0x54, 0x4C, 0x53, 0x20]

  /// The TLS port a bookmark file keeps, for one set to connect securely, in the 128 reserved bytes
  /// after its version, which Hotline's own client, and others, pass over: 'TLS ', then the port.
  /// Nil for any other file, whose reserved bytes are all zero.
  static func tlsPort(inReserved reserved: Data) -> Int? {
    let bytes = [UInt8](reserved)
    guard bytes.count >= 6, Array(bytes[0..<4]) == Self.tlsPortTag else {
      return nil
    }
    let port = Int(bytes[4]) << 8 | Int(bytes[5])
    return (1..<Int(UInt16.max)).contains(port) ? port : nil
  }
  
  convenience init?(fileURL bookmarkFileURL: URL) {
    guard bookmarkFileURL.isFileURL,
          let fileAttributes = try? FileManager.default.attributesOfItem(atPath: bookmarkFileURL.path(percentEncoded: false)),
          let fileSize = fileAttributes[FileAttributeKey.size] as? UInt64,
          fileSize <= 2000,
          let fileData = try? Data(contentsOf: bookmarkFileURL) else {
      return nil
    }
      
    print("Bookmark: Parsing Hotline bookmark file...")
    
    let fileName = bookmarkFileURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    
    self.init(fileData: fileData, name: fileName)
    
//    var fileDataArray: [UInt8] = [UInt8](fileData)
//      
//    guard let headerValue = fileDataArray.consume(UInt32.self),
//          headerValue.fourCharCode() == "HTsc",
//          let versionNumber = fileDataArray.consume(UInt16.self),
//          versionNumber == 1,
//          fileDataArray.consume(128), // Skip 128 reserved bytes.
//          let loginLength = fileDataArray.consume(UInt16.self),
//          let loginData: Data = fileDataArray.consumeBytes(32),
//          let passwordLength = fileDataArray.consume(UInt16.self),
//          let passwordData: Data = fileDataArray.consumeBytes(32),
//          let addressLength = fileDataArray.consume(UInt16.self),
//          let addressData: Data = fileDataArray.consumeBytes(256),
//          let addressString = String(data: addressData[0..<Int(addressLength)], encoding: .ascii),
//          let loginString = String(data: loginData[0..<Int(loginLength)], encoding: .ascii),
//          let passwordString = String(data: passwordData[0..<Int(passwordLength)], encoding: .ascii) else {
//      return nil
//    }
//      
//    let (addressHost, addressPort) = Server.parseServerAddressAndPort(addressString)
//    
//    self.type = .server
//    self.name = fileName.isEmpty ? addressHost : fileName
//    self.address = addressHost
//    self.port = addressPort
//    self.login = loginString.isEmpty ? nil : loginString
//    self.password = passwordString.isEmpty ? nil : passwordString
  }
  
  /// The bookmark as a Hotline bookmark file, as Hotline's own client writes them, so it can read
  /// them too: its address, login and password, each no longer than its field, and, for one that's
  /// set to connect securely, its TLS port in the reserved bytes. See `tlsPort(inReserved:)`.
  func bookmarkFileData() -> Data? {
    guard let fullAddressData = self.displayAddress.data(using: .ascii) else {
      return nil
    }
    
    let addressData = fullAddressData.prefix(256)
    let loginData: Data = (self.login?.data(using: .ascii) ?? Data()).prefix(32)
    let passwordData: Data = (self.password?.data(using: .ascii) ?? Data()).prefix(32)
    
    var fileData: Data = Data()
    
    fileData.append("HTsc".fourCharCode(), endian: .big) // magic
    fileData.append(UInt16(0x0001), endian: .big) // version

    var reserved = Data(repeating: 0x00, count: 128)
    if let tlsPort = self.tlsPort, let port = UInt16(exactly: tlsPort) {
      reserved.replaceSubrange(0..<6, with: Self.tlsPortTag + [UInt8(port >> 8), UInt8(port & 0xFF)])
    }
    fileData.append(reserved)
    
    fileData.append(UInt16(loginData.count), endian: .big)
    fileData.append(loginData)
    if loginData.count < 32 {
      // Pad login data to 32 bytes
      fileData.append(Data(repeating: 0x00, count: 32 - loginData.count))
    }
    
    fileData.append(UInt16(passwordData.count), endian: .big)
    fileData.append(passwordData)
    if passwordData.count < 32 {
      // Pad password data to 32 bytes
      fileData.append(Data(repeating: 0x00, count: 32 - passwordData.count))
    }
    
    fileData.append(UInt16(addressData.count), endian: .big)
    fileData.append(addressData)
    if addressData.count < 256 {
      // Pad address data to 256 bytes
      fileData.append(Data(repeating: 0x00, count: 256 - addressData.count))
    }
    
    return fileData
  }
  
  static func populateDefaults(force: Bool = false, context: ModelContext) {
    if force || Bookmark.fetchCount(context: context) == 0 {
      Bookmark.add(Bookmark.DefaultBookmarks, context: context)
    }
  }
  
  static func fetchAll(context: ModelContext) -> [Bookmark] {
    let fetchDescriptor = FetchDescriptor<Bookmark>(sortBy: [.init(\.order)])
    do {
      let bookmarks: [Bookmark] = try context.fetch(fetchDescriptor)
      return bookmarks
    }
    catch {
      return []
    }
  }
  
  static func fetchCount(context: ModelContext) -> Int {
    let descriptor = FetchDescriptor<Bookmark>()
    return (try? context.fetchCount(descriptor)) ?? 0
  }
  
  static func deleteAll(context: ModelContext) {
    try? context.delete(model: Bookmark.self)
  }
  
  static func add(_ bookmark: Bookmark, context: ModelContext) {
    let existingBookmarks = Bookmark.fetchAll(context: context)
    
    // Reindex bookmarks before insert.
    for existingBookmark in existingBookmarks {
      existingBookmark.order += 1
    }
    
    // Insert new bookmark at start.
    bookmark.order = 0
    context.insert(bookmark)
  }
  
  static func add(_ bookmarks: [Bookmark], context: ModelContext) {
    let existingBookmarks = Bookmark.fetchAll(context: context)
    
    // Reindex bookmarks before insert.
    for existingBookmark in existingBookmarks {
      existingBookmark.order += bookmarks.count
    }
    
    // Insert new bookmarks at start.
    var bookmarkIndex = 0
    for newBookmark in bookmarks {
      newBookmark.order = bookmarkIndex
      context.insert(newBookmark)
      bookmarkIndex += 1
      
      print("Bookmark: added \(newBookmark.name)")
    }
  }
  
  static func delete(_ bookmark: Bookmark, context: ModelContext) {
    // Delete bookmark
    context.delete(bookmark)
    
    // Reindex bookmarks
    let existingBookmarks = Bookmark.fetchAll(context: context)
    var index = 0
    for existingBookmark in existingBookmarks {
      existingBookmark.order = index
      index += 1
    }
  }
  
  static func delete(at indexes: IndexSet, context: ModelContext) {
    var existingBookmarks = Bookmark.fetchAll(context: context)
//    existingBookmarks.remove(atOffsets: indexes)
    let bookmarksToDelete = indexes.map { existingBookmarks[$0] }
    
    // Delete bookmark
    for bookmark in bookmarksToDelete {
      context.delete(bookmark)
    }
    
    // Reindex bookmarks
    var index = 0
    existingBookmarks.remove(atOffsets: indexes)
    for existingBookmark in existingBookmarks {
      existingBookmark.order = index
      index += 1
    }
    
    do {
      try context.save()
    }
    catch {
      print("Bookmark: Failed to save bookmark deletions")
    }
  }
  
  static func move(_ indexes: IndexSet, to newIndex: Int, context: ModelContext) {
    guard Bookmark.fetchCount(context: context) >= indexes.count else {
      print("Bookmark: Not enough bookmarks to move requested set")
      return
    }
    
    // Perform move
    var existingBookmarks = Bookmark.fetchAll(context: context)
    existingBookmarks.move(fromOffsets: indexes, toOffset: newIndex)
    
    // Reindex bookmarks
    var index = 0
    for existingBookmark in existingBookmarks {
      existingBookmark.order = index
      index += 1
    }
    
    do {
      try context.save()
    }
    catch {
      print("Bookmark: Failed to save bookmark reordering")
    }
  }
  
  /// The servers a tracker lists, as many as came before anything went wrong, or, when none did,
  /// why not: it couldn't be reached, or stopped answering.
  func fetchServers() async throws -> [BookmarkServer] {
    guard self.type == .tracker else {
      return []
    }

    var fetchedBookmarks: [BookmarkServer] = []

    let client = HotlineTrackerClient()
    do {
      for try await fetchedServer in client.fetchServers(address: self.address, port: self.port) {
        print("FETCHED SERVER", fetchedServer)
        // So it's tried over TLS however it's connected to, not only from this list.
        ServerTrust.shared.noteListed(address: fetchedServer.address, port: Int(fetchedServer.port), tlsPort: fetchedServer.tlsPort.map(Int.init))
        if let serverName = fetchedServer.name {
          let server = Server(name: serverName, description: fetchedServer.description, address: fetchedServer.address, port: Int(fetchedServer.port), tlsPort: fetchedServer.tlsPort.map(Int.init), users: Int(fetchedServer.users))
          fetchedBookmarks.append(BookmarkServer(server: server))
        }
      }
    } catch {
      print("Failed to fetch servers from tracker: \(error)")
      if fetchedBookmarks.isEmpty {
        throw error
      }
    }

    return fetchedBookmarks
  }
}
