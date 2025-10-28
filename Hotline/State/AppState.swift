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

  var cloudKitReady: Bool = false
}
