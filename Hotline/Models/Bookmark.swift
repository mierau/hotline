import Foundation
import SwiftData

enum BookmarkType: String, Codable {
  case tracker = "tracker"
  case server = "server"
  case temporary = "temporary"
}

@Model
final class Bookmark {
  var type: BookmarkType = BookmarkType.server
  var order: Int = 0
  
  var name: String = ""
  var address: String = ""
  var port: Int = HotlinePorts.DefaultServerPort
  
  @Attribute(.allowsCloudEncryption)
  var login: String?
  
  @Attribute(.allowsCloudEncryption)
  var password: String?
  
  @Attribute(.ephemeral)
  var expanded: Bool = false
  
  @Attribute(.ephemeral)
  var loading: Bool = false
  
  @Attribute(.ephemeral)
  var serverDescription: String? = nil
  
  @Attribute(.ephemeral)
  var serverUserCount: Int? = nil
  
  @Transient
  var servers: [Bookmark] = []
  
  func hash(into hasher: inout Hasher) {
    
  }
  
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
      
    case .server, .temporary:
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
      
    case .server, .temporary:
      return Server(name: self.name, description: self.serverDescription, address: self.address, port: self.port, login: self.login, password: self.password)
    }
  }
  
  static let DefaultBookmarks: [Bookmark] = [
    Bookmark(type: .server, name: "The Mobius Strip", address: "67.174.208.111", port: HotlinePorts.DefaultServerPort),
    Bookmark(type: .server, name: "System 7 Today", address: "hotline.system7today.com", port: HotlinePorts.DefaultServerPort),
    Bookmark(type: .tracker, name: "Featured Servers", address: "hltracker.com", port: HotlinePorts.DefaultTrackerPort)
  ]
  
  init(type: BookmarkType, name: String, address: String, port: Int, login: String? = nil, password: String? = nil) {
    self.type = type
    self.name = name
    self.address = address
    self.port = port
    
    self.login = login
    self.password = password
  }
  
  init(temporaryServer server: Server) {
    self.type = .temporary
    
    self.name = server.name ?? server.address
    self.address = server.address
    self.port = server.port
    
    self.serverDescription = server.description
    self.serverUserCount = server.users
  }
  
  init?(fileData: Data, name: String? = nil) {
    guard fileData.count <= 2000 else {
      return nil
    }
    
    var fileDataArray: [UInt8] = [UInt8](fileData)
      
    guard let headerValue = fileDataArray.consumeUInt32(),
          headerValue.fourCharCode() == "HTsc",
          let versionNumber = fileDataArray.consumeUInt16(),
          versionNumber == 1,
          fileDataArray.consume(128), // Skip 128 reserved bytes.
          let loginLength = fileDataArray.consumeUInt16(),
          let loginData: Data = fileDataArray.consumeBytes(32),
          let passwordLength = fileDataArray.consumeUInt16(),
          let passwordData: Data = fileDataArray.consumeBytes(32),
          let addressLength = fileDataArray.consumeUInt16(),
          let addressData: Data = fileDataArray.consumeBytes(256),
          let addressString = String(data: addressData[0..<Int(addressLength)], encoding: .ascii),
          let loginString = String(data: loginData[0..<Int(loginLength)], encoding: .ascii),
          let passwordString = String(data: passwordData[0..<Int(passwordLength)], encoding: .ascii) else {
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
//    guard let headerValue = fileDataArray.consumeUInt32(),
//          headerValue.fourCharCode() == "HTsc",
//          let versionNumber = fileDataArray.consumeUInt16(),
//          versionNumber == 1,
//          fileDataArray.consume(128), // Skip 128 reserved bytes.
//          let loginLength = fileDataArray.consumeUInt16(),
//          let loginData: Data = fileDataArray.consumeBytes(32),
//          let passwordLength = fileDataArray.consumeUInt16(),
//          let passwordData: Data = fileDataArray.consumeBytes(32),
//          let addressLength = fileDataArray.consumeUInt16(),
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
  
  func bookmarkFileData() -> Data? {
    guard let addressData = self.displayAddress.data(using: .ascii) else {
      return nil
    }
    
    let loginData: Data = self.login?.data(using: .ascii) ?? Data()
    let passwordData: Data = self.password?.data(using: .ascii) ?? Data()
    
    var fileData: Data = Data()
    
    fileData.appendUInt32("HTsc".fourCharCode()) // magic
    fileData.appendUInt16(0x0001) // version
    fileData.append(Data(repeating: 0x00, count: 128)) // reserved
    
    fileData.appendUInt16(UInt16(loginData.count))
    fileData.append(loginData)
    if loginData.count < 32 {
      // Pad login data to 32 bytes
      fileData.append(Data(repeating: 0x00, count: 32 - loginData.count))
    }
    
    fileData.appendUInt16(UInt16(passwordData.count))
    fileData.append(passwordData)
    if passwordData.count < 32 {
      // Pad password data to 32 bytes
      fileData.append(Data(repeating: 0x00, count: 32 - passwordData.count))
    }
    
    fileData.appendUInt16(UInt16(addressData.count))
    fileData.append(addressData)
    if passwordData.count < 256 {
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
    guard bookmark.type != .temporary else {
      print("Bookmark: Attempting to add temporary bookmark to store. Aborting.")
      return
    }
    
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
  
  func fetchServers() async {
    guard self.type == .tracker else {
      //      self.loading = false
      return
    }
    
    DispatchQueue.main.sync {
      self.loading = true
    }
    
    var fetchedBookmarks: [Bookmark] = []
    
    let client = HotlineTrackerClient()
    if let fetchedServers: [HotlineServer] = try? await client.fetchServers(address: self.address, port: self.port) {
      for fetchedServer in fetchedServers {
        if let serverName = fetchedServer.name {
          let server = Server(name: serverName, description: fetchedServer.description, address: fetchedServer.address, port: Int(fetchedServer.port), users: Int(fetchedServer.users))
          fetchedBookmarks.append(Bookmark(temporaryServer: server))
        }
      }
    }
    
    let newServers = fetchedBookmarks
    DispatchQueue.main.sync {
      self.servers = newServers
      self.loading = false
    }
  }
}
