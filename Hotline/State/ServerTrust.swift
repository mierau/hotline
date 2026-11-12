import Foundation
import Network
import Security
import CryptoKit
import NetSocket
import Observation

/// What's known of servers that take encrypted connections, which keeps connections to them
/// encrypted from then on: for each one that's been connected to over TLS, the port it takes them
/// on, and its certificate, as SSH remembers a host's key.
///
/// A server's certificate is taken on trust the first time, once the server's answered as a Hotline
/// server over it, so a certificate for something else that takes TLS on the port isn't. Hardly any Hotline server's would pass
/// a web browser's checks: trackers list servers by address, with no name to check, and servers
/// often have a certificate for another of their names, or one they made themselves. Encrypted,
/// what's said is kept from anyone listening along the way all the same. After that, it's the
/// certificate's key that's checked, so someone in between can't pass for the server. A new key is
/// taken only with a certificate for the same name from an authority browsers trust, as one renewed
/// from Let's Encrypt is.
final class ServerTrust: Observable, @unchecked Sendable {
  static let shared = ServerTrust(fileURL: URL.applicationSupportDirectory.appending(path: "Encrypted Servers.json", directoryHint: .notDirectory))

  /// A server that's been connected to over TLS.
  struct Record: Codable, Equatable, Sendable {
    /// The port it takes TLS connections on, with its file transfers on the one after.
    var tlsPort: Int
    /// The SHA-256 of its certificate's public key.
    var key: Data
    /// Who its certificate says it's for.
    var name: String
    /// When it was last connected to with this certificate.
    var date: Date
  }

  /// A server's certificate, as a TLS handshake finds it.
  struct Certificate: Sendable, Equatable {
    /// The SHA-256 of its public key.
    let key: Data
    /// Who it says it's for.
    let name: String
    /// Whether it's from an authority browsers trust, for whatever name, or false if it wasn't
    /// checked.
    let isFromAuthority: Bool
    /// Whether it's from one, for the address that was connected to, as a browser would have it,
    /// or false if it wasn't checked.
    let isVerified: Bool
    /// As it is, to show.
    let data: Data

    init(key: Data, name: String, isFromAuthority: Bool, isVerified: Bool, data: Data) {
      self.key = key
      self.name = name
      self.isFromAuthority = isFromAuthority
      self.isVerified = isVerified
      self.data = data
    }

    /// The certificate a server gave, checked with the authorities browsers trust, for the
    /// address that was connected to, unless its key is `knownKey`.
    ///
    /// - Parameter knownKey: A key that needs no more checking than that it's the same, as the one
    ///   that's kept does, which is quicker: checking can mean the system going to the network.
    init?(trust: SecTrust, host: String, unlessKey knownKey: Data? = nil) {
      guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let leaf = chain.first,
            let publicKey = SecCertificateCopyKey(leaf),
            let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
        return nil
      }
      self.key = Data(SHA256.hash(data: keyData))
      self.name = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
      self.data = SecCertificateCopyData(leaf) as Data

