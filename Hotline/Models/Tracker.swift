import SwiftUI

@Observable final class Tracker {
  let address: String
  let port: Int
  
  init(address: String, port: Int = HotlinePorts.DefaultTrackerPort) {
    self.address = address
    self.port = port
  }
}
