// TransferQueueTests

import Testing
import Foundation
@testable import Hotline

/// A download waiting in the server's line: where it says it is, and how that's shown.
@MainActor
struct TransferQueueTests {
  @Test func placeInLine() {
    let transfer = TransferInfo(reference: 1, title: "Hotline.b27.zip", size: 6_900_000, serverID: UUID(), serverName: "The Mobius Strip")
    #expect(transfer.queueDescription == nil)

    transfer.queuePosition = 3
    #expect(transfer.queueDescription == "3rd in queue on The Mobius Strip")

    transfer.queuePosition = 22
    #expect(transfer.queueDescription == "22nd in queue on The Mobius Strip")

    transfer.queuePosition = 1
    #expect(transfer.queueDescription == "Next in queue on The Mobius Strip")

    transfer.serverName = nil
    #expect(transfer.queueDescription == "Next in queue")
  }

  @Test func theServerMovesItUpUntilItStarts() {
    let hotline = HotlineState()
    let transfer = TransferInfo(reference: 42, title: "Hotline.b27.zip", size: 6_900_000, serverID: hotline.id, serverName: "The Mobius Strip")
    let other = TransferInfo(reference: 42, title: "Elsewhere.zip", size: 1, serverID: UUID())
    AppState.shared.addTransfer(transfer)
    AppState.shared.addTransfer(other)
    defer {
      AppState.shared.transfers.removeAll { $0 == transfer || $0 == other }
    }

    hotline.handleDownloadQueued(reference: 42, position: 3)
    #expect(transfer.queuePosition == 3)
    // Only this server's, by its reference number.
    #expect(other.queuePosition == nil)

    hotline.handleDownloadQueued(reference: 42, position: 2)
    #expect(transfer.queuePosition == 2)

    // Once it's going, the server saying where it was doesn't put it back in line.
    transfer.queuePosition = nil
    transfer.progress = 0.01
    hotline.handleDownloadQueued(reference: 42, position: 1)
    #expect(transfer.queuePosition == nil)
  }
}
