import SwiftUI

@Observable
final class ApplicationState {
  static let shared = ApplicationState()
  
  var activeHotline: Hotline? = nil
  var activeServerState: ServerState? = nil
  
  // Frontmost server window information
  var activeServerID: UUID? = nil
  var activeServerBanner: NSImage? = nil
  var activeServerName: String? = nil
  
  var cloudKitReady: Bool = false
}
