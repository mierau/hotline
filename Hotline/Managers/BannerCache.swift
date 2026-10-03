import CryptoKit
import Foundation

/// Banners from servers you've connected to before, so a server's banner can show as soon as you
/// start connecting instead of after it downloads.
///
/// Each server gets a folder, named by a hash of its address and port, holding its banner named by
/// a hash of the banner's contents. When a server changes its banner, the new one gets a different
/// URL, which is what makes the toolbar fade it in. An unchanged banner keeps its URL, so nothing
/// on screen changes.
///
/// Banners live in the app's Caches folder, which macOS can clear when space runs low, so a cached
/// banner can disappear at any time. That just means waiting for the download, as before.
actor BannerCache {
  static let shared = BannerCache()

  /// Past this many servers, or this many bytes, the least recently used servers' banners go.
  private let serverLimit = 100
  private let sizeLimit = 20 * 1024 * 1024

  /// Banners bigger than this aren't kept.
  private let bannerSizeLimit = 4 * 1024 * 1024

  private let directory: URL

  init(directory: URL? = nil) {
    self.directory = directory ?? URL.cachesDirectory
      .appending(path: Bundle.main.bundleIdentifier ?? "Hotline", directoryHint: .isDirectory)
      .appending(path: "Banners", directoryHint: .isDirectory)
  }

  /// The banner cached for a server, if there is one.
  func banner(forAddress address: String, port: Int) -> URL? {
    let serverDirectory = self.serverDirectory(address: address, port: port)
    guard let file = self.bannerFiles(in: serverDirectory).first else {
      return nil
    }
    // Built the same way as in store(_:forAddress:port:), so the same banner has the same URL.
    let fileURL = serverDirectory.appending(path: file.lastPathComponent, directoryHint: .notDirectory)
    self.markUsed(fileURL)
    return fileURL
  }

  /// Keeps a server's banner in place of the one cached before, and returns its file. A banner
  /// that hasn't changed keeps the file it already had. Nil if the banner can't be kept.
  @discardableResult
  func store(_ data: Data, forAddress address: String, port: Int) -> URL? {
    guard !data.isEmpty, data.count <= self.bannerSizeLimit else {
      return nil
    }

    let fileManager = FileManager.default
    let serverDirectory = self.serverDirectory(address: address, port: port)
    let fileURL = serverDirectory.appending(path: Self.fileName(for: data), directoryHint: .notDirectory)

    if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
      self.markUsed(fileURL)
    }
    else {
      do {
        try fileManager.createDirectory(at: serverDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
      }
      catch {
        return nil
      }
    }

    // Drop the banner this one replaces.
    for oldFileURL in self.bannerFiles(in: serverDirectory) where oldFileURL.lastPathComponent != fileURL.lastPathComponent {
      try? fileManager.removeItem(at: oldFileURL)
    }

    self.trim()
    return fileURL
  }

  /// Forgets a server's banner, for when the server no longer has one.
  func removeBanner(forAddress address: String, port: Int) {
    try? FileManager.default.removeItem(at: self.serverDirectory(address: address, port: port))
  }

  // MARK: - Files

  private func serverDirectory(address: String, port: Int) -> URL {
    // Host names aren't case sensitive, so "Example.com" and "example.com" share a banner.
    let server = "\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
    return self.directory.appending(path: Self.hash(Data(server.utf8)), directoryHint: .isDirectory)
  }

  /// The banners in a server's folder, most recently used first. There's normally just one.
  private func bannerFiles(in serverDirectory: URL) -> [URL] {
    let files = try? FileManager.default.contentsOfDirectory(
      at: serverDirectory,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: .skipsHiddenFiles
    )
    return (files ?? []).sorted { Self.lastUsed($0) > Self.lastUsed($1) }
  }

  /// Records that a banner was used, so it outlasts ones that haven't been.
  private func markUsed(_ fileURL: URL) {
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path(percentEncoded: false))
  }

  /// Removes the least recently used servers' banners once there are too many or they take up too
  /// much space. The most recently used one, the banner just stored, always stays.
  private func trim() {
    let fileManager = FileManager.default
    guard let serverDirectories = try? fileManager.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
      return
    }

    let servers = serverDirectories
      .map { (directory: $0, banner: self.bannerFiles(in: $0).first) }
      .sorted { Self.lastUsed($0.banner) > Self.lastUsed($1.banner) }

    var totalSize = 0
    for (index, server) in servers.enumerated() {
      totalSize += server.banner.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
      if index > 0 && (server.banner == nil || index >= self.serverLimit || totalSize > self.sizeLimit) {
        try? fileManager.removeItem(at: server.directory)
      }
    }
  }

  private static func lastUsed(_ fileURL: URL?) -> Date {
    (try? fileURL?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
  }

  /// A banner's file name: a hash of its contents, with the extension for its format.
  private static func fileName(for data: Data) -> String {
    let name = self.hash(data)
    switch data.detectedImageFormat {
    case .gif: return "\(name).gif"
    case .jpeg: return "\(name).jpg"
    case .png: return "\(name).png"
    case .webp: return "\(name).webp"
    case .unknown: return name
    }
  }

  private static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
  }
}
