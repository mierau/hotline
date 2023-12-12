import SwiftUI

@Observable final class Tracker {
  static let defaultPort: Int = 5498
  
  let address: String
  let port: Int
  
  init(address: String, port: Int = defaultPort) {
    self.address = address
    self.port = port
  }
}
