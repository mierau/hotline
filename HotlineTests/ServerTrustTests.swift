// ServerTrustTests

import Testing
import Foundation
import Network
import NetSocket
import Observation
@testable import Hotline

struct ServerTrustTests {
  /// A certificate as a handshake would find it, with a key made from `seed`.
  private func certificate(_ seed: UInt8, name: String = "hotline.example.com", fromAuthority: Bool = false) -> ServerTrust.Certificate {
    ServerTrust.Certificate(key: Data(repeating: seed, count: 32), name: name, isFromAuthority: fromAuthority, isVerified: false, data: Data())
  }

  private let identity = ServerTrust.identity(address: "Hotline.Example.com", port: 5500)

  @Test func firstCertificateIsTakenAndKept() {
    let trust = ServerTrust(fileURL: nil)
    #expect(trust.record(address: "hotline.example.com", port: 5500) == nil)
    #expect(trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600) == .first)

    let record = trust.record(address: "hotline.example.com", port: 5500)
    #expect(record?.tlsPort == 5600)
    #expect(record?.key == Data(repeating: 1, count: 32))
    #expect(record?.name == "hotline.example.com")
  }

  @Test func comparingACertificateDoesntKeepIt() {
    let trust = ServerTrust(fileURL: nil)
    #expect(trust.compare(self.certificate(1), identity: self.identity) == .first)
    #expect(trust.record(address: "hotline.example.com", port: 5500) == nil)
  }

