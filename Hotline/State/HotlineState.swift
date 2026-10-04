import SwiftUI
import UserNotifications

// MARK: - Connection Status

enum HotlineConnectionStatus: Equatable {
  case disconnected
  case connecting
  case connected
  case loggedIn
  case failed(String)

  var isLoggingIn: Bool {
    self == .connecting || self == .connected
  }

  var isConnected: Bool {
    return self == .connected || self == .loggedIn
  }
}

struct FileSearchConfig: Equatable {
  /// Number of folders we process before we start applying delay backoff.
  var initialBurstCount: Int = 15
  /// Base delay applied between folder requests during the backoff phase.
  var initialDelay: TimeInterval = 0.02
  /// Multiplier used to increase the delay after each processed folder in backoff.
  var backoffMultiplier: Double = 1.1
  /// Maximum delay cap so searches don't stall out during long walks.
  var maxDelay: TimeInterval = 1.0
  /// Maximum recursion depth allowed during file search.
  var maxDepth: Int = 40
  /// Limit for repeated folder loops (guards against circular server listings).
  var loopRepetitionLimit: Int = 4
  /// Number of child folders that get prioritized after a matching parent is found.
  var hotBurstLimit: Int = 2
  /// Maximum age, in seconds, that a cached folder listing is treated as fresh.
  var cacheTTL: TimeInterval = 60 * 15
  /// Upper bound on the number of folder listings retained in the cache.
  var maxCachedFolders: Int = 1024 * 3
}

enum FileSearchStatus: Equatable {
  case idle
  case searching(processed: Int, pending: Int)
  case completed(processed: Int)
  case cancelled(processed: Int)
  case failed(String)

  var isActive: Bool {
    if case .searching = self {
      return true
    }
    return false
  }
}

// MARK: - Message Board Post

struct MessageBoardPost: Identifiable, Hashable {
  let id: UUID = UUID()
  let username: String?
  let date: Date?
  let rawDateString: String?
  let body: String
  /// True when the date had no explicit year and the year was inferred.
  let yearInferred: Bool

  private static let drawingCharacters = CharacterSet(charactersIn: #"|/\_-=+*#@[]()<>{}^~`"#)

  /// Heuristic: true when the post body contains ASCII art.
  /// Looks for a contiguous run of 3+ lines where each line has a high
  /// ratio of drawing characters, so mixed posts (art banner + normal
  /// text) are still detected.
  var looksLikeASCIIArt: Bool {
    let lines = self.body.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 3 else { return false }

    var consecutiveArtLines = 0

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Blank lines inside art are common — keep the run going.
      if trimmed.isEmpty {
        if consecutiveArtLines > 0 {
          continue
        } else {
          consecutiveArtLines = 0
          continue
        }
      }

      var drawingCount = 0
      var totalCount = 0

      for scalar in trimmed.unicodeScalars {
        guard scalar.isASCII, scalar != " " else { continue }
        totalCount += 1
        if Self.drawingCharacters.contains(scalar) {
          drawingCount += 1
        }
      }

      let ratio = totalCount > 0 ? Double(drawingCount) / Double(totalCount) : 0
      let hasInternalSpacing = trimmed.range(of: #"\S {3,}\S"#, options: .regularExpression) != nil

      if ratio > 0.30 || (ratio > 0.15 && hasInternalSpacing) {
        consecutiveArtLines += 1
        if consecutiveArtLines >= 3 {
          return true
        }
      } else {
        consecutiveArtLines = 0
      }
    }

    return false
  }

  private static let headerRegex = /^From\s+(.+)\s*\(([^)]+)\)\s*:?\s*$/

  private static let dateFormats: [(format: String, needsYear: Bool)] = [
    ("EEEE, MMMM d, yyyy, h:mm:ss a", false),
    ("EEEE, MMMM d, yyyy, h:mm a", false),
    ("EEEE MMMM d, yyyy 'at' HH:mm zzz", false),
    ("EEEE MMMM d, yyyy 'at' HH:mm", false),
    ("EEEE d/MMM/yyyy h:mm:ss a", false),
    ("EEEE d/MMM/yyyy HH:mm:ss", false),
    ("EEE MMM d HH:mm:ss yyyy", false),
    ("MMMM d, yyyy", false),
    ("MMM d, yyyy 'at' HH:mm zzz", false),
    ("MMM d, yyyy 'at' HH:mm", false),
    ("MMM d, yyyy HH:mm", false),
    ("MMM d HH:mm:ss yyyy", false),
    ("MMM d HH:mm yyyy", false),
    ("MMM d HH:mm", true),
  ]