      guard self.key != knownKey else {
        self.isFromAuthority = false
        self.isVerified = false
        return
      }
      SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil))
      self.isFromAuthority = SecTrustEvaluateWithError(trust, nil)
      if self.isFromAuthority {
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        self.isVerified = SecTrustEvaluateWithError(trust, nil)
      }
      else {
        self.isVerified = false
      }
    }
  }

  /// How a server's certificate compares with the one it had.
  enum Outcome: Sendable, Equatable {
    /// It hadn't been connected to over TLS before, so it's taken on trust, and kept once the
    /// server answers as a Hotline server.
    case first
    /// It's the one it had.
    case known
    /// It's a new one for the same name, from an authority, which is kept in place of the old one,
    /// once the server answers.
    case renewed
    /// It isn't the one it had, which could be someone passing for the server, so it's turned down.
    case changed
  }

  /// What a TLS handshake found, for whatever made the connection: the server's certificate, how it
  /// compares with the one it had, and the version of TLS, and whether the server then answered as
  /// a Hotline server.
  final class Handshake: @unchecked Sendable {
    private let lock = NSLock()
    private var foundCertificate: Certificate?
    private var foundOutcome: Outcome?
    private var foundVersion: String?
    private var answered = false

    var certificate: Certificate? { self.lock.withLock { self.foundCertificate } }
    var outcome: Outcome? { self.lock.withLock { self.foundOutcome } }
    /// As in "TLS 1.3".
    var version: String? { self.lock.withLock { self.foundVersion } }
    /// Whether the server answered the Hotline handshake over TLS, so it's a Hotline server, and
    /// whatever goes wrong after isn't for connecting without TLS to put right.
    var isConfirmed: Bool { self.lock.withLock { self.answered } }

    func record(_ certificate: Certificate, _ outcome: Outcome?, version: String?) {
      self.lock.withLock {
        self.foundCertificate = certificate
        self.foundOutcome = outcome
        self.foundVersion = version
      }
    }

    fileprivate func confirm() {
      self.lock.withLock {
        self.answered = true
      }
    }
  }

  /// Why a server couldn't be connected to over TLS, when that isn't left to the network.
  enum Problem: Error, Equatable {
    /// It's been connected to over TLS before, but couldn't be now, so it isn't connected to
    /// without, unless that's chosen.
    case unavailable(port: Int)
    /// Its certificate isn't the one it had.
    case certificateChanged(Certificate, port: Int)
  }

  /// An encrypted connection to a server, as its window shows it.
  struct Connection: Equatable, Sendable {
    /// The port it's on, with its file transfers on the one after.
    let port: Int
    let certificate: Certificate
    /// As in "TLS 1.3".
    let version: String?
  }

  private let lock = NSLock()
  private var records: [String: Record]
  /// Where they're kept, or nil to keep them only while it's open.
  private let fileURL: URL?
  /// For views that show which servers take TLS, so they show it as soon as one's found to.
  private let registrar = ObservationRegistrar()
  /// What trying a server's usual TLS port found, when it didn't take TLS there.
  struct Absence: Codable, Equatable, Sendable {
    /// When it was tried.
    var date: Date
    /// Whether it's sure nothing that takes TLS is there, rather than that it went wrong this
    /// once, as something passing could make it.
    var isSure: Bool
  }

  /// Servers on Hotline's usual port that were tried on the usual TLS port and didn't take TLS
  /// there, so they aren't tried there again for a while, once that's sure.
  private var withoutSecurePort: [String: Absence]
  /// Where they're kept, beside the servers that take TLS, or nil to keep them only while it's open.
  private let withoutSecurePortFileURL: URL?
  /// How long a server that didn't take TLS on the usual TLS port isn't tried there again: long
  /// enough that trying costs next to nothing, and short enough to find one that's started to.
  static let noSecurePortInterval: TimeInterval = 7 * 24 * 60 * 60
  /// The TLS ports trackers list servers with, by their address and port, while it's open.
  private var listed: [String: Int] = [:]

  init(fileURL: URL?) {
    self.fileURL = fileURL
    if let fileURL, let data = try? Data(contentsOf: fileURL),
       let records = try? JSONDecoder().decode([String: Record].self, from: data) {
      self.records = records
    }
    else {
      self.records = [:]
    }

    self.withoutSecurePortFileURL = fileURL?.deletingLastPathComponent().appending(path: "Unencrypted Servers.json", directoryHint: .notDirectory)
    if let url = self.withoutSecurePortFileURL, let data = try? Data(contentsOf: url),
       let found = try? JSONDecoder().decode([String: Absence].self, from: data) {
      // Without the ones that are due to be tried again.
      self.withoutSecurePort = found.filter { Date.now.timeIntervalSince($0.value.date) < Self.noSecurePortInterval }
    }
    else {
      self.withoutSecurePort = [:]
    }
  }

  /// A server's address and port, which says which it is, however it's connected to.
  static func identity(address: String, port: Int) -> String {
    "\(address.lowercased()):\(port)"
  }

  /// What's known of a server, if it's been connected to over TLS. A view that asks is shown again
  /// when a server's kept or forgotten.
  func record(address: String, port: Int) -> Record? {
    self.registrar.access(self, keyPath: \.records)
    let identity = Self.identity(address: address, port: port)
    return self.lock.withLock { self.records[identity] }
  }

  /// Tells views that asked which servers take TLS that one's been kept or forgotten, on the main
  /// thread, where they're shown again, whatever thread it was kept on.
  private func recordsChanged() {
    DispatchQueue.main.async {
      self.registrar.withMutation(of: self, keyPath: \.records) {}
    }
  }

  /// Notes the TLS port a tracker lists a server with, or that it lists it without one, so it's
  /// tried over TLS first however it's connected to: chosen from a list, typed, or from a link.
  func noteListed(address: String, port: Int, tlsPort: Int?) {
    let identity = Self.identity(address: address, port: port)
    self.lock.withLock {
      self.listed[identity] = tlsPort
    }
  }

  /// The TLS port a tracker last listed a server with, if one did.
  func listedTLSPort(address: String, port: Int) -> Int? {
    let identity = Self.identity(address: address, port: port)
    return self.lock.withLock { self.listed[identity] }
  }

  /// Notes that a server was tried on the usual TLS port and didn't take TLS there. It isn't tried
  /// there again for `noSecurePortInterval` when that's sure, or when it's gone wrong twice in that
  /// time, which isn't something passing.
  ///
  /// - Parameter isSure: Whether it's sure nothing that takes TLS is there, as
  ///   `absenceIsSure(after:tookTLS:)` says.
  func noteNoSecurePort(address: String, port: Int, isSure: Bool, now: Date = .now) {
    let identity = Self.identity(address: address, port: port)
    self.lock.withLock {
      let wentWrongBefore = self.withoutSecurePort[identity].map { now.timeIntervalSince($0.date) < Self.noSecurePortInterval } ?? false
      self.withoutSecurePort[identity] = Absence(date: now, isSure: isSure || wentWrongBefore)
    }
    self.saveWithoutSecurePort()
  }

  /// Whether a server was tried on the usual TLS port lately, and it's sure it didn't take TLS
  /// there.
  func hasNoSecurePort(address: String, port: Int, now: Date = .now) -> Bool {
    let identity = Self.identity(address: address, port: port)
    guard let absence = self.lock.withLock({ self.withoutSecurePort[identity] }), absence.isSure else {
      return false
    }
    return now.timeIntervalSince(absence.date) < Self.noSecurePortInterval
  }

  /// What a try at the usual TLS port that didn't work says of whether the server takes TLS
  /// there: it's sure it doesn't when nothing answered at all, or what took TLS there isn't a
  /// Hotline server; not sure when it went wrong partway, as the network, or a server turning
  /// away a connection too soon after another, can make it this once; and nil when nothing was
  /// there and said so, which is quick to try again, and finds TLS as soon as it's there.
  ///
  /// - Parameter tookTLS: Whether the TLS handshake finished.
  static func absenceIsSure(after error: Error, tookTLS: Bool) -> Bool? {
    if case HotlineClientError.connectionFailed(let failure) = error {
      if case NetSocketError.failed(let underlying) = failure, case NWError.posix(let code) = underlying {
        switch code {
        case .ETIMEDOUT:
          return true
        case .ECONNREFUSED:
          return nil
        default:
          break
        }
      }
      // Slow, which isn't sure.
      if failure is TaskTimeoutError {
        return false
      }
    }
    // Nowhere to send it, or no such address, which connecting without TLS finds too.
    if Self.wasNeverReached(error) {
      return nil
    }
    return tookTLS
  }

  /// Takes a server's certificate in place of the one it had, once it's chosen to be trusted.
  func trust(_ certificate: Certificate, address: String, port: Int, tlsPort: Int) {
    let identity = Self.identity(address: address, port: port)
    self.lock.withLock {
      self.records[identity] = Record(tlsPort: tlsPort, key: certificate.key, name: certificate.name, date: .now)
    }
    self.save()
    self.recordsChanged()
  }

  /// Forgets a server was connected to over TLS, so its next connection is as if it never was.
  func forget(address: String, port: Int) {
    let identity = Self.identity(address: address, port: port)
    let removed = self.lock.withLock { self.records.removeValue(forKey: identity) != nil }
    if removed {
      self.save()
      self.recordsChanged()
    }
  }

  /// TLS for connecting to a server on its TLS port, and for its file transfers, which checks its
  /// certificate as described above, and says what it finds in `handshake`, for
  /// `confirm(_:address:port:tlsPort:)` to keep once the server's answered as a Hotline server.
  ///
  /// - Parameters:
  ///   - address: The server's address, as it's connected to.
  ///   - port: Its port, which says which server it is, rather than the port for TLS.
  ///   - tlsPort: The port for TLS.
  func policy(address: String, port: Int, tlsPort: Int, handshake: Handshake? = nil) -> TLSPolicy {
    let identity = Self.identity(address: address, port: port)
    return .enabled { options in
      Self.requireModernTLS(options)
      sec_protocol_options_set_verify_block(options.securityProtocolOptions, { metadata, trust, complete in
        let trust = sec_trust_copy_ref(trust).takeRetainedValue()
        // A file transfer's certificate isn't shown, so if it's the one that's kept, that's all
        // there is to check. What an authority says of it is for one that's changed, which could
        // be renewed, and to show the connection's.
        let keptKey = handshake == nil ? self.lock.withLock { self.records[identity]?.key } : nil
        guard let certificate = Certificate(trust: trust, host: address, unlessKey: keptKey) else {
          complete(false)
          return
        }
        let outcome = self.compare(certificate, identity: identity)
        let version = Self.versionName(sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata))
        handshake?.record(certificate, outcome, version: version)
        complete(outcome != .changed)
      }, DispatchQueue.global(qos: .userInitiated))
    }
  }

  /// TLS that takes any certificate, without keeping it, to look at a server's, and say what it is
  /// in `handshake`, as checking whether it takes secure connections does.
  static func inspection(address: String, handshake: Handshake) -> TLSPolicy {
    .enabled { options in
      Self.requireModernTLS(options)
      sec_protocol_options_set_verify_block(options.securityProtocolOptions, { metadata, trust, complete in
        let trust = sec_trust_copy_ref(trust).takeRetainedValue()
        if let certificate = Certificate(trust: trust, host: address) {
          handshake.record(certificate, nil, version: Self.versionName(sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata)))
        }
        complete(true)
      }, DispatchQueue.global(qos: .userInitiated))
    }
  }

  /// TLS 1.2 or later, and nothing older, which servers that take TLS, like Mobius, all do.
  private static func requireModernTLS(_ options: NWProtocolTLS.Options) {
    sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
  }

  // MARK: - Checking

  /// Whether a server takes secure connections, as checking it found.
  enum CheckResult: Equatable, Sendable {
    /// It does, on the port, with a certificate for the name.
    case found(port: Int, name: String)
    /// It doesn't, on any of the ports.
    case notFound(ports: [Int])
    /// There's no server at its address.
    case unknownAddress
  }

  /// How long a connection to an address takes up, before Mobius takes another from the same one,
  /// on any of its ports.
  static let connectionInterval: TimeInterval = 2.1

  /// When each server's address was last connected to, to check it or log in.
  private var contacted: [String: Date] = [:]

  /// Checks whether a server takes secure connections, on each of the ports in turn, until it
  /// finds one: a TLS connection, with the handshake every connection starts with in it, without
  /// logging in. Its certificate isn't kept: that's for when it's connected to.
  func checkSecureConnection(address: String, ports: [Int]) async -> CheckResult {
    var tried: [Int] = []
    for port in ports {
      guard !Task.isCancelled else {
        break
      }
      guard let tlsPort = HotlinePorts.connectionPort(port) else {
        continue
      }
      // Each check after one the server took waits its turn, as connecting does.
      let wait = self.waitBeforeConnecting(address: address)
      if wait > 0 {
        try? await Task.sleep(for: .seconds(wait))
      }

      let handshake = Handshake()
      do {
        try await HotlineClient.check(host: address, port: tlsPort, tls: Self.inspection(address: address, handshake: handshake), timeout: 5)
        self.noteContact(address: address)
        return .found(port: port, name: handshake.certificate?.name ?? "")
      }
      catch {
        print("ServerTrust: No secure connection to \(address) on port \(port): \(error)")
        if Self.wasNotFound(error) {
          return .unknownAddress
        }
        if !Self.wasNeverReached(error) {
          self.noteContact(address: address)
        }
        tried.append(port)
      }
    }
    return .notFound(ports: tried)
  }

  /// Notes that a server's address was just connected to, which Mobius counts against the next
  /// connection from here.
  func noteContact(address: String) {
    self.lock.withLock {
      self.contacted[address.lowercased()] = .now
    }
  }

  /// How long to wait to connect to a server's address, so it's been `connectionInterval` since it
  /// was last connected to, or nothing.
  func waitBeforeConnecting(address: String) -> TimeInterval {
    let last = self.lock.withLock { self.contacted[address.lowercased()] }
    guard let last else {
      return 0
    }
    return max(0, Self.connectionInterval - Date.now.timeIntervalSince(last))
  }

  /// Whether the connection never reached anything to take it: nothing was there and said so,
  /// nothing answered in time, as when what's in the way drops it, or the address couldn't be
  /// looked up or reached. Either way, the server never saw it.
  static func wasNeverReached(_ error: Error) -> Bool {
    guard case HotlineClientError.connectionFailed(let failure) = error,
          case NetSocketError.failed(let underlying) = failure else {
      return false
    }
    switch underlying {
    case NWError.posix(let code):
      return [.ECONNREFUSED, .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN].contains(code)
    case NWError.dns(_):
      return true
    default:
      return false
    }
  }

  /// Whether the address couldn't be looked up.
  static func wasNotFound(_ error: Error) -> Bool {
    guard case HotlineClientError.connectionFailed(let failure) = error,
          case NetSocketError.failed(let underlying) = failure,
          case NWError.dns(_) = underlying else {
      return false
    }
    return true
  }

  // MARK: - Records

  /// How a server's certificate compares with the one it had, without keeping it.
  func compare(_ certificate: Certificate, identity: String) -> Outcome {
    self.lock.withLock {
      Self.outcome(of: certificate, against: self.records[identity])
    }
  }

  /// Keeps a server's certificate, and the port it takes TLS on, when it's the first, renewed, or
  /// the one it had, and not when it's changed, which only trusting it takes.
  @discardableResult
  func keep(_ certificate: Certificate, identity: String, tlsPort: Int) -> Outcome {
    let (outcome, hadAbsence): (Outcome, Bool) = self.lock.withLock {
      let outcome = Self.outcome(of: certificate, against: self.records[identity])
      if outcome != .changed {
        self.records[identity] = Record(tlsPort: tlsPort, key: certificate.key, name: certificate.name, date: .now)
      }
      // It's taken TLS, so whatever went wrong trying it before was passing.
      let hadAbsence = self.withoutSecurePort.removeValue(forKey: identity) != nil
      return (outcome, hadAbsence)
    }
    if outcome != .changed {
      self.save()
    }
    if hadAbsence {
      self.saveWithoutSecurePort()
    }
    // A server's taken TLS for the first time.
    if outcome == .first {
      self.recordsChanged()
    }
    return outcome
  }

  /// Notes that a server answered as a Hotline server over TLS, once it has, and keeps the
  /// certificate it gave, so it's connected to over TLS from then on.
  func confirm(_ handshake: Handshake, address: String, port: Int, tlsPort: Int) {
    handshake.confirm()
    if let certificate = handshake.certificate {
      self.keep(certificate, identity: Self.identity(address: address, port: port), tlsPort: tlsPort)
    }
  }

  private static func outcome(of certificate: Certificate, against record: Record?) -> Outcome {
    guard let record else {
      return .first
    }
    if record.key == certificate.key {
      return .known
    }
    if certificate.isFromAuthority && !certificate.name.isEmpty && certificate.name == record.name {
      return .renewed
    }
    return .changed
  }

  private func save() {
    guard let fileURL = self.fileURL else {
      return
    }
    Self.write(self.lock.withLock { self.records }, to: fileURL)
  }

  private func saveWithoutSecurePort() {
    guard let url = self.withoutSecurePortFileURL else {
      return
    }
    Self.write(self.lock.withLock { self.withoutSecurePort }, to: url)
  }

  private static func write(_ value: some Encodable, to fileURL: URL) {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }
    catch {
      print("ServerTrust: Couldn't save \(fileURL.lastPathComponent): \(error)")
    }
  }

  private static func versionName(_ version: tls_protocol_version_t) -> String? {
    switch version {
    case .TLSv13: "TLS 1.3"
    case .TLSv12: "TLS 1.2"
    default: nil
    }
  }
}
