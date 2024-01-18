import SwiftUI

@Observable final class Tracker {
  let address: String
  let port: Int
  
  init(address: String, port: Int = HotlinePorts.DefaultTrackerPort) {
    self.address = address
    self.port = port
  }
  
  static func parseTrackerAddressAndPort(_ address: String) -> (String, Int) {
    let url = URL(string: "hotlinetracker://\(address)")
    let port = url?.port ?? HotlinePorts.DefaultTrackerPort
    let host = url?.host(percentEncoded: false) ?? ""
    return (host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), port)
  }
}
