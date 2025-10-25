import Foundation
import CryptoKit
import Security

actor ChatStore {
  static let shared = ChatStore()
  static let historyClearedNotification = Notification.Name("ChatStoreHistoryCleared")

  struct SessionKey: Hashable {
    let address: String
    let port: Int

    var identifier: String { "\(address):\(port)" }
  }

  struct Metadata: Codable {
    let address: String
    let port: Int
    var serverName: String?
    var createdAt: Date
    var updatedAt: Date

    mutating func update(serverName: String?, timestamp: Date) {
      if let serverName, !serverName.isEmpty {
        self.serverName = serverName
      }
      self.updatedAt = timestamp
    }
  }

  struct Entry: Codable {
    let id: UUID
    let body: String
    let username: String?
    let type: String
    let date: Date
  }

  struct LoadResult {
    let entries: [Entry]
    let metadata: Metadata?
  }

  private struct LogFile: Codable {
    var metadata: Metadata
    var entries: [Entry]
  }

  private enum StoreError: Error {
    case encryptionFailed
    case invalidCombinedCiphertext
    case keyGenerationFailed
  }

  private let keychainKey = "chatlog-encryption-key"
  private let applicationFolderName = "Hotline"
  private let logsFolderName = "ChatLogs"
  private let fileExtension = "hlchat"
  private let maxEntries = 2000

  private var cache: [SessionKey: LogFile] = [:]
  private var cachedDirectory: URL?
  private var cachedKey: SymmetricKey?

  func append(entry: Entry, for key: SessionKey, serverName: String?) async {
    do {
      var logFile = try loadLogFile(for: key) ?? newLogFile(for: key, serverName: serverName)

      logFile.entries.append(entry)
      if logFile.entries.count > maxEntries {
        logFile.entries = Array(logFile.entries.suffix(maxEntries))
      }

      logFile.metadata.update(serverName: serverName, timestamp: entry.date)
      cache[key] = logFile

      try persist(logFile, for: key)
    }
    catch {
      print("ChatStore: failed to append entry —", error)
    }
  }

  func loadHistory(for key: SessionKey, limit: Int? = nil) async -> LoadResult {
    do {
      let logFile = try loadLogFile(for: key)
      guard let logFile else {
        return LoadResult(entries: [], metadata: nil)
      }

      let entries: [Entry]
      if let limit, limit < logFile.entries.count {
        entries = Array(logFile.entries.suffix(limit))
      }
      else {
        entries = logFile.entries
      }

      return LoadResult(entries: entries, metadata: logFile.metadata)
    }
    catch {
      print("ChatStore: failed to load history —", error)
      return LoadResult(entries: [], metadata: nil)
    }
  }

  func clearAll() async {
    let fm = FileManager.default
    if let dir = try? directoryURL(), fm.fileExists(atPath: dir.path) {
      do {
        try fm.removeItem(at: dir)
      }
      catch {
        print("ChatStore: failed to clear chat logs —", error)
      }
    }

    cache.removeAll()
    cachedDirectory = nil

    await MainActor.run {
      NotificationCenter.default.post(name: Self.historyClearedNotification, object: nil)
    }
  }

  static func digest(for string: String) -> String {
    let hash = SHA256.hash(data: Data(string.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  private func newLogFile(for key: SessionKey, serverName: String?) -> LogFile {
    let now = Date()
    var metadata = Metadata(address: key.address, port: key.port, serverName: nil, createdAt: now, updatedAt: now)
    metadata.update(serverName: serverName, timestamp: now)
    let logFile = LogFile(metadata: metadata, entries: [])
    cache[key] = logFile
    return logFile
  }

  private func loadLogFile(for key: SessionKey) throws -> LogFile? {
    if let cached = cache[key] {
      return cached
    }

    let url = try fileURL(for: key)
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else {
      return nil
    }

    let encryptedData = try Data(contentsOf: url)
    let decryptedData = try decrypt(encryptedData)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let logFile = try decoder.decode(LogFile.self, from: decryptedData)
    cache[key] = logFile
    return logFile
  }

  private func persist(_ logFile: LogFile, for key: SessionKey) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(logFile)
    let encrypted = try encrypt(data)
    let url = try fileURL(for: key)
    let fm = FileManager.default
    let directory = url.deletingLastPathComponent()
    if !fm.fileExists(atPath: directory.path) {
      try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try encrypted.write(to: url, options: .atomic)
  }

  private func directoryURL() throws -> URL {
    if let cachedDirectory {
      return cachedDirectory
    }

    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw StoreError.keyGenerationFailed
    }

    let appDirectory = base.appendingPathComponent(applicationFolderName, isDirectory: true)
    let logsDirectory = appDirectory.appendingPathComponent(logsFolderName, isDirectory: true)

    if !fm.fileExists(atPath: appDirectory.path) {
      try fm.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: logsDirectory.path) {
      try fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    cachedDirectory = logsDirectory
    return logsDirectory
  }

  private func fileURL(for key: SessionKey) throws -> URL {
    let directory = try directoryURL()
    let digest = Self.digest(for: key.identifier)
    return directory.appendingPathComponent(digest).appendingPathExtension(fileExtension)
  }

  private func encrypt(_ data: Data) throws -> Data {
    let key = try symmetricKey()
    let sealedBox = try AES.GCM.seal(data, using: key)
    guard let combined = sealedBox.combined else {
      throw StoreError.encryptionFailed
    }
    return combined
  }

  private func decrypt(_ data: Data) throws -> Data {
    let key = try symmetricKey()
    let sealedBox = try AES.GCM.SealedBox(combined: data)
    return try AES.GCM.open(sealedBox, using: key)
  }

  private func symmetricKey() throws -> SymmetricKey {
    if let cachedKey {
      return cachedKey
    }

    if let stored = DAKeychain.shared[keychainKey],
       let storedData = Data(base64Encoded: stored),
       storedData.count == 32 {
      let key = SymmetricKey(data: storedData)
      cachedKey = key
      return key
    }

    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw StoreError.keyGenerationFailed
    }

    let data = Data(bytes)
    let key = SymmetricKey(data: data)
    DAKeychain.shared[keychainKey] = data.base64EncodedString()
    cachedKey = key
    return key
  }
}
