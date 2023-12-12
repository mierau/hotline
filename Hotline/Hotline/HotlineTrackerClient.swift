import Foundation
import Network

enum HotlineTrackerStatus: Int {
  case disconnected
  case connecting
  case connected
}

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

class HotlineTrackerClient {
  static let magicPacket = Data([
    0x48, 0x54, 0x52, 0x4B, // 'HTRK'
    0x00, 0x01 // Version
  ])
  
  private var tracker: HotlineTracker
  private var connectionStatus: HotlineTrackerStatus = .disconnected
  private var servers: [HotlineServer] = []
  
  private var serverAddress: NWEndpoint.Host
  private var serverPort: NWEndpoint.Port
  private var connection: NWConnection?
  private var bytes = Data()
  private var maxDataLength: Int = 0
  private var serverCount: Int = 0
  
  init() {
    let t = HotlineTracker("hltracker.com")
    self.tracker = t
    self.serverAddress = NWEndpoint.Host(t.address)
    self.serverPort = NWEndpoint.Port(rawValue: t.port)!
  }
  
  init(tracker: HotlineTracker) {
    self.tracker = tracker
    self.serverAddress = NWEndpoint.Host(tracker.address)
    self.serverPort = NWEndpoint.Port(rawValue: tracker.port)!
  }
    
  func fetchServers(address: String, port: Int, callback: (([HotlineServer]) -> Void)? = nil) async -> [HotlineServer] {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: UInt16(port))!
    
    self.reset()
    
    return await withCheckedContinuation { [weak self] continuation in
      self?.connect { [weak self] in
        continuation.resume(returning: self?.servers ?? [])
      }
    }
  }
  
  private func reset() {
    self.maxDataLength = 0
    self.serverCount = 0
    self.servers = []
  }
  
  private func connect(_ callback: (() -> Void)? = nil) {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        self?.connectionStatus = .connected
        self?.sendMagic()
      case .cancelled:
        self?.connectionStatus = .disconnected
        DispatchQueue.main.async {
          callback?()
        }
      case .failed(let err):
        print("HotlineTrackerClient: Connection error \(err)")
        self?.connectionStatus = .disconnected
        DispatchQueue.main.async {
          callback?()
        }
      default:
        return
      }
    }
    
    self.connectionStatus = .connecting
    self.connection?.start(queue: .global())
  }
  
  func disconnect() {
    self.connection?.cancel()
    self.connection = nil
  }
  
  private func sendMagic() {
    guard let c = connection else {
      print("HotlineTrackerClient: invalid connection to send magic.")
      return
    }
    
    //    let packet: [UInt8] = [0x48, 0x54, 0x52, 0x4B, 0x00, self.serverVersion]
    
    c.send(content: HotlineTrackerClient.magicPacket, completion: .contentProcessed { [weak self] (error) in
      if let err = error {
        print("HotlineTrackerClient: sending magic failed \(err)")
        return
      }
      
      self?.receiveMagic()
    })
  }
  
  private func receiveMagic() {
    guard let c = connection else {
      print("HotlineTrackerClient: invalid connection to receive magic.")
      return
    }
    
    c.receive(minimumIncompleteLength: 6, maximumLength: 6) { [weak self] (data, context, isComplete, error) in
      guard let self = self, let data = data else {
        return
      }
      
      if data.isEmpty || !data.elementsEqual(HotlineTrackerClient.magicPacket) {
        print("HotlineTrackerClient: invalid magic response")
        self.disconnect()
        return
      }
      
      if let error = error {
        print("HotlineTrackerClient: receive error \(error)")
      }
      else {
        self.receiveHeader()
      }
    }
  }
  
  private func receiveHeader() {
    guard let c = connection else {
      print("HotlineTrackerClient: invalid connection to receive header.")
      return
    }
    
    c.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let error = error {
        print("HotlineTrackerClient: receive error \(error)")
        self.disconnect()
        return
      }
      
      if let data = data, !data.isEmpty {
        self.maxDataLength = Int(data[2]) * 0xFF + Int(data[3])
        self.maxDataLength -= 4
        self.serverCount = Int(data[4]) * 256 + Int(data[5])
      }
      
      if let error = error {
        print("HotlineTrackerClient: receive error \(error)")
      }
      else {
        self.receiveListing()
      }
    }
  }
  
  private func receiveListing() {
    guard let c = connection else {
      print("HotlineTrackerClient: invalid connection to receive data.")
      return
    }
    
    c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let data = data, !data.isEmpty {
        self.bytes.append(contentsOf: data)
        
        if bytes.count >= maxDataLength {
          self.parseListing()
          print("HotlineTrackerClient: Found \(self.servers.count) servers on tracker \(self.serverAddress):\(self.serverPort)")
          self.disconnect()
          return
        }
      }
      
      if let error = error {
        print("HotlineTrackerClient: receive error \(error)")
        self.disconnect()
      }
      else {
        print("HotlineTrackerClient: not complete")
        self.receiveListing()
      }
    }
  }
  
  private func parseListing() {
    // IP address (4 bytes)
    // Port number (2 bytes)
    // Number of users (2 bytes)
    // Unused (2 bytes)
    // Name size (1 byte)
    // Name (name size)
    // Description size (1 byte)
    // Description (description size)
    
    let trackerSeparatorRegex = /^[-]+$/
    var foundServers: [HotlineServer] = []
    
    var cursor = 0
    for _ in 1...self.serverCount {
      if self.bytes.count < cursor + 12 {
        print("HotlineTrackerClient: Data isn't long enough for next server")
        break
      }
      
      if
        let ip_1 = self.bytes.readUInt8(at: cursor),
        let ip_2 = self.bytes.readUInt8(at: cursor + 1),
        let ip_3 = self.bytes.readUInt8(at: cursor + 2),
        let ip_4 = self.bytes.readUInt8(at: cursor + 3),
        let port = self.bytes.readUInt16(at: cursor + 4),
        let userCount = self.bytes.readUInt16(at: cursor + 6) {
//        let nameLengthByte = self.bytes.readUInt8(at: cursor + 10) {
        
        let (serverName, nameByteCount) = self.bytes.readPString(at: cursor + 10)
        let (serverDescription, descByteCount) = self.bytes.readPString(at: cursor + 10 + nameByteCount)
        
        if let name = serverName,
           let desc = serverDescription {
          let validName = try? trackerSeparatorRegex.prefixMatch(in: name)
          if validName == nil {
//          if name.range(of: regex, options: .regularExpression) == nil {
            let server = HotlineServer(address: "\(ip_1).\(ip_2).\(ip_3).\(ip_4)", port: port, users: userCount, name: name, description: desc)
            foundServers.append(server)
          }
        }
        
        cursor += 10 + nameByteCount + descByteCount
      }
    }
    
    self.servers = foundServers
  }
}
