import SwiftUI

@Observable final class Server {
  let name: String
  let description: String?
  let users: Int = 0
  let address: String
  let port: Int
  
  init(name: String, description: String?, address: String, port: Int) {
    self.name = name
    self.description = description
    self.address = address
    self.port = port
  }
}
