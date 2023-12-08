import Foundation
import Network

enum HotlineTrackerStatus: Int {
  case disconnected
  case connecting
  case connected
}

struct HotlineTracker: Identifiable {
  var address: String
  var port: UInt16
  var servers: [HotlineServer] = []
  var expanded: Bool = false
  
  var id: String { get { return self.address } }
  
  init(_ address: String, port: UInt16 = 5498) {
    self.address = address
    self.port = port
  }
}

@Observable
class HotlineTrackerClient {
  static let magicPacket = Data([
    0x48, 0x54, 0x52, 0x4B, // 'HTRK'
    0x00, 0x01 // Version
  ])
  
  @ObservationIgnored private var serverAddress: NWEndpoint.Host
  @ObservationIgnored private var serverPort: NWEndpoint.Port
  @ObservationIgnored private var connection: NWConnection?
  @ObservationIgnored private var bytes = Data()
  @ObservationIgnored private var maxDataLength: Int = 0
  @ObservationIgnored private var serverCount: Int = 0
  
  var tracker: HotlineTracker
  var connectionStatus: HotlineTrackerStatus = .disconnected
  var servers: [HotlineServer] = []
  
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
  
  func fetch(callback: (() -> Void)? = nil) {
    self.reset()
    self.connect(callback)
  }
  
  func fetch2(address: String, port: Int, callback: (([Server]) -> Void)? = nil) {
    self.serverAddress = NWEndpoint.Host(address)
    self.serverPort = NWEndpoint.Port(rawValue: UInt16(port))!
    
    self.reset()
    self.connect { [weak self] in
      var allServers: [Server] = []
      
      if let servers = self?.servers {
        for server in servers {
          let s = Server(name: server.name!, description: server.description, address: server.address, port: Int(server.port))
          allServers.append(s)
        }
      }
      
      DispatchQueue.main.async {
        callback?(allServers)
      }
    }
  }
  
  private func reset() {
    self.maxDataLength = 0
    self.serverCount = 0
  }
  
  private func connect(_ callback: (() -> Void)? = nil) {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        print("READY TO SEND AND RECEIVE DATA")
        DispatchQueue.main.async {
          self?.connectionStatus = .connected
        }
        self?.sendMagic()
      case .cancelled:
        print("CONNECTION CANCELLED")
        DispatchQueue.main.async {
          self?.connectionStatus = .disconnected
          callback?()
        }
      case .failed(let err):
        print("CONNECTION ERROR \(err)")
        DispatchQueue.main.async {
          self?.connectionStatus = .disconnected
          callback?()
        }
      default:
        print("CONNECTION OTHER THING")
      }
    }
    
    DispatchQueue.main.async {
      self.connectionStatus = .connecting
    }
    self.connection?.start(queue: .global())
  }
  
  private func disconnect() {
    guard let c = connection else {
      print("HotlineTracker: already disconnected")
      return
    }
    
    c.cancel()
    self.connection = nil
  }
  
  private func sendMagic() {
    guard let c = connection else {
      print("HotlineTracker: invalid connection to send magic.")
      return
    }
    
    //    let packet: [UInt8] = [0x48, 0x54, 0x52, 0x4B, 0x00, self.serverVersion]
    
    c.send(content: HotlineTrackerClient.magicPacket, completion: .contentProcessed { [weak self] (error) in
      if let err = error {
        print("HotlineTracker: sending magic failed \(err)")
        return
      }
      
      print("HotlineTracker: sent magic!")
      
      self?.receiveMagic()
    })
  }
  
  private func receiveMagic() {
    guard let c = connection else {
      print("HotlineTracker: invalid connection to receive magic.")
      return
    }
    
    print("HotlineTracker: receiving...")
    c.receive(minimumIncompleteLength: 6, maximumLength: 6) { [weak self] (data, context, isComplete, error) in
      guard let self = self, let data = data else {
        return
      }
      
      if data.isEmpty || !data.elementsEqual(HotlineTrackerClient.magicPacket) {
        print("HotlineTracker: invalid magic response")
        self.disconnect()
        return
      }
      //      if let data = data, !data.isEmpty {
      print("HotlineTracker: received magic response!")
      //      }
      
      if let error = error {
        print("HotlineTracker: receive error \(error)")
      }
      else {
        self.receiveHeader()
      }
    }
  }
  
  private func receiveHeader() {
    guard let c = connection else {
      print("HotlineTracker: invalid connection to receive header.")
      return
    }
    
    print("HotlineTracker: receiving...")
    c.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let error = error {
        print("HotlineTracker: receive error \(error)")
        self.disconnect()
        return
      }
      
      if let data = data, !data.isEmpty {
        print("HotlineTracker: received \(data.count) header bytes")
        
        self.maxDataLength = Int(data[2]) * 0xFF + Int(data[3])
        self.maxDataLength -= 4
        print("HotlineTracker: message size = \(self.maxDataLength)")
        
        self.serverCount = Int(data[4]) * 256 + Int(data[5])
        print("HotlineTracker: server count = \(self.serverCount)")
      }
      
      if let error = error {
        print("HotlineTracker: receive error \(error)")
      }
      else {
        self.receiveListing()
      }
    }
  }
  
  private func receiveListing() {
    guard let c = connection else {
      print("HotlineTracker: invalid connection to receive data.")
      return
    }
    
    print("HotlineTracker: receiving...")
    c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] (data, context, isComplete, error) in
      guard let self = self else {
        return
      }
      
      if let data = data, !data.isEmpty {
        print("HotlineTracker: received \(data.count) bytes")
        self.bytes.append(contentsOf: data)
        
        if bytes.count >= maxDataLength {
          self.disconnect()
          self.parseListing()
          return
        }
      }
      
      if let error = error {
        print("HotlineTracker: receive error \(error)")
        self.disconnect()
      }
      else {
        print("HotlineTracker: not complete")
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
    
    var foundServers: [HotlineServer] = []
    
    var cursor = 0
    for _ in 1...self.serverCount {
      if self.bytes.count < cursor + 12 {
        print("HotlineTracker: Data isn't long enough for next server")
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
          let server = HotlineServer(address: "\(ip_1).\(ip_2).\(ip_3).\(ip_4)", port: port, users: userCount, name: name, description: desc)
          foundServers.append(server)
        }
        
        cursor += 10 + nameByteCount + descByteCount
      }
    }
    
    DispatchQueue.main.async {
      self.tracker.servers = foundServers
//      print("CALLING CALLBACK")
      self.servers = foundServers
    }
    
  }
}
