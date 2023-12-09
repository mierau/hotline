import SwiftUI

@Observable final class Hotline {
  let trackerClient: HotlineTrackerClient
  
  init(trackerClient: HotlineTrackerClient) {
    self.trackerClient = trackerClient
  }
  
  @MainActor func getServers(address: String, port: Int = Tracker.defaultPort) async -> [Server] {
    let fetchedServers: [HotlineServer] = await self.trackerClient.fetchServers(address: address, port: port)
    
    var servers: [Server] = []
    
    for s in fetchedServers {
      if let serverName = s.name {
        servers.append(Server(name: serverName, description: s.description, address: s.address, port: Int(s.port), users: Int(s.users)))
      }
    }
    
    return servers
  }
}
