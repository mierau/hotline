import SwiftUI

extension EnvironmentValues {
  @Entry var appState: AppState = AppState.shared
}

@Observable
final class AppState {
  static let shared = AppState()
  
  private init() {
    
  }
  
  var activeHotline: Hotline? = nil
  var activeServerState: ServerState? = nil
  
  // Frontmost server window information
  var activeServerID: UUID? = nil
  var activeServerBanner: NSImage? = nil
  var activeServerName: String? = nil
  
  var cloudKitReady: Bool = false
}