  @Test func sameCertificateIsKnown() {
    let trust = ServerTrust(fileURL: nil)
    trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)
    #expect(trust.compare(self.certificate(1), identity: self.identity) == .known)
    // Kept again on another port, it's that port it takes TLS on now.
    #expect(trust.keep(self.certificate(1), identity: self.identity, tlsPort: 6600) == .known)
    #expect(trust.record(address: "hotline.example.com", port: 5500)?.tlsPort == 6600)
  }

  @Test func renewedCertificateFromAnAuthorityIsTaken() {
    let trust = ServerTrust(fileURL: nil)
    trust.keep(self.certificate(1, fromAuthority: true), identity: self.identity, tlsPort: 5600)
    #expect(trust.compare(self.certificate(2, fromAuthority: true), identity: self.identity) == .renewed)
    // Only once the server's answered with it.
    #expect(trust.record(address: "hotline.example.com", port: 5500)?.key == Data(repeating: 1, count: 32))
    #expect(trust.keep(self.certificate(2, fromAuthority: true), identity: self.identity, tlsPort: 5600) == .renewed)
    #expect(trust.record(address: "hotline.example.com", port: 5500)?.key == Data(repeating: 2, count: 32))
  }

  @Test func otherCertificateIsTurnedDown() {
    let trust = ServerTrust(fileURL: nil)
    trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)

    // Made by anyone, or from an authority but for another name.
    #expect(trust.compare(self.certificate(2), identity: self.identity) == .changed)
    #expect(trust.compare(self.certificate(3, name: "elsewhere.example.com", fromAuthority: true), identity: self.identity) == .changed)
    // And not kept, even when asked to be, so the one it had is still the one it has.
    #expect(trust.keep(self.certificate(2), identity: self.identity, tlsPort: 5600) == .changed)
    #expect(trust.record(address: "hotline.example.com", port: 5500)?.key == Data(repeating: 1, count: 32))
  }

  @Test func trustingANewCertificateReplacesTheOldOne() {
    let trust = ServerTrust(fileURL: nil)
    trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)
    trust.trust(self.certificate(2), address: "hotline.example.com", port: 5500, tlsPort: 5600)
    #expect(trust.compare(self.certificate(2), identity: self.identity) == .known)
  }

  @Test func certificateIsKeptOnceTheServerAnswers() {
    let trust = ServerTrust(fileURL: nil)
    let handshake = ServerTrust.Handshake()
    handshake.record(self.certificate(1), .first, version: "TLS 1.3")
    #expect(!handshake.isConfirmed)
    #expect(trust.record(address: "hotline.example.com", port: 5500) == nil)

    trust.confirm(handshake, address: "Hotline.Example.com", port: 5500, tlsPort: 5600)
    #expect(handshake.isConfirmed)
    #expect(trust.record(address: "hotline.example.com", port: 5500)?.key == Data(repeating: 1, count: 32))
    #expect(trust.record(address: "hotline.example.com", port: 5500)?.tlsPort == 5600)
  }

  @Test func serversAreKeptApartByPort() {
    let trust = ServerTrust(fileURL: nil)
    trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)
    #expect(trust.record(address: "hotline.example.com", port: 6500) == nil)
  }

  @Test func forgettingAServer() {
    let trust = ServerTrust(fileURL: nil)
    trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)
    trust.forget(address: "hotline.example.com", port: 5500)
    #expect(trust.record(address: "hotline.example.com", port: 5500) == nil)
    #expect(trust.compare(self.certificate(2), identity: self.identity) == .first)
  }

  @Test func listedTLSPortsAreKeptByAddressAndPort() {
    let trust = ServerTrust(fileURL: nil)
    trust.noteListed(address: "10.0.0.1", port: 5500, tlsPort: 5600)
    #expect(trust.listedTLSPort(address: "10.0.0.1", port: 5500) == 5600)
    #expect(trust.listedTLSPort(address: "10.0.0.1", port: 6500) == nil)

    // Listed again without one, it doesn't have one.
    trust.noteListed(address: "10.0.0.1", port: 5500, tlsPort: nil)
    #expect(trust.listedTLSPort(address: "10.0.0.1", port: 5500) == nil)
    // And being listed isn't the same as having been connected to over TLS.
    #expect(trust.record(address: "10.0.0.1", port: 5500) == nil)
  }

  @Test func connectingWaitsAfterACheck() {
    let trust = ServerTrust(fileURL: nil)
    #expect(trust.waitBeforeConnecting(address: "hotline.example.com") == 0)

    trust.noteContact(address: "Hotline.Example.com")
    let wait = trust.waitBeforeConnecting(address: "hotline.example.com")
    #expect(wait > 1.5 && wait <= ServerTrust.connectionInterval)
    #expect(trust.waitBeforeConnecting(address: "elsewhere.example.com") == 0)
  }

  @Test func serversWithoutASecurePortArentTriedAgainForAWhile() {
    let trust = ServerTrust(fileURL: nil)
    let tried = Date(timeIntervalSinceReferenceDate: 800_000_000)
    #expect(!trust.hasNoSecurePort(address: "hotline.example.com", port: 5500, now: tried))

    trust.noteNoSecurePort(address: "Hotline.Example.com", port: 5500, isSure: true, now: tried)
    #expect(trust.hasNoSecurePort(address: "hotline.example.com", port: 5500, now: tried.addingTimeInterval(24 * 60 * 60)))
    #expect(!trust.hasNoSecurePort(address: "hotline.example.com", port: 6500, now: tried))
    // A week on, it's tried again.
    #expect(!trust.hasNoSecurePort(address: "hotline.example.com", port: 5500, now: tried.addingTimeInterval(ServerTrust.noSecurePortInterval + 1)))
    // And it isn't the same as having been connected to over TLS, or not.
    #expect(trust.record(address: "hotline.example.com", port: 5500) == nil)
  }

  @Test func somethingPassingIsTriedAgainButNotTwice() {
    let trust = ServerTrust(fileURL: nil)
    let tried = Date(timeIntervalSinceReferenceDate: 800_000_000)
    // Gone wrong once, which could be the network, it's tried again.
    trust.noteNoSecurePort(address: "hotline.example.com", port: 5500, isSure: false, now: tried)
    #expect(!trust.hasNoSecurePort(address: "hotline.example.com", port: 5500, now: tried.addingTimeInterval(60)))
    // Twice, it isn't.
    let again = tried.addingTimeInterval(24 * 60 * 60)
    trust.noteNoSecurePort(address: "hotline.example.com", port: 5500, isSure: false, now: again)
    #expect(trust.hasNoSecurePort(address: "hotline.example.com", port: 5500, now: again.addingTimeInterval(60)))

    // Once more, more than a week after it last went wrong, is once again.
    let later = again.addingTimeInterval(ServerTrust.noSecurePortInterval + 60)
    trust.noteNoSecurePort(address: "hotline.example.com", port: 5500, isSure: false, now: later)
    #expect(!trust.hasNoSecurePort(address: "hotline.example.com", port: 5500, now: later.addingTimeInterval(60)))
  }

  @Test func takingTLSClearsWhatWentWrongBefore() {
    let trust = ServerTrust(fileURL: nil)
    trust.noteNoSecurePort(address: "hotline.example.com", port: 5500, isSure: false)
    trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)

    // Forgotten after, so it's tried again, going wrong once more is only once.
    trust.forget(address: "hotline.example.com", port: 5500)
    trust.noteNoSecurePort(address: "hotline.example.com", port: 5500, isSure: false)
    #expect(!trust.hasNoSecurePort(address: "hotline.example.com", port: 5500))
  }

  @Test func whatWentWrongSaysWhetherItsSure() {
    func failed(_ underlying: Error) -> Error {
      HotlineClientError.connectionFailed(NetSocketError.failed(underlying: underlying))
    }
    // Nothing there, which is quick to try again.
    #expect(ServerTrust.absenceIsSure(after: failed(NWError.posix(.ECONNREFUSED)), tookTLS: false) == nil)
    // Nowhere to send it, which connecting without TLS finds too.
    #expect(ServerTrust.absenceIsSure(after: failed(NWError.posix(.EHOSTUNREACH)), tookTLS: false) == nil)
    // Nothing answered.
    #expect(ServerTrust.absenceIsSure(after: failed(NWError.posix(.ETIMEDOUT)), tookTLS: false) == true)
    // Something took TLS, and isn't a Hotline server: it said something else, or hung up.
    #expect(ServerTrust.absenceIsSure(after: HotlineClientError.connectionFailed(NSError(domain: "HotlineClient", code: -1)), tookTLS: true) == true)
    #expect(ServerTrust.absenceIsSure(after: NetSocketError.closed, tookTLS: true) == true)
    // Gone wrong partway, which could be passing: TLS broke off, or it was slow.
    #expect(ServerTrust.absenceIsSure(after: failed(NWError.posix(.ECONNRESET)), tookTLS: false) == false)
    #expect(ServerTrust.absenceIsSure(after: failed(NWError.tls(-9806)), tookTLS: false) == false)
    #expect(ServerTrust.absenceIsSure(after: HotlineClientError.connectionFailed(TaskTimeoutError()), tookTLS: true) == false)
    #expect(ServerTrust.absenceIsSure(after: HotlineClientError.connectionFailed(TaskTimeoutError()), tookTLS: false) == false)
  }

  @Test func serversWithoutASecurePortAreKeptInTheirFile() throws {
    let fileURL = URL.temporaryDirectory.appending(path: "ServerTrustTests-\(UUID().uuidString)/Encrypted Servers.json")
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    let trust = ServerTrust(fileURL: fileURL)
    trust.noteNoSecurePort(address: "hotline.example.com", port: 5500, isSure: true)
    trust.noteNoSecurePort(address: "old.example.com", port: 5500, isSure: true, now: .now.addingTimeInterval(-ServerTrust.noSecurePortInterval - 60))

    let reopened = ServerTrust(fileURL: fileURL)
    #expect(reopened.hasNoSecurePort(address: "hotline.example.com", port: 5500))
    #expect(!reopened.hasNoSecurePort(address: "old.example.com", port: 5500))
    // Apart from the servers that take TLS.
    #expect(reopened.record(address: "hotline.example.com", port: 5500) == nil)
  }

  @Test func connectionsThatNeverReachedTheServer() {
    func failed(_ underlying: Error) -> Error {
      HotlineClientError.connectionFailed(NetSocketError.failed(underlying: underlying))
    }
    // Nothing there, nothing answering in time, nowhere to send it, or no such address.
    #expect(ServerTrust.wasNeverReached(failed(NWError.posix(.ECONNREFUSED))))
    #expect(ServerTrust.wasNeverReached(failed(NWError.posix(.ETIMEDOUT))))
    #expect(ServerTrust.wasNeverReached(failed(NWError.posix(.EHOSTUNREACH))))
    #expect(ServerTrust.wasNeverReached(failed(NWError.dns(-65554))))
    // Something took it, and then didn't go on.
    #expect(!ServerTrust.wasNeverReached(failed(NWError.posix(.ECONNRESET))))
    #expect(!ServerTrust.wasNeverReached(failed(NWError.tls(-9806))))
    #expect(!ServerTrust.wasNeverReached(HotlineClientError.connectionFailed(NSError(domain: "HotlineClient", code: -1))))
  }

  /// Whether something that asked about a server, as a view showing it does, is told it changed.
  @MainActor
  private func isToldOfChange(_ trust: ServerTrust, after change: () -> Void) async throws -> Bool {
    let told = Told()
    withObservationTracking {
      _ = trust.record(address: "hotline.example.com", port: 5500)
    } onChange: {
      told.value = true
    }
    change()
    // It's told on the main thread, a moment after.
    try await Task.sleep(for: .milliseconds(50))
    return told.value
  }

  private final class Told: @unchecked Sendable {
    var value = false
  }

  @MainActor
  @Test func viewsAreToldWhenAServerIsKeptOrForgotten() async throws {
    let trust = ServerTrust(fileURL: nil)
    #expect(try await self.isToldOfChange(trust) {
      trust.keep(self.certificate(1), identity: self.identity, tlsPort: 5600)
    })
    #expect(try await self.isToldOfChange(trust) {
      trust.forget(address: "hotline.example.com", port: 5500)
    })
    #expect(try await self.isToldOfChange(trust) {
      trust.trust(self.certificate(2), address: "hotline.example.com", port: 5500, tlsPort: 5600)
    })
    // Not for the same one again, which shows the same.
    #expect(try await !self.isToldOfChange(trust) {
      trust.keep(self.certificate(2), identity: self.identity, tlsPort: 5600)
    })
  }

  @Test func recordsAreKeptInTheirFile() throws {
    let fileURL = URL.temporaryDirectory.appending(path: "ServerTrustTests-\(UUID().uuidString)/Encrypted Servers.json")
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    ServerTrust(fileURL: fileURL).keep(self.certificate(1), identity: self.identity, tlsPort: 5600)

    let reopened = ServerTrust(fileURL: fileURL)
    #expect(reopened.record(address: "hotline.example.com", port: 5500)?.tlsPort == 5600)
    #expect(reopened.compare(self.certificate(1), identity: self.identity) == .known)
  }
}
