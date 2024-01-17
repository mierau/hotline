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

enum HotlineTrackerStatus: Int {
  case disconnected
  case connecting
  case connected
}

private enum HotlineTrackerStage {
  case magic
  case header
  case listing
  case done
}

class HotlineTrackerClient {
  static let MagicPacket: [UInt8] = [
    0x48, 0x54, 0x52, 0x4B, // 'HTRK'
    0x00, 0x01 // Version
  ]
  
  private var tracker: HotlineTracker
  private var connectionStatus: HotlineTrackerStatus = .disconnected
  private var servers: [HotlineServer] = []

  private var socket: NetSocket = NetSocket()
  private var stage: HotlineTrackerStage = .magic
  
  private var serverAddress: String
  private var serverPort: Int
  private var expectedDataLength: Int = 0
  private var serverCount: Int = 0
  
  private var fetchContinuation: CheckedContinuation<[HotlineServer], any Error>?
  
  init() {
    let t = HotlineTracker("hltracker.com")
    self.tracker = t
    self.serverAddress = t.address
    self.serverPort = Int(t.port)
    self.socket.delegate = self
  }
  
  init(tracker: HotlineTracker) {
    self.tracker = tracker
    self.serverAddress = tracker.address
    self.serverPort = Int(tracker.port)
    self.socket.delegate = self
  }
    
  @MainActor func fetchServers(address: String, port: Int) async throws -> [HotlineServer] {
    self.serverAddress = address
    self.serverPort = Int(port)
    
    self.reset()
    
    return try await withCheckedThrowingContinuation { [weak self] continuation in
      self?.fetchContinuation = continuation
      self?.connect()
    }
  }
  
  @MainActor func close() {
    self.socket.close()
  }
  
  // MARK: -
  
  @MainActor private func reset() {
    self.expectedDataLength = 0
    self.serverCount = 0
    self.servers = []
  }
  
  @MainActor private func connect() {
    self.socket.close()
    
    self.connectionStatus = .connecting
    self.socket.connect(host: self.serverAddress, port: self.serverPort)
    self.socket.write(HotlineTrackerClient.MagicPacket)
  }
  
  @MainActor private func receiveMagic() {
    guard self.stage == .magic, self.socket.available >= HotlineTrackerClient.MagicPacket.count else {
      return
    }
    
    let magic: [UInt8] = self.socket.read(count: HotlineTrackerClient.MagicPacket.count)
    
    if magic != HotlineTrackerClient.MagicPacket {
      self.socket.close()
      return
    }
    
    self.stage = .header
    self.receiveHeader()
  }
  
  @MainActor private func receiveHeader() {
    guard self.stage == .header, self.socket.available >= 8 else {
      return
    }
    
    var header: [UInt8] = self.socket.read(count: 8)

    guard let messageType = header.consumeUInt16(),
       let dataLength = header.consumeUInt16(),
       let numberOfServers = header.consumeUInt16(),
       let numberOfServers2 = header.consumeUInt16() else {
      self.socket.close()
      return
    }
    
    print("HotlineTrackerClient: Received response header ", messageType, dataLength, numberOfServers, numberOfServers2)
    
    self.expectedDataLength = Int(dataLength)
    self.expectedDataLength -= 4 // Remove the size of the two server count fields
    self.serverCount = Int(numberOfServers)
    
    self.stage = .listing
    self.receiveListing()
  }
  
  @MainActor private func receiveListing() {
    guard self.stage == .listing, self.socket.available >= self.expectedDataLength else {
      return
    }
    
    self.parseListing(self.socket.read(count: self.expectedDataLength))
  }
  
  @MainActor private func parseListing(_ listingBytes: [UInt8]) {
    // IP address (4 bytes)
    // Port number (2 bytes)
    // Number of users (2 bytes)
    // Unused (2 bytes)
    // Name size (1 byte)
    // Name (name size)
    // Description size (1 byte)
    // Description (description size)
    
    var bytes: [UInt8] = listingBytes
    let trackerSeparatorRegex = /^[-]+$/
    var foundServers: [HotlineServer] = []
    
    for _ in 1...self.serverCount {
      guard
        let ip_1 = bytes.consumeUInt8(),
        let ip_2 = bytes.consumeUInt8(),
        let ip_3 = bytes.consumeUInt8(),
        let ip_4 = bytes.consumeUInt8(),
        let port = bytes.consumeUInt16(),
        bytes.consume(2),
        let userCount = bytes.consumeUInt16(),
        let serverName = bytes.consumePString(),
        let serverDescription = bytes.consumePString() else {
        print("HotlineTrackerClient: Data isn't long enough for next server")
        break
      }
        
      // Ignore servers that are just used as dividers in the tracker listing.
      let validName = try? trackerSeparatorRegex.prefixMatch(in: serverName)
      if validName == nil {
        let server = HotlineServer(address: "\(ip_1).\(ip_2).\(ip_3).\(ip_4)", port: port, users: userCount, name: serverName, description: serverDescription)
        foundServers.append(server)
      }
    }
    
    self.servers = foundServers
    self.stage = .done
    self.socket.close()
  }
}

// MARK: -

extension HotlineTrackerClient: NetSocketDelegate {
  @MainActor func netsocketConnected(socket: NetSocket) {
    self.connectionStatus = .connected
  }
  
  @MainActor func netsocketDisconnected(socket: NetSocket, error: Error?) {
    self.stage = .magic
    self.connectionStatus = .disconnected
    
    let servers = self.servers
    self.reset()
    
    if let continuation = self.fetchContinuation {
      self.fetchContinuation = nil
      if let err = error {
        continuation.resume(throwing: err)
      }
      else {
        continuation.resume(returning: servers)
      }
    }
  }
  
  @MainActor func netsocketReceived(socket: NetSocket, bytes: [UInt8]) {
    switch self.stage {
    case .magic:
      self.receiveMagic()
    case .header:
      self.receiveHeader()
    case .listing:
      self.receiveListing()
    case .done:
      break
    }
  }
}
