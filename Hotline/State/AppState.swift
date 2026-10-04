import SwiftUI

extension EnvironmentValues {
  @Entry var appState: AppState = AppState.shared
}

/// The kind of app window that's focused, so the banner toolbar can highlight its button.
enum FocusedAppWindow: Hashable {
  case servers
  case server
  case transfers
  case settings
}

extension FocusedValues {
  @Entry var focusedAppWindow: FocusedAppWindow?
}

@Observable
final class AppState {
  static let shared = AppState()

  private init() {

  }
  
  /// Called from AppDelegate to open the Transfers window when a transfer notification is clicked.
  static var openTransfersWindow: (() -> Void)?

  var bonjourState = BonjourState()

  // MARK: - Windows

  /// The kind of window that's focused, if it's one the banner toolbar has a button for.
  var focusedWindow: FocusedAppWindow? = nil

  private struct ServerWindow {
    let hotline: HotlineState
    let state: ServerState
  }

  /// Open server windows, from least to most recently focused.
  private var serverWindows: [ServerWindow] = []

  /// The server the banner toolbar shows and controls: the most recently focused server window,
  /// even while another kind of window (like Servers) is in front.
  var activeHotline: HotlineState? { self.serverWindows.last?.hotline }
  var activeServerState: ServerState? { self.serverWindows.last?.state }

  /// A server window came to the front.
  func serverWindowFocused(hotline: HotlineState, state: ServerState) {
    self.serverWindows.removeAll { $0.state === state }
    self.serverWindows.append(ServerWindow(hotline: hotline, state: state))
  }

  /// The connection with that ID, while its window's open.
  func hotline(id: UUID) -> HotlineState? {
    self.serverWindows.last { $0.hotline.id == id }?.hotline
  }

  /// A server window closed. The toolbar falls back to the server window used before it.
  func serverWindowClosed(state: ServerState) {
    self.serverWindows.removeAll { $0.state === state }
  }

  var cloudKitReady: Bool = false

  /// Pending server to open from a hotline:// URL. Set by AppDelegate,
  /// consumed by the App struct's scene observer which calls openWindow.
  var pendingServerOpen: Server? = nil

  /// Pending link from a hotline:// URL opened while the target server
  /// is already connected. ServerView observes this and navigates to the section.
  var pendingLink: Server? = nil

  // MARK: - Transfers

  /// All active transfers across all servers
  /// Transfers persist even if you disconnect from the server
  var transfers: [TransferInfo] = []
  
  @ObservationIgnored private var transferClients: [UUID: HotlineTransferClient] = [:]

  /// Track download tasks by reference number for cancellation
  @ObservationIgnored private var transferTasks: [UUID: Task<Void, Never>] = [:]
  
  /// Add a transfer to the transfer list
  @MainActor
  func addTransfer(_ transfer: TransferInfo) {
    self.transfers.append(transfer)
  }

  /// Cancel a transfer by transfer ID
  @MainActor
  func cancelTransfer(id: UUID) {
    guard let transferIndex = self.transfers.firstIndex(where: { $0.id == id }) else {
      return
    }
    
    // Cancel the task if it exists
    if let task = self.transferTasks[id] {
      task.cancel()
      self.transferTasks.removeValue(forKey: id)
    }
    
    if let client = self.transferClients[id] {
      client.cancel()
      self.transferClients.removeValue(forKey: id)
    }

    // Remove from transfers list
    self.transfers.remove(at: transferIndex)
  }
  
  /// Cancel specified transfers
  @MainActor
  func cancelTransfers(ids: [UUID]) {
    for transferID in ids {
      self.cancelTransfer(id: transferID)
    }
  }

  /// Cancel all active transfers
  @MainActor
  func cancelAllTransfers() {
    for (_, task) in self.transferTasks {
      task.cancel()
    }
    self.transferTasks.removeAll()
    
    for (_, client) in self.transferClients {
      client.cancel()
    }
    self.transferClients.removeAll()

    // Clear transfers
    self.transfers.removeAll()
  }
  
  /// Remove all completed transfers
  @MainActor
  func sweepTransfers() {
    for t in self.transfers {
      if t.done {
        self.cancelTransfer(id: t.id)
      }
    }
  }

  /// Register a transfer task
  @MainActor
  func registerTransferTask(_ task: Task<Void, Never>, transferID: UUID) {
    self.transferTasks[transferID] = task
  }
  
  @MainActor
  func registerTransferTask(_ task: Task<Void, Never>, transferID: UUID, client: HotlineTransferClient) {
    self.transferTasks[transferID] = task
    self.transferClients[transferID] = client
  }
  
  /// Unregister a download task (called on completion/failure)
  @MainActor
  func unregisterTransferTask(for transferID: UUID) {
    self.transferTasks.removeValue(forKey: transferID)
    self.transferClients.removeValue(forKey: transferID)
  }
}