  static func parse(_ rawPost: String) -> MessageBoardPost {
    let lines = rawPost.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)

    guard let firstLine = lines.first,
          let match = firstLine.wholeMatch(of: headerRegex) else {
      return MessageBoardPost(username: nil, date: nil, rawDateString: nil, body: rawPost.trimmingCharacters(in: .whitespacesAndNewlines), yearInferred: false)
    }

    let username = String(match.1).trimmingCharacters(in: .whitespaces)
    let rawDate = String(match.2)
    let body = lines.count > 1
      ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
      : ""

    let (date, yearInferred) = parseDate(rawDate)
    return MessageBoardPost(
      username: username,
      date: date,
      rawDateString: rawDate,
      body: body,
      yearInferred: yearInferred
    )
  }

  /// Adjust year-inferred dates so that posts stay in reverse chronological
  /// order.  Message boards are newest-first, so each post must be no newer
  /// than the one before it.
  static func adjustDates(_ posts: [MessageBoardPost]) -> [MessageBoardPost] {
    guard posts.count > 1 else { return posts }
    var result = posts
    // Track the last known date across all posts, not just the immediate
    // predecessor, so gaps from posts without dates don't break the chain.
    var lastKnownDate: Date?
    for i in 0..<result.count {
      guard let current = result[i].date else { continue }
      if let previous = lastKnownDate, result[i].yearInferred, current > previous {
        // Decrement year until this post is no newer than the last known date.
        // Only extract the components we need — using dateComponents(in:from:)
        // includes week-based fields that conflict when the year changes.
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: current)
        components.timeZone = TimeZone.current
        while let adjusted = Calendar.current.date(from: components), adjusted > previous {
          components.year = (components.year ?? 2026) - 1
        }
        if let fixed = Calendar.current.date(from: components) {
          result[i] = MessageBoardPost(
            username: result[i].username,
            date: fixed,
            rawDateString: result[i].rawDateString,
            body: result[i].body,
            yearInferred: true
          )
          lastKnownDate = fixed
          continue
        }
      }
      lastKnownDate = current
    }
    return result
  }

  private static func parseDate(_ raw: String) -> (Date?, Bool) {
    // Normalize: collapse multiple spaces
    var normalized = raw.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    // Strip ordinal suffixes: "16th" → "16", "1st" → "1", "2nd" → "2", "3rd" → "3"
    normalized = normalized.replacingOccurrences(
      of: "(\\d{1,2})(st|nd|rd|th)\\b",
      with: "$1",
      options: .regularExpression
    )
    // Insert space in "MMMdd" patterns like "Dec23" → "Dec 23", "Nov04" → "Nov 04"
    normalized = normalized.replacingOccurrences(
      of: "([A-Za-z]{3})(\\d{1,2})",
      with: "$1 $2",
      options: .regularExpression
    )

    // Extract and resolve trailing timezone abbreviation. DateFormatter with
    // en_US_POSIX may not recognize abbreviations like CET/CEST via zzz, so
    // we strip it and set formatter.timeZone directly instead.
    var tzAbbrev: String?
    let tzStripped: String
    if let range = normalized.range(of: "\\s+([A-Z]{2,5})$", options: .regularExpression) {
      let abbrev = String(normalized[range]).trimmingCharacters(in: .whitespaces)
      if TimeZone(abbreviation: abbrev) != nil {
        tzAbbrev = abbrev
      }
      tzStripped = String(normalized[normalized.startIndex..<range.lowerBound])
    } else {
      tzStripped = normalized
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")

    // Try the original string first, then the tz-stripped version with the
    // resolved timezone set on the formatter.
    let candidates: [(String, TimeZone?)] = if tzAbbrev != nil {
      [(normalized, nil), (tzStripped, TimeZone(abbreviation: tzAbbrev!))]
    } else {
      [(normalized, nil)]
    }

    for (candidate, tz) in candidates {
      formatter.timeZone = tz ?? TimeZone.current
      for (format, needsYear) in dateFormats {
        formatter.dateFormat = format
        if let date = formatter.date(from: candidate) {
          if needsYear {
            // Add current year for formats without year, fall back to
            // previous year if the result would be in the future.
            let now = Date()
            var components = Calendar.current.dateComponents([.month, .day, .hour, .minute, .second], from: date)
            components.year = Calendar.current.component(.year, from: now)
            components.timeZone = tz ?? TimeZone.current
            if let result = Calendar.current.date(from: components), result > now {
              components.year = components.year! - 1
            }
            return (Calendar.current.date(from: components), true)
          }
          return (date, false)
        }
      }
    }

    return (nil, false)
  }
}

