import Foundation
import SQLite3

actor ChatStore {
  static let shared = ChatStore()
  static let historyClearedNotification = Notification.Name("ChatStoreHistoryCleared")
  static let serverHistoryClearedNotification = Notification.Name("ChatStoreServerHistoryCleared")

  struct SessionKey: Hashable, Codable {
    let address: String
    let port: Int

    var identifier: String { "\(address):\(port)" }
  }

  struct Metadata: Codable, Identifiable {
    let address: String
    let port: Int
    var serverName: String?
    var createdAt: Date
    var updatedAt: Date

    var id: String { "\(address):\(port)" }

    mutating func update(serverName: String?, timestamp: Date) {
      if let serverName, !serverName.isEmpty {
        self.serverName = serverName
      }
      self.updatedAt = timestamp
    }
  }

  struct ServerListing: Identifiable {
    let metadata: Metadata
    let entryCount: Int

    var id: String { metadata.id }
  }

  struct EntryMetadata: Codable {
    var images: [ImageMetadata]?
    var iconID: UInt?
    var receiverName: String?
    var receiverIconID: UInt?
    var senderIsAdmin: Bool?
    /// Where a line about something elsewhere goes, like one saying someone posted to the board.
    var link: String?

    struct ImageMetadata: Codable {
      let url: String
      let width: CGFloat?
      let height: CGFloat?
    }
  }

  struct Entry: Codable {
    let id: UUID
    let body: String
    let username: String?
    let type: String
    let date: Date
    var metadata: EntryMetadata?
    var isRead: Bool = true
  }

  struct LoadResult {
    let entries: [Entry]
    let metadata: Metadata?
  }

  private let maxEntries = 2000

  private var db: OpaquePointer?
  private var stmtUpsertServer: OpaquePointer?
  private var stmtGetServerID: OpaquePointer?
  private var stmtInsertEntry: OpaquePointer?
  private var stmtLoadEntries: OpaquePointer?
  private var stmtLoadMetadata: OpaquePointer?
  private var stmtCountEntries: OpaquePointer?
  private var stmtTrimEntries: OpaquePointer?
  private var stmtUpdateMetadata: OpaquePointer?
  private var stmtLoadPrivateEntries: OpaquePointer?
  private var stmtCountPrivateEntries: OpaquePointer?
  private var stmtTrimPrivateEntries: OpaquePointer?
  private var stmtMarkPrivateRead: OpaquePointer?

  func append(entry: Entry, for key: SessionKey, serverName: String?, peerName: String? = nil) async {
    do {
      try openIfNeeded()

      let now = entry.date.timeIntervalSince1970
      let serverID = try upsertServer(key: key, serverName: serverName, timestamp: now)

      let metadataJSON: String?
      if let meta = entry.metadata {
        let data = try JSONEncoder().encode(meta)
        metadataJSON = String(data: data, encoding: .utf8)
      } else {
        metadataJSON = nil
      }

      guard let stmt = stmtInsertEntry else { return }
      sqlite3_reset(stmt)
      sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      sqlite3_bind_int64(stmt, 2, Int64(serverID))
      sqlite3_bind_text(stmt, 3, entry.body, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      if let username = entry.username {
        sqlite3_bind_text(stmt, 4, username, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      } else {
        sqlite3_bind_null(stmt, 4)
      }
      sqlite3_bind_text(stmt, 5, entry.type, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      sqlite3_bind_double(stmt, 6, entry.date.timeIntervalSince1970)
      if let json = metadataJSON {
        sqlite3_bind_text(stmt, 7, json, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      } else {
        sqlite3_bind_null(stmt, 7)
      }
      if let peerName {
        sqlite3_bind_text(stmt, 8, peerName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      } else {
        sqlite3_bind_null(stmt, 8)
      }
      sqlite3_bind_int(stmt, 9, entry.isRead ? 1 : 0)

      if sqlite3_step(stmt) != SQLITE_DONE {
        print("ChatStore: failed to insert entry —", errorMessage())
      }

      if peerName != nil {
        trimPrivateEntries(serverID: serverID, peerName: peerName!)
      } else {
        trimEntries(serverID: serverID)
      }
    }
    catch {
      print("ChatStore: failed to append entry —", error)
    }
  }

  func updateMetadata(_ metadata: EntryMetadata, for entryID: UUID, key: SessionKey) async {
    do {
      try openIfNeeded()

      let data = try JSONEncoder().encode(metadata)
      guard let json = String(data: data, encoding: .utf8) else { return }

      guard let stmt = stmtUpdateMetadata else { return }
      sqlite3_reset(stmt)
      sqlite3_bind_text(stmt, 1, json, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      sqlite3_bind_text(stmt, 2, entryID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

      if sqlite3_step(stmt) != SQLITE_DONE {
        print("ChatStore: failed to update metadata —", errorMessage())
      }
    }
    catch {
      print("ChatStore: failed to update metadata —", error)
    }
  }

  func deleteEntry(id: UUID) async {
    do {
      try openIfNeeded()

      var stmt: OpaquePointer?
      let sql = "DELETE FROM entries WHERE id = ?1"
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        print("ChatStore: failed to prepare deleteEntry —", errorMessage())
        return
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

      if sqlite3_step(stmt) != SQLITE_DONE {
        print("ChatStore: failed to delete entry —", errorMessage())
      }
    }
    catch {
      print("ChatStore: failed to delete entry —", error)
    }
  }

  func markPrivateEntriesAsRead(for key: SessionKey, peerName: String) async {
    do {
      try openIfNeeded()

      guard let serverID = findServerID(key: key) else { return }
      guard let stmt = stmtMarkPrivateRead else { return }

      sqlite3_reset(stmt)
      sqlite3_bind_int64(stmt, 1, Int64(serverID))
      sqlite3_bind_text(stmt, 2, peerName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

      if sqlite3_step(stmt) != SQLITE_DONE {
        print("ChatStore: failed to mark private entries as read —", errorMessage())
      }
    }
    catch {
      print("ChatStore: failed to mark private entries as read —", error)
    }
  }

  func deletePrivateEntries(for key: SessionKey, peerName: String) async {
    do {
      try openIfNeeded()

      guard let serverID = findServerID(key: key) else { return }

      var stmt: OpaquePointer?
      let sql = "DELETE FROM entries WHERE serverId = ?1 AND peerName = ?2"
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        print("ChatStore: failed to prepare deletePrivateEntries —", errorMessage())
        return
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_int64(stmt, 1, Int64(serverID))
      sqlite3_bind_text(stmt, 2, peerName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

      if sqlite3_step(stmt) != SQLITE_DONE {
        print("ChatStore: failed to delete private entries —", errorMessage())
      }
    }
    catch {
      print("ChatStore: failed to delete private entries —", error)
    }
  }

  func loadHistory(for key: SessionKey, peerName: String? = nil, limit: Int? = nil) async -> LoadResult {
    do {
      try openIfNeeded()

      guard let serverID = findServerID(key: key) else {
        return LoadResult(entries: [], metadata: nil)
      }

      let metadata = loadServerMetadata(serverID: serverID)
      let entries: [Entry]
      if let peerName {
        entries = loadPrivateEntries(serverID: serverID, peerName: peerName, limit: limit)
      } else {
        entries = loadEntries(serverID: serverID, limit: limit)
      }

      return LoadResult(entries: entries, metadata: metadata)
    }
    catch {
      print("ChatStore: failed to load history —", error)
      return LoadResult(entries: [], metadata: nil)
    }
  }

  func clearAll() async {
    closeDatabase()

    let fm = FileManager.default
    if let dbPath = try? databaseURL().path {
      for suffix in ["", "-wal", "-shm"] {
        let path = dbPath + suffix
        if fm.fileExists(atPath: path) {
          try? fm.removeItem(atPath: path)
        }
      }
    }

    cleanupLegacyDirectory()

    await MainActor.run {
      NotificationCenter.default.post(name: Self.historyClearedNotification, object: nil)
    }
  }

  func listServers() async -> [ServerListing] {
    do {
      try openIfNeeded()
    } catch {
      print("ChatStore: failed to list servers —", error)
      return []
    }

    var results: [ServerListing] = []
    var stmt: OpaquePointer?
    let sql = """
      SELECT s.address, s.port, s.serverName, s.createdAt, s.updatedAt, COUNT(e.id)
      FROM servers s
      LEFT JOIN entries e ON e.serverId = s.id AND e.peerName IS NULL
      GROUP BY s.id
      ORDER BY s.updatedAt DESC
      """

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      print("ChatStore: failed to prepare listServers —", errorMessage())
      return []
    }
    defer { sqlite3_finalize(stmt) }

    while sqlite3_step(stmt) == SQLITE_ROW {
      guard let address = columnText(stmt, 0) else { continue }
      let port = Int(sqlite3_column_int(stmt, 1))
      let serverName = columnText(stmt, 2)
      let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
      let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
      let entryCount = Int(sqlite3_column_int(stmt, 5))

      let metadata = Metadata(
        address: address,
        port: port,
        serverName: serverName,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
      results.append(ServerListing(metadata: metadata, entryCount: entryCount))
    }
    return results
  }

  func clearHistory(for key: SessionKey) async {
    do {
      try openIfNeeded()
    } catch {
      print("ChatStore: failed to clear server history —", error)
      return
    }

    var stmt: OpaquePointer?
    let sql = "DELETE FROM servers WHERE address = ?1 AND port = ?2"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      print("ChatStore: failed to prepare clearHistory —", errorMessage())
      return
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, key.address, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_int(stmt, 2, Int32(key.port))

    if sqlite3_step(stmt) != SQLITE_DONE {
      print("ChatStore: failed to clear history for \(key.identifier) —", errorMessage())
    }

    await MainActor.run {
      NotificationCenter.default.post(
        name: Self.serverHistoryClearedNotification,
        object: nil,
        userInfo: ["address": key.address, "port": key.port]
      )
    }
  }

  // MARK: - Database Setup

  private enum StoreError: Error {
    case databaseOpenFailed(String)
    case sqlError(String)
  }

  private func databaseURL() throws -> URL {
    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw StoreError.databaseOpenFailed("Application Support directory not found")
    }

    let appDirectory = base.appendingPathComponent("Hotline", isDirectory: true)
    if !fm.fileExists(atPath: appDirectory.path) {
      try fm.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    }

    return appDirectory.appendingPathComponent("ChatLogs.sqlite")
  }

  private func openIfNeeded() throws {
    if db != nil { return }

    let url = try databaseURL()
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
      let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
      sqlite3_close(handle)
      throw StoreError.databaseOpenFailed(msg)
    }

    db = handle

    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA foreign_keys = ON")

    try execute("""
      CREATE TABLE IF NOT EXISTS servers (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        address    TEXT NOT NULL,
        port       INTEGER NOT NULL,
        serverName TEXT,
        createdAt  REAL NOT NULL,
        updatedAt  REAL NOT NULL,
        UNIQUE(address, port)
      )
      """)

    try execute("""
      CREATE TABLE IF NOT EXISTS entries (
        id       TEXT PRIMARY KEY,
        serverId INTEGER NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
        body     TEXT NOT NULL,
        username TEXT,
        type     TEXT NOT NULL,
        date     REAL NOT NULL,
        metadata TEXT
      )
      """)

    try execute("CREATE INDEX IF NOT EXISTS idx_entries_server_date ON entries(serverId, date)")

    // Schema migration: add peerName column if missing
    try migrateAddPeerName()

    // Schema migration: add isRead column if missing
    try migrateAddIsRead()

    try prepareStatements()
    cleanupLegacyDirectory()
  }

  private func migrateAddPeerName() throws {
    var checkStmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, "SELECT peerName FROM entries LIMIT 1", -1, &checkStmt, nil)
    sqlite3_finalize(checkStmt)

    if rc != SQLITE_OK {
      try execute("ALTER TABLE entries ADD COLUMN peerName TEXT")
      try execute("CREATE INDEX IF NOT EXISTS idx_entries_peer ON entries(serverId, peerName, date)")
    }
  }

  private func migrateAddIsRead() throws {
    var checkStmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, "SELECT isRead FROM entries LIMIT 1", -1, &checkStmt, nil)
    sqlite3_finalize(checkStmt)

    if rc != SQLITE_OK {
      try execute("ALTER TABLE entries ADD COLUMN isRead INTEGER DEFAULT 1")
    }
  }

  private func prepareStatements() throws {
    stmtUpsertServer = try prepare("""
      INSERT INTO servers (address, port, serverName, createdAt, updatedAt)
      VALUES (?1, ?2, ?3, ?4, ?5)
      ON CONFLICT(address, port) DO UPDATE SET
        serverName = COALESCE(NULLIF(?3, ''), serverName),
        updatedAt = ?5
      """)

    stmtGetServerID = try prepare(
      "SELECT id FROM servers WHERE address = ?1 AND port = ?2"
    )

    stmtInsertEntry = try prepare("""
      INSERT OR REPLACE INTO entries (id, serverId, body, username, type, date, metadata, peerName, isRead)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
      """)

    stmtLoadEntries = try prepare("""
      SELECT id, body, username, type, date, metadata
      FROM entries WHERE serverId = ?1 AND peerName IS NULL ORDER BY date ASC
      """)

    stmtLoadMetadata = try prepare(
      "SELECT address, port, serverName, createdAt, updatedAt FROM servers WHERE id = ?1"
    )

    stmtCountEntries = try prepare(
      "SELECT COUNT(*) FROM entries WHERE serverId = ?1 AND peerName IS NULL"
    )

    stmtTrimEntries = try prepare("""
      DELETE FROM entries WHERE id IN (
        SELECT id FROM entries WHERE serverId = ?1 AND peerName IS NULL ORDER BY date ASC LIMIT ?2
      )
      """)

    stmtUpdateMetadata = try prepare(
      "UPDATE entries SET metadata = ?1 WHERE id = ?2"
    )

    stmtLoadPrivateEntries = try prepare("""
      SELECT id, body, username, type, date, metadata, isRead
      FROM entries WHERE serverId = ?1 AND peerName = ?2 ORDER BY date DESC
      """)

    stmtCountPrivateEntries = try prepare(
      "SELECT COUNT(*) FROM entries WHERE serverId = ?1 AND peerName = ?2"
    )

    stmtTrimPrivateEntries = try prepare("""
      DELETE FROM entries WHERE id IN (
        SELECT id FROM entries WHERE serverId = ?1 AND peerName = ?2 ORDER BY date ASC LIMIT ?3
      )
      """)

    stmtMarkPrivateRead = try prepare(
      "UPDATE entries SET isRead = 1 WHERE serverId = ?1 AND peerName = ?2 AND isRead = 0"
    )
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var stmt: OpaquePointer?
    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
      throw StoreError.sqlError(errorMessage())
    }
    return stmt
  }

  private func execute(_ sql: String) throws {
    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
      throw StoreError.sqlError(errorMessage())
    }
  }

  private func errorMessage() -> String {
    db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
  }

  private func closeDatabase() {
    let stmts: [OpaquePointer?] = [
      stmtUpsertServer, stmtGetServerID, stmtInsertEntry,
      stmtLoadEntries, stmtLoadMetadata, stmtCountEntries,
      stmtTrimEntries, stmtUpdateMetadata,
      stmtLoadPrivateEntries, stmtCountPrivateEntries, stmtTrimPrivateEntries,
      stmtMarkPrivateRead
    ]
    for stmt in stmts {
      sqlite3_finalize(stmt)
    }
    stmtUpsertServer = nil
    stmtGetServerID = nil
    stmtInsertEntry = nil
    stmtLoadEntries = nil
    stmtLoadMetadata = nil
    stmtCountEntries = nil
    stmtTrimEntries = nil
    stmtUpdateMetadata = nil
    stmtLoadPrivateEntries = nil
    stmtCountPrivateEntries = nil
    stmtTrimPrivateEntries = nil
    stmtMarkPrivateRead = nil

    if let db {
      sqlite3_close(db)
    }
    self.db = nil
  }

  // MARK: - Queries

  private func upsertServer(key: SessionKey, serverName: String?, timestamp: Double) throws -> Int32 {
    guard let stmt = stmtUpsertServer else {
      throw StoreError.sqlError("upsert statement not prepared")
    }
    sqlite3_reset(stmt)
    sqlite3_bind_text(stmt, 1, key.address, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_int(stmt, 2, Int32(key.port))
    if let name = serverName, !name.isEmpty {
      sqlite3_bind_text(stmt, 3, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    } else {
      sqlite3_bind_null(stmt, 3)
    }
    sqlite3_bind_double(stmt, 4, timestamp)
    sqlite3_bind_double(stmt, 5, timestamp)

    if sqlite3_step(stmt) != SQLITE_DONE {
      throw StoreError.sqlError(errorMessage())
    }

    guard let serverID = findServerID(key: key) else {
      throw StoreError.sqlError("server row not found after upsert")
    }
    return serverID
  }

  private func findServerID(key: SessionKey) -> Int32? {
    guard let stmt = stmtGetServerID else { return nil }
    sqlite3_reset(stmt)
    sqlite3_bind_text(stmt, 1, key.address, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_int(stmt, 2, Int32(key.port))

    defer { sqlite3_reset(stmt) }
    if sqlite3_step(stmt) == SQLITE_ROW {
      return sqlite3_column_int(stmt, 0)
    }
    return nil
  }

  private func trimEntries(serverID: Int32) {
    guard let countStmt = stmtCountEntries else { return }
    sqlite3_reset(countStmt)
    sqlite3_bind_int(countStmt, 1, serverID)

    guard sqlite3_step(countStmt) == SQLITE_ROW else { return }
    let count = Int(sqlite3_column_int(countStmt, 0))

    guard count > maxEntries else { return }
    let excess = count - maxEntries

    guard let trimStmt = stmtTrimEntries else { return }
    sqlite3_reset(trimStmt)
    sqlite3_bind_int(trimStmt, 1, serverID)
    sqlite3_bind_int(trimStmt, 2, Int32(excess))
    sqlite3_step(trimStmt)
  }

  private func trimPrivateEntries(serverID: Int32, peerName: String) {
    guard let countStmt = stmtCountPrivateEntries else { return }
    sqlite3_reset(countStmt)
    sqlite3_bind_int(countStmt, 1, serverID)
    sqlite3_bind_text(countStmt, 2, peerName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

    guard sqlite3_step(countStmt) == SQLITE_ROW else { return }
    let count = Int(sqlite3_column_int(countStmt, 0))

    guard count > maxEntries else { return }
    let excess = count - maxEntries

    guard let trimStmt = stmtTrimPrivateEntries else { return }
    sqlite3_reset(trimStmt)
    sqlite3_bind_int(trimStmt, 1, serverID)
    sqlite3_bind_text(trimStmt, 2, peerName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_int(trimStmt, 3, Int32(excess))
    sqlite3_step(trimStmt)
  }

  private func loadEntries(serverID: Int32, limit: Int?) -> [Entry] {
    guard let stmt = stmtLoadEntries else { return [] }
    sqlite3_reset(stmt)
    sqlite3_bind_int(stmt, 1, serverID)

    let decoder = JSONDecoder()
    var entries: [Entry] = []

    while sqlite3_step(stmt) == SQLITE_ROW {
      guard let idStr = columnText(stmt, 0),
            let uuid = UUID(uuidString: idStr),
            let body = columnText(stmt, 1),
            let type = columnText(stmt, 3) else {
        continue
      }

      let username = columnText(stmt, 2)
      let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

      var entryMetadata: EntryMetadata?
      if let metaStr = columnText(stmt, 5),
         let metaData = metaStr.data(using: .utf8) {
        entryMetadata = try? decoder.decode(EntryMetadata.self, from: metaData)
      }

      entries.append(Entry(
        id: uuid,
        body: body,
        username: username,
        type: type,
        date: date,
        metadata: entryMetadata
      ))
    }

    if let limit, limit < entries.count {
      return Array(entries.suffix(limit))
    }
    return entries
  }

  private func loadPrivateEntries(serverID: Int32, peerName: String, limit: Int?) -> [Entry] {
    guard let stmt = stmtLoadPrivateEntries else { return [] }
    sqlite3_reset(stmt)
    sqlite3_bind_int(stmt, 1, serverID)
    sqlite3_bind_text(stmt, 2, peerName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

    let decoder = JSONDecoder()
    var entries: [Entry] = []

    while sqlite3_step(stmt) == SQLITE_ROW {
      guard let idStr = columnText(stmt, 0),
            let uuid = UUID(uuidString: idStr),
            let body = columnText(stmt, 1),
            let type = columnText(stmt, 3) else {
        continue
      }

      let username = columnText(stmt, 2)
      let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

      var entryMetadata: EntryMetadata?
      if let metaStr = columnText(stmt, 5),
         let metaData = metaStr.data(using: .utf8) {
        entryMetadata = try? decoder.decode(EntryMetadata.self, from: metaData)
      }

      let isRead = sqlite3_column_int(stmt, 6) != 0

      entries.append(Entry(
        id: uuid,
        body: body,
        username: username,
        type: type,
        date: date,
        metadata: entryMetadata,
        isRead: isRead
      ))
    }

    if let limit, limit < entries.count {
      return Array(entries.prefix(limit))
    }
    return entries
  }

  private func loadServerMetadata(serverID: Int32) -> Metadata? {
    guard let stmt = stmtLoadMetadata else { return nil }
    sqlite3_reset(stmt)
    sqlite3_bind_int(stmt, 1, serverID)

    defer { sqlite3_reset(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

    guard let address = columnText(stmt, 0) else { return nil }
    let port = Int(sqlite3_column_int(stmt, 1))
    let serverName = columnText(stmt, 2)
    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
    let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

    return Metadata(
      address: address,
      port: port,
      serverName: serverName,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
    guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
    return String(cString: cStr)
  }

  // MARK: - Legacy Cleanup

  private func cleanupLegacyDirectory() {
    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let legacyDir = base.appendingPathComponent("Hotline", isDirectory: true)
      .appendingPathComponent("ChatLogs", isDirectory: true)
    if fm.fileExists(atPath: legacyDir.path) {
      try? fm.removeItem(at: legacyDir)
    }
  }
}
