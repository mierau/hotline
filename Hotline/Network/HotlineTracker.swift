import Foundation
import Network

struct HotlineServer: Identifiable {
  var id = UUID()
  let address: String
  let port: UInt16
  let users: UInt16
  let name: String?
  let description: String?
}

enum HotlineTrackerStatus: Int {
  case disconnected
  case connecting
  case connected
}

class HotlineTracker : ObservableObject {
  let serverAddress: NWEndpoint.Host
  let serverPort: NWEndpoint.Port = NWEndpoint.Port(rawValue: 5498)!
  let callback: ([HotlineServer]) -> Void
  
  static let magicPacket = Data([
    0x48, 0x54, 0x52, 0x4B, // 'HTRK'
    0x00, 0x01 // Version
  ])
  
  var connection: NWConnection?
  
  var bytes = Data()
  var maxDataLength: Int = 0
  var serverCount: Int = 0
  
  @Published var connectionStatus: HotlineTrackerStatus = .disconnected
  @Published var servers: [HotlineServer] = []
  
  init(address: String, callback: @escaping ([HotlineServer]) -> Void) {
    self.serverAddress = NWEndpoint.Host(address)
    self.callback = callback
  }
  
  func fetch() {
    self.reset()
    self.connect()
  }
  
  private func reset() {
    self.maxDataLength = 0
    self.serverCount = 0
  }
  
  private func connect() {
    self.connection = NWConnection(host: self.serverAddress, port: self.serverPort, using: .tcp)
    self.connection?.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
      switch newState {
      case .ready:
        print("READY TO SEND AND RECEIVE DATA")
        self?.connectionStatus = .connected
        self?.sendMagic()
      case .cancelled:
        print("CONNECTION CANCELLED")
        self?.connectionStatus = .disconnected
      case .failed(let err):
        print("CONNECTION ERROR \(err)")
        self?.connectionStatus = .disconnected
      default:
        print("CONNECTION OTHER THING")
      }
    }
    
    self.connectionStatus = .connecting
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
    
    c.send(content: HotlineTracker.magicPacket, completion: .contentProcessed { [weak self] (error) in
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
      
      if data.isEmpty || !data.elementsEqual(HotlineTracker.magicPacket) {
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
          print("HotlineTracker: done with data, should close. \(self.bytes.count) \(self.maxDataLength)")
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
    
    var servers: [HotlineServer] = []
    
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
        let userCount = self.bytes.readUInt16(at: cursor + 6),
        let nameLengthByte = self.bytes.readUInt8(at: cursor + 10) {
        
        let nameLength = Int(nameLengthByte)
        if let name = self.bytes.readString(at: cursor + 11, length: nameLength, encoding: .utf8) ?? self.bytes.readString(at: cursor + 11, length: nameLength, encoding: .ascii) {
          if let descLengthByte = self.bytes.readUInt8(at: cursor + 11 + nameLength) {
            let descLength = Int(descLengthByte)
            if let desc = self.bytes.readString(at: cursor + 11 + nameLength + 1, length: descLength, encoding: .utf8) ?? self.bytes.readString(at: cursor + 11 + nameLength + 1, length: descLength, encoding: .ascii) {
              let server = HotlineServer(address: "\(ip_1).\(ip_2).\(ip_3).\(ip_4)", port: port, users: userCount, name: name, description: desc)
              
              print("SERVER: \(server)")
              
              servers.append(server)
              
              cursor += 11 + nameLength + 1 + descLength
            }
          }
        }
      }
      
      print(cursor)
    }
    
    DispatchQueue.main.async {
      print("CALLING CALLBACK")
      self.servers = servers
      self.callback(servers)
    }
    
  }
}
