import Foundation

/// The news articles you've read on each server, kept between visits, so when you're back, only the
/// ones you haven't read show as unread.
///
/// An article is known by its topic, the ID the server numbers it by there, and when it was posted,
/// so one that a server numbers the same after its news has been started over isn't taken for one
/// you read. When it was posted can be a day off and still match, as a server can tell it in its own
/// time zone, which daylight saving time moves. Each time a topic's articles are read from the
/// server, only those still in it are kept, so what's kept doesn't grow without end.
final class NewsReadArticles: @unchecked Sendable {
  static let shared = NewsReadArticles(fileURL: URL.applicationSupportDirectory.appending(path: "Read News Articles.json", directoryHint: .notDirectory))

  /// How far apart two times an article was posted can be, and it still be the same article.
  static let postedTolerance: TimeInterval = 24 * 60 * 60

  private let fileURL: URL
  private let lock = NSLock()
  /// By server, then by topic, then by article ID, when it was posted, in seconds since 1970, or nil
  /// when the server didn't say. Nil until read from disk, the first time it's needed.
  private var servers: [String: [String: [String: Double?]]]?
  private var saveScheduled = false

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// How a server is known: by its address, whatever its case, and its port.
  static func server(address: String, port: Int) -> String {
    "\(address.lowercased()):\(port)"
  }

  /// Which of a topic's articles, all of them as it lists them now, were read before. Any that were
  /// read and aren't in it anymore are forgotten.
  func read(of articles: [(id: UInt, posted: Date?)], in topic: String, on server: String) -> Set<UInt> {
    let (read, scheduleSave): (Set<UInt>, Bool) = self.lock.withLock {
      self.loadIfNeeded()
      let stored = self.servers?[server]?[topic] ?? [:]
      var read = Set<UInt>()
      var kept: [String: Double?] = [:]
      for article in articles {
        let key = String(article.id)
        guard let was = stored[key] else {
          continue
        }
        let posted = article.posted?.timeIntervalSince1970
        // Another article, numbered as one that was read was, as after a server's news is started
        // over.
        if let was, let posted, abs(was - posted) > Self.postedTolerance {
          continue
        }
        read.insert(article.id)
        kept.updateValue(posted ?? was, forKey: key)
      }
      guard kept != stored else {
        return (read, false)
      }
      self.servers?[server, default: [:]][topic] = kept.isEmpty ? nil : kept
      if self.servers?[server]?.isEmpty == true {
        self.servers?[server] = nil
      }
      defer { self.saveScheduled = true }
      return (read, !self.saveScheduled)
    }
    if scheduleSave {
      self.scheduleSave()
    }
    return read
  }

  /// Keeps that an article has been read. Saved a moment later, along with any others read by then.
  func markRead(id: UInt, posted: Date?, in topic: String, on server: String) {
    let scheduleSave: Bool = self.lock.withLock {
      self.loadIfNeeded()
      let key = String(id)
      let posted = posted?.timeIntervalSince1970
      if let was = self.servers?[server]?[topic]?[key], was == posted {
        return false
      }
      self.servers?[server, default: [:]][topic, default: [:]].updateValue(posted, forKey: key)
      defer { self.saveScheduled = true }
      return !self.saveScheduled
    }
    if scheduleSave {
      self.scheduleSave()
    }
  }

  /// Writes what's kept to disk.
  func save() {
    let servers: [String: [String: [String: Double?]]] = self.lock.withLock {
      self.saveScheduled = false
      return self.servers ?? [:]
    }
    guard let data = try? JSONEncoder().encode(servers) else {
      return
    }
    try? FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: self.fileURL, options: .atomic)
  }

  /// A moment from now, so that articles read one after another, as a thread's replies are, are
  /// saved together.
  private func scheduleSave() {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
      self.save()
    }
  }

  private func loadIfNeeded() {
    guard self.servers == nil else {
      return
    }
    if let data = try? Data(contentsOf: self.fileURL),
       let servers = try? JSONDecoder().decode([String: [String: [String: Double?]]].self, from: data) {
      self.servers = servers
    }
    else {
      self.servers = [:]
    }
  }
}
