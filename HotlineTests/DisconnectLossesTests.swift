// DisconnectLossesTests

import Testing
import AppKit
@testable import Hotline

@MainActor
struct DisconnectLossesTests {

  // MARK: - Disconnecting

  @Test func nothingToLoseNeedsNoConfirmation() {
    let hotline = HotlineState()
    #expect(hotline.disconnectLosses == nil)
  }

  @Test func blankDraftsDontCount() {
    let hotline = HotlineState()
    hotline.boardDraft = "  \n"
    hotline.newsDrafts[NewsDraft.Place(path: ["General"], parentID: 0)] = NewsDraft(title: "Hello", text: " ")
    #expect(hotline.disconnectLosses == nil)
  }

  @Test func boardPostBeingWritten() {
    let hotline = HotlineState()
    hotline.boardDraft = "Hello"
    #expect(hotline.disconnectLosses == "The board post you're writing will be lost.")
  }

  @Test func boardAndNewsPostsBeingWritten() {
    let hotline = HotlineState()
    hotline.boardDraft = "Hello"
    hotline.newsDrafts[NewsDraft.Place(path: ["General"], parentID: 0)] = NewsDraft(title: "One", text: "First")
    hotline.newsDrafts[NewsDraft.Place(path: ["General"], parentID: 7)] = NewsDraft(title: "Two", text: "Second")
    #expect(hotline.disconnectLosses == "The board post and 2 news posts you're writing will be lost.")
  }

  @Test func waitingTransfersAndPosts() {
    let hotline = HotlineState()
    hotline.boardDraft = "Hello"
    for name in ["a.zip", "b.zip"] {
      let transfer = TransferInfo(reference: 0, title: name, size: 1, serverID: hotline.id)
      hotline.queuedUploads.append((URL(fileURLWithPath: "/tmp/\(name)"), ["Uploads"], transfer))
    }
    #expect(hotline.disconnectLosses == "2 waiting transfers will be cancelled, and the board post you're writing will be lost.")
  }

  // MARK: - Quitting

  @Test func quittingCountsUnfinishedTransfersAndPosts() {
    let appState = AppState.shared
    let hotline = HotlineState()
    hotline.serverTitle = "Test Server"
    hotline.boardDraft = "Hello"
    let state = ServerState(selection: .chat)

    let running = TransferInfo(reference: 1, title: "a.zip", size: 10, serverID: hotline.id)
    let finished = TransferInfo(reference: 2, title: "b.zip", size: 10, serverID: hotline.id)
    finished.completed = true

    appState.transfers.append(contentsOf: [running, finished])
    appState.serverWindowFocused(hotline: hotline, state: state)
    defer {
      appState.transfers.removeAll { $0 === running || $0 === finished }
      appState.serverWindowClosed(state: state)
    }

    #expect(appState.quitLosses == "1 transfer is still active and will be stopped. The board post you're writing on Test Server will be lost.")
  }

  // MARK: - Window Close Guard

  /// Stands in for the delegate SwiftUI gives a window.
  private final class OriginalDelegate: NSObject, NSWindowDelegate {
    var resized = false
    var askedToClose = false

    func windowDidResize(_ notification: Notification) {
      self.resized = true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      self.askedToClose = true
      return true
    }
  }

  @Test func guardAsksBeforeClosingAndPassesEverythingElseOn() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    let original = OriginalDelegate()
    window.delegate = original

    var canClose = false
    WindowCloseGuard.guardClosing(window) { _ in canClose }
    let closeGuard = window.delegate
    #expect(closeGuard !== original)

    // While it's asking, the window stays open, and the original delegate isn't consulted.
    #expect(window.delegate?.windowShouldClose?(window) == false)
    #expect(original.askedToClose == false)

    canClose = true
    #expect(window.delegate?.windowShouldClose?(window) == true)
    #expect(original.askedToClose == true)

    // Guarding it again updates the guard, rather than wrapping it in another.
    WindowCloseGuard.guardClosing(window) { _ in false }
    #expect(window.delegate === closeGuard)
    #expect(window.delegate?.windowShouldClose?(window) == false)

    // Notifications the original delegate handles still reach it.
    NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
    #expect(original.resized)
  }
}