// MARK: - HotlineState

@Observable @MainActor
class HotlineState: Equatable {
  let id: UUID = UUID()

  nonisolated static func == (lhs: HotlineState, rhs: HotlineState) -> Bool {
    return lhs.id == rhs.id
  }

  // MARK: - Static Icon Data

  #if os(macOS)
  static func getClassicIcon(_ index: Int) -> NSImage? {
    return NSImage(named: "Classic/\(index)")
  }
  #elseif os(iOS)
  static func getClassicIcon(_ index: Int) -> UIImage? {
    return UIImage(named: "Classic/\(index)")
  }
  #endif

  static let classicIconSet: [Int] = [
    141, 149, 150, 151, 172, 184, 204,
    2013, 2036, 2037, 2055, 2400, 2505, 2534,
    2578, 2592, 4004, 4015, 4022, 4104, 4131,
    4134, 4136, 4169, 4183, 4197, 4240, 4247,
    128, 129, 130, 131, 132, 133, 134,
    135, 136, 137, 138, 139, 140, 142,
    143, 144, 145, 146, 147, 148, 152,
    153, 154, 155, 156, 157, 158, 159,
    160, 161, 162, 163, 164, 165, 166,
    167, 168, 169, 170, 171, 173, 174,
    175, 176, 177, 178, 179, 180, 181,
    182, 183, 185, 186, 187, 188, 189,
    190, 191, 192, 193, 194, 195, 196,
    197, 198, 199, 200, 201, 202, 203,
    205, 206, 207, 208, 209, 212, 214,
    215, 220, 233, 236, 237, 243, 244,
    277, 410, 414, 500, 666, 1250, 1251,
    1968, 1969, 2000, 2001, 2002, 2003, 2004,
    2006, 2007, 2008, 2009, 2010, 2011, 2012,
    2014, 2015, 2016, 2017, 2018, 2019, 2020,
    2021, 2022, 2023, 2024, 2025, 2026, 2027,
    2028, 2029, 2030, 2031, 2032, 2033, 2034,
    2035, 2038, 2040, 2041, 2042, 2043, 2044,
    2045, 2046, 2047, 2048, 2049, 2050, 2051,
    2052, 2053, 2054, 2056, 2057, 2058, 2059,
    2060, 2061, 2062, 2063, 2064, 2065, 2066,
    2067, 2070, 2071, 2072, 2073, 2075, 2079,
    2098, 2100, 2101, 2102, 2103, 2104, 2105,
    2106, 2107, 2108, 2109, 2110, 2112, 2113,
    2115, 2116, 2117, 2118, 2119, 2120, 2121,
    2122, 2123, 2124, 2125, 2126, 4150, 2223,
    2401, 2402, 2403, 2404, 2500, 2501, 2502,
    2503, 2504, 2506, 2507, 2528, 2529, 2530,
    2531, 2532, 2533, 2535, 2536, 2537, 2538,
    2539, 2540, 2541, 2542, 2543, 2544, 2545,
    2546, 2547, 2548, 2549, 2550, 2551, 2552,
    2553, 2554, 2555, 2556, 2557, 2558, 2559,
    2560, 2561, 2562, 2563, 2564, 2565, 2566,
    2567, 2568, 2569, 2570, 2571, 2572, 2573,
    2574, 2575, 2576, 2577, 2579, 2580, 2581,
    2582, 2583, 2584, 2585, 2586, 2587, 2588,
    2589, 2590, 2591, 2593, 2594, 2595, 2596,
    2597, 2598, 2599, 2600, 4000, 4001, 4002,
    4003, 4005, 4006, 4007, 4008, 4009, 4010,
    4011, 4012, 4013, 4014, 4016, 4017, 4018,
    4019, 4020, 4021, 4023, 4024, 4025, 4026,
    4027, 4028, 4029, 4030, 4031, 4032, 4033,
    4034, 4035, 4036, 4037, 4038, 4039, 4040,
    4041, 4042, 4043, 4044, 4045, 4046, 4047,
    4048, 4049, 4050, 4051, 4052, 4053, 4054,
    4055, 4056, 4057, 4058, 4059, 4060, 4061,
    4062, 4063, 4064, 4065, 4066, 4067, 4068,
    4069, 4070, 4071, 4072, 4073, 4074, 4075,
    4076, 4077, 4078, 4079, 4080, 4081, 4082,
    4083, 4084, 4085, 4086, 4087, 4088, 4089,
    4090, 4091, 4092, 4093, 4094, 4095, 4096,
    4097, 4098, 4099, 4100, 4101, 4102, 4103,
    4105, 4106, 4107, 4108, 4109, 4110, 4111,
    4112, 4113, 4114, 4115, 4116, 4117, 4118,
    4119, 4120, 4121, 4122, 4123, 4124, 4125,
    4126, 4127, 4128, 4129, 4130, 4132, 4133,
    4135, 4137, 4138, 4139, 4140, 4141, 4142,
    4143, 4144, 4145, 4146, 4147, 4148, 4149,
    4151, 4152, 4153, 4154, 4155, 4156, 4157,
    4158, 4159, 4160, 4161, 4162, 4163, 4164,
    4165, 4166, 4167, 4168, 4170, 4171, 4172,
    4173, 4174, 4175, 4176, 4177, 4178, 4179,
    4180, 4181, 4182, 4184, 4185, 4186, 4187,
    4188, 4189, 4190, 4191, 4192, 4193, 4194,
    4195, 4196, 4198, 4199, 4200, 4201, 4202,
    4203, 4204, 4205, 4206, 4207, 4208, 4209,
    4210, 4211, 4212, 4213, 4214, 4215, 4216,
    4217, 4218, 4219, 4220, 4221, 4222, 4223,
    4224, 4225, 4226, 4227, 4228, 4229, 4230,
    4231, 4232, 4233, 4234, 4235, 4236, 4238,
    4241, 4242, 4243, 4244, 4245, 4246, 4248,
    4249, 4250, 4251, 4252, 4253, 4254, 31337,
    6001, 6002, 6003, 6004, 6005, 6008, 6009,
    6010, 6011, 6012, 6013, 6014, 6015, 6016,
    6017, 6018, 6023, 6025, 6026, 6027, 6028,
    6029, 6030, 6031, 6032, 6033, 6034, 6035
  ]

