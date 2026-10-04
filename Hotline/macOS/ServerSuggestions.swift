import SwiftUI

/// A server suggested as an address is typed in the connect form.
struct ServerSuggestion: Identifiable, Hashable, Sendable {
  enum Source: Hashable, Sendable {
    case bookmark
    case tracker
  }

  let name: String
  let address: String
  let port: Int
  let source: Source
  var login: String? = nil
  var password: String? = nil

  var id: String { "\(self.address.lowercased()):\(self.port)" }

  /// What goes in the field for it: its address, with the port if it isn't the usual one.
  var completion: String {
    self.port == HotlinePorts.DefaultServerPort ? self.address : "\(self.address):\(self.port)"
  }
}

/// Servers to suggest as an address is typed: your bookmarks, and what your trackers list. The
/// trackers are asked in the background, all at once, and what they list is kept for a few
/// minutes, for the next window.
@MainActor @Observable
final class ServerSuggestions {
  private(set) var servers: [ServerSuggestion] = []

  private static var trackerListings: (date: Date, servers: [ServerSuggestion])?
  private static let trackerListingsLifetime: TimeInterval = 10 * 60

  func load(bookmarks: [Bookmark]) async {
    let saved = bookmarks.filter { $0.type == .server }.map {
      ServerSuggestion(name: $0.name, address: $0.address, port: $0.port, source: .bookmark, login: $0.login, password: $0.password)
    }
    let trackers = bookmarks.filter { $0.type == .tracker }.map { Tracker(address: $0.address, port: $0.port) }
    self.servers = Self.merged(saved, Self.trackerListings?.servers ?? [])

    if let cached = Self.trackerListings, Date().timeIntervalSince(cached.date) < Self.trackerListingsLifetime {
      return
    }
    // Each tracker's servers as soon as it answers, since a slow one can take a while.
    var listed: [ServerSuggestion] = []
    await withTaskGroup(of: [ServerSuggestion].self) { group in
      for tracker in trackers {
        group.addTask {
          await Self.listing(of: tracker)
        }
      }
      for await servers in group {
        listed += servers
        self.servers = Self.merged(saved, listed)
      }
    }
    Self.trackerListings = (Date(), listed)
  }

  /// The bookmarks and trackers' servers with what's typed in their name or address, ones that
  /// start with it first.
  func matching(_ typed: String) -> (bookmarks: [ServerSuggestion], trackers: [ServerSuggestion]) {
    let typed = typed.trimmingCharacters(in: .whitespaces)
    guard !typed.isEmpty else {
      return ([], [])
    }
    func matches(from source: ServerSuggestion.Source, limit: Int) -> [ServerSuggestion] {
      var starting: [ServerSuggestion] = []
      var containing: [ServerSuggestion] = []
      for server in self.servers where server.source == source && server.completion.caseInsensitiveCompare(typed) != .orderedSame {
        let fields = [server.name, server.address]
        if fields.contains(where: { $0.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }) {
          starting.append(server)
        }
        else if fields.contains(where: { $0.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
          containing.append(server)
        }
      }
      return Array((starting + containing).prefix(limit))
    }
    return (matches(from: .bookmark, limit: 5), matches(from: .tracker, limit: 8))
  }

  private struct Tracker: Sendable {
    let address: String
    let port: Int
  }

  /// Each server once, the way the first list to have it has it: a bookmark, with its login, over
  /// a tracker's listing.
  private static func merged(_ lists: [ServerSuggestion]...) -> [ServerSuggestion] {
    var seen = Set<String>()
    return lists.joined().filter { seen.insert($0.id).inserted }
  }

  nonisolated private static func listing(of tracker: Tracker) async -> [ServerSuggestion] {
    var servers: [ServerSuggestion] = []
    do {
      for try await server in HotlineTrackerClient().fetchServers(address: tracker.address, port: tracker.port) {
        servers.append(ServerSuggestion(name: server.name ?? server.address, address: server.address, port: Int(server.port), source: .tracker))
      }
    }
    catch {
      // What it listed before it stopped answering, if anything.
    }
    return servers
  }
}
