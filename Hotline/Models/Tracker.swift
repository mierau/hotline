import SwiftUI

@Observable final class Tracker {
  let service: HotlineTrackerClient
  let address: String
  let port: Int
  var servers: [Server] = []
  
  init(address: String, port: Int = 5498, service: HotlineTrackerClient) {
    self.address = address
    self.port = port
    self.service = service
  }
  
  func fetchServers() {
    self.service.fetch2(address: self.address, port: self.port) { servers in
      self.servers = servers
    }
  }
}
