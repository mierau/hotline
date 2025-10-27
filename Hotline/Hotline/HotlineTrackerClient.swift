import Foundation
import Network

struct HotlineTracker: Identifiable, Equatable {
  let id: UUID = UUID()
  var address: String
  var port: UInt16

  init(_ address: String, port: UInt16 = 5498) {
    self.address = address
    self.port = port
  }

  static func == (lhs: HotlineTracker, rhs: HotlineTracker) -> Bool {
    return lhs.address == rhs.address && lhs.port == rhs.port
  }
}


/// Client for Hotline trackers
///
/// The tracker protocol:
/// 1. Client sends magic: "HTRK" + version (0x0001)
/// 2. Server echoes magic back
/// 3. Server sends header: message type, data length, server count
/// 4. Server sends listing: array of server records
class HotlineTrackerClient {
  static let MagicPacket: [UInt8] = [
    0x48, 0x54, 0x52, 0x4B, // 'HTRK'
    0x00, 0x01 // Version
  ]

  private var tracker: HotlineTracker

  init() {
    self.tracker = HotlineTracker("hltracker.com")
  }

  init(tracker: HotlineTracker) {
    self.tracker = tracker
  }

  /// Fetch server list from the tracker
  /// - Parameters:
  ///   - address: Tracker hostname or IP
  ///   - port: Tracker port (default: 5498)
  /// - Returns: AsyncThrowingStream of servers as they arrive from the tracker
  /// - Throws: Network or protocol errors
  func fetchServers(address: String, port: Int) -> AsyncThrowingStream<HotlineServer, Error> {
    return AsyncThrowingStream { continuation in
      let task = Task {
        await self.fetchServersInternal(address: address, port: port, continuation: continuation)
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  private func fetchServersInternal(address: String, port: Int, continuation: AsyncThrowingStream<HotlineServer, Error>.Continuation) async {
    do {
      // Add timeout wrapper
      try await withTimeout(seconds: 30) {
        try await self.doFetch(address: address, port: port, continuation: continuation)
      }
    } catch {
      print("HotlineTrackerClient: Error in fetchServersInternal: \(error)")
      continuation.finish(throwing: error)
    }
  }

  private func doFetch(address: String, port: Int, continuation: AsyncThrowingStream<HotlineServer, Error>.Continuation) async throws {
    // Connect to tracker (plaintext, no TLS)
    let socket = try await NetSocketNew.connect(
      host: address,
      port: UInt16(port),
      tls: .disabled
    )
    defer { Task { await socket.close() } }

    // Send magic packet
    try await socket.write(Data(HotlineTrackerClient.MagicPacket))

    // Receive magic response (6 bytes: 'HTRK' + version)
    let magicResponse = try await socket.read(6)
    let magic = magicResponse[0..<4]
    let version = UInt16(magicResponse[4]) << 8 | UInt16(magicResponse[5])

    // Validate magic ('HTRK')
    guard magic == Data([0x48, 0x54, 0x52, 0x4B]) else {
      throw NetSocketError.decodeFailed(
        NSError(domain: "HotlineTracker", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "Invalid magic response from tracker (expected 'HTRK')"
        ])
      )
    }

    print("HotlineTrackerClient: Connected to tracker (version \(version))")

    // Read server listings (may span multiple batches)
    var totalYielded = 0
    var totalEntriesParsed = 0  // Includes separators
    var totalExpectedEntries: Int = 0
    var batchCount = 0

    repeat {
        batchCount += 1

        // Receive server information header (8 bytes)
        // Format: [message type: u16][data length: u16][server count: u16][server count 2: u16]
        let messageType = try await socket.read(UInt16.self, endian: .big)
        let dataLength = try await socket.read(UInt16.self, endian: .big)
        let serverCount = try await socket.read(UInt16.self, endian: .big)
        let serverCount2 = try await socket.read(UInt16.self, endian: .big)

        // First header tells us the total expected entries (includes separators)
        if totalExpectedEntries == 0 {
          totalExpectedEntries = Int(serverCount)
        }

        print("HotlineTrackerClient: Batch #\(batchCount) - type: \(messageType), dataLen: \(dataLength), count1: \(serverCount), count2: \(serverCount2)")

        // Parse servers directly from socket stream (no buffering!)
        let trackerSeparatorRegex = /^[-]+$/
        var batchEntriesParsed = 0
        var batchServersYielded = 0

        for _ in 0..<Int(serverCount2) {
          do {
            // Decode server entry directly from socket stream
            let server = try await socket.receive(HotlineServer.self)

            batchEntriesParsed += 1
            totalEntriesParsed += 1

            // Filter out separator entries (servers with names like "-------")
            let isSeparator = server.name.map {
              (try? trackerSeparatorRegex.prefixMatch(in: $0)) != nil
            } ?? false

            if !isSeparator {
              // Convert wire format to domain model
              continuation.yield(server)
              batchServersYielded += 1
              totalYielded += 1
            }
          } catch {
            print("HotlineTrackerClient: Failed to decode entry #\(batchEntriesParsed + 1): \(error)")
            break
          }
        }

        print("HotlineTrackerClient: Batch #\(batchCount): parsed \(batchEntriesParsed) entries, yielded \(batchServersYielded) servers (filtered \(batchEntriesParsed - batchServersYielded) separators)")
        print("HotlineTrackerClient: Progress: \(totalEntriesParsed)/\(totalExpectedEntries) entries, \(totalYielded) servers yielded")

        // Safety: don't loop forever
        if batchCount >= 100 {
          print("HotlineTrackerClient: WARNING - Stopped after 100 batches")
          break
        }

    } while totalEntriesParsed < totalExpectedEntries

    print("HotlineTrackerClient: Completed - parsed \(totalEntriesParsed)/\(totalExpectedEntries) entries, yielded \(totalYielded) servers")
    continuation.finish()
  }

  private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw NSError(domain: "HotlineTracker", code: 2, userInfo: [
          NSLocalizedDescriptionKey: "Tracker request timed out after \(seconds) seconds"
        ])
      }

      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }
}
