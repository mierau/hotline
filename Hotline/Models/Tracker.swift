import SwiftUI

@Observable final class Tracker {
  static let defaultPort: Int = 5498
  
  let service: HotlineTrackerClient
  let address: String
  let port: Int
  var servers: [Server] = []
  
  init(address: String, port: Int = defaultPort, service: HotlineTrackerClient) {
    self.address = address
    self.port = port
    self.service = service
  }
  
  func fetchServers() {
//    self.service.fetch2(address: self.address, port: self.port) { hotlineServers in
//      self.servers = servers
//    }
  }
}
