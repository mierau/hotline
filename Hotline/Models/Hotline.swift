import SwiftUI

@Observable final class Hotline {
  let trackerClient: HotlineTrackerClient
  
  
  
  init(trackerClient: HotlineTrackerClient) {
    self.trackerClient = trackerClient
  }
  
  @MainActor func getServers(address: String, port: Int) async {
    let fetchedServers = await withCheckedContinuation { [weak self] continuation in
      self?.trackerClient.fetch() {
        continuation.resume(returning: [])
      }
    }
    
    
  }
}