  // MARK: - Observable State

  var status: HotlineConnectionStatus = .disconnected
  var server: Server? {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverVersion: UInt16 = 123
  var serverName: String? {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverTitle: String = ""
  var username: String = "unnamed"
  var iconID: Int = 414
  var access: HotlineUserAccessOptions?
  var agreed: Bool = false
  var agreementText: String? = nil

  // Users
  var users: [User] = []

  // Chat
  var broadcastMessage: String = ""
  var chat: [ChatMessage] = []
  var chatInput: String = ""
  var chatRenderedText: NSAttributedString?
  var chatRenderedCount: Int = 0
  var unreadPublicChat: Bool = false

  // Private Messages
  var privateMessages: [UInt16:[InstantMessage]] = [:]
  var unreadPrivateMessages: [UInt16:UInt16] = [:]

  // Message Board
  var messageBoard: [MessageBoardPost] = []
  var messageBoardLoaded: Bool = false
  var messageBoardSignature: String?

  // News
  var news: [NewsInfo] = []
  var newsLoaded: Bool = false
  var newsLookup: [String:NewsInfo] = [:]

  // Files
  var files: [FileInfo] = []
  var filesLoaded: Bool = false
  /// Set by post-login when a link was used to connect to a new server.
  /// The view layer observes this to navigate to the target section.
  var pendingNavigation: (section: ServerNavigationType, filePath: [String]?)? = nil

  // Accounts
  var accounts: [HotlineAccount] = []
  var accountsLoaded: Bool = false

  // Banner
  var bannerFileURL: URL? = nil
  var bannerImageFormat: Data.ImageFormat = .unknown
  #if os(macOS)
  var bannerImage: Image? = nil
  var bannerColors: ColorArt? = nil
  #elseif os(iOS)
  var bannerImage: UIImage? = nil
  #endif
  /// Loads the banner cached from an earlier visit, to show while connecting.
  @ObservationIgnored var bannerCacheTask: Task<Void, Never>? = nil
  /// Whether this connection has downloaded the server's banner yet.
  @ObservationIgnored var bannerDownloaded: Bool = false
  /// A downloaded banner that couldn't be cached, shown from its download until it's replaced or
  /// the connection ends.
  @ObservationIgnored var bannerTemporaryFileURL: URL? = nil

  // Transfers (now stored globally in AppState)
  /// Returns all transfers associated with this server
  var transfers: [TransferInfo] {
    AppState.shared.transfers.filter { $0.serverID == self.id }
  }

  // Legacy transfer tracking (for old delegate-based downloads)
  @ObservationIgnored var bannerDownloadTask: Task<Void, Never>? = nil

  // File Search
  var fileSearchResults: [FileInfo] = []
  var fileSearchStatus: FileSearchStatus = .idle
  var fileSearchQuery: String = ""
  var fileSearchConfig = FileSearchConfig()
  var fileSearchScannedFolders: Int = 0
  var fileSearchCurrentPath: [String]? = nil
  @ObservationIgnored var fileSearchSession: HotlineStateFileSearchSession? = nil
  @ObservationIgnored var fileSearchResultKeys: Set<String> = []

  // File List Cache
  struct FileListCacheEntry {
    let files: [FileInfo]
    let timestamp: Date
  }
  @ObservationIgnored var fileListCache: [String: FileListCacheEntry] = [:]

  // Error Display
  var errorDisplayed: Bool = false
  var errorMessage: String? = nil

  // Disconnect Message (server-initiated)
  var disconnectMessage: String? = nil

  // MARK: - Private State

  @ObservationIgnored var client: HotlineClient?
  @ObservationIgnored var eventTask: Task<Void, Never>?
  @ObservationIgnored var chatSessionKey: ChatStore.SessionKey?
  @ObservationIgnored var restoredChatSessionKey: ChatStore.SessionKey?
  @ObservationIgnored private var chatHistoryObserver: NSObjectProtocol?
  @ObservationIgnored private var serverHistoryObserver: NSObjectProtocol?
  @ObservationIgnored var lastPersistedMessageType: ChatMessageType?
  @ObservationIgnored var lastPersistedMessageDate: Date?
  @ObservationIgnored var restoredPrivatePeers: Set<String> = []

  // MARK: - Initialization

  init() {
    self.chatHistoryObserver = NotificationCenter.default.addObserver(
      forName: ChatStore.historyClearedNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleChatHistoryCleared()
      }
    }

    self.serverHistoryObserver = NotificationCenter.default.addObserver(
      forName: ChatStore.serverHistoryClearedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor [weak self] in
        guard let self,
              let address = notification.userInfo?["address"] as? String,
              let port = notification.userInfo?["port"] as? Int else { return }
        let clearedKey = ChatStore.SessionKey(address: address, port: port)
        if self.chatSessionKey == clearedKey {
          self.handleChatHistoryCleared()
        }
      }
    }
  }

  deinit {
    if let observer = self.chatHistoryObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = self.serverHistoryObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Utilities

  func updateServerTitle() {
    self.serverTitle = self.serverName ?? self.server?.name ?? self.server?.address ?? "Hotline"
  }
}
