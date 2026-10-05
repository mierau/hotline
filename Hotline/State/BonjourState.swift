import Foundation
import Network
import dnssd

@Observable
class BonjourState {
  var isExpanded: Bool = false
  var isBrowsing: Bool = false
  var discoveredServers: [BonjourServer] = []
  
  private var browser: NWBrowser?
  private var resolutionTasks: [UUID: Task<Void, Never>] = [:]
  
  struct BonjourServer: Identifiable, Hashable {
    let id = UUID()
    let serviceName: String
    let name: String
    let address: String?
    let port: UInt16?
    let txtRecords: [String: String]
    
    var displayName: String {
      // Use the advertised name, fall back to service name
      self.name.isEmpty ? self.serviceName : self.name
    }
    
    var server: Server? {
      guard let address = self.address,
            let port = self.port else {
        return nil
      }
      return Server(name: self.displayName, description: nil, address: address, port: Int(port))
    }
    
    static func == (lhs: BonjourServer, rhs: BonjourServer) -> Bool {
      lhs.address == rhs.address && lhs.port == rhs.port
    }
    
    func hash(into hasher: inout Hasher) {
      hasher.combine(self.id)
    }
  }
  
  func startBrowsing() {
    guard !self.isBrowsing else {
      return
    }
    
    self.isBrowsing = true
    self.discoveredServers.removeAll()
    
    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    
    self.browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_hotline._tcp", domain: nil), using: parameters)
    
    self.browser?.stateUpdateHandler = { [weak self] newState in
      Task { @MainActor in
        switch newState {
        case .ready:
          print("BonjourState: Browser ready")
        case .failed(let error):
          print("BonjourState: Browser failed: \(error)")
          self?.stopBrowsing()
        case .cancelled:
          print("BonjourState: Browser cancelled")
          self?.isBrowsing = false
        default:
          break
        }
      }
    }
    
    self.browser?.browseResultsChangedHandler = { [weak self] results, changes in
      guard let self = self else {
        return
      }
      
      Task { @MainActor in
        print("BonjourState: Browse results changed, found \(results.count) services")
        
        // Handle removed services
        for change in changes {
          if case .removed(let result) = change {
            if case .service(let name, _, _, _) = result.endpoint {
              self.discoveredServers.removeAll { $0.serviceName == name }
              print("BonjourState: Removed service: \(name)")
            }
          }
        }
        
        // Handle added/updated services
        for change in changes {
          if case .added(let result) = change, case .service = result.endpoint {
            await self.resolveService(result)
          } else if case .changed(_, let new, _) = change, case .service = new.endpoint {
            await self.resolveService(new)
          }
        }
      }
    }
    
    self.browser?.start(queue: .main)
  }
  
  /// Finds out where a service is, its host name and port, and adds it to the list or updates it.
  ///
  /// This asks Bonjour rather than connecting to the server to see where it ends up, because a
  /// server can count that connection against how often one address may connect, and turn away the
  /// real one that follows.
  @MainActor
  private func resolveService(_ result: NWBrowser.Result) async {
    guard case .service(let name, let type, let domain, let interface) = result.endpoint else {
      return
    }

    guard let (host, port) = await BonjourResolution.resolve(name: name, type: type, domain: domain, interface: interface) else {
      print("BonjourState: Failed to resolve \(name)")
      return
    }

    // Parse TXT records
    var txtRecords: [String: String] = [:]
    if case .bonjour(let txtRecord) = result.metadata {
      for (key, value) in txtRecord.dictionary {
        txtRecords[key] = value
      }
    }

    let server = BonjourServer(
      serviceName: name,
      name: name,
      address: host,
      port: port,
      txtRecords: txtRecords
    )

    // Update or add server
    if let index = self.discoveredServers.firstIndex(where: { $0.serviceName == name }) {
      self.discoveredServers[index] = server
    } else {
      self.discoveredServers.append(server)
    }
  }
  
  func stopBrowsing() {
    guard self.isBrowsing else {
      return
    }
    
    print("BonjourState: Stopping Bonjour browsing")
    
    // Cancel all resolution tasks
    for (_, task) in self.resolutionTasks {
      task.cancel()
    }
    self.resolutionTasks.removeAll()
    
    self.browser?.cancel()
    self.browser = nil
    self.isBrowsing = false
    self.discoveredServers.removeAll()
  }
}

/// One question to Bonjour about where a service is: its host name, like micro.local, and port.
/// Everything happens on the main queue.
private final class BonjourResolution {
  typealias Answer = (host: String, port: UInt16)

  private var reference: DNSServiceRef?
  private var continuation: CheckedContinuation<Answer?, Never>?

  /// The service's host name and port, or nil if Bonjour can't say within a few seconds.
  @MainActor
  static func resolve(name: String, type: String, domain: String, interface: NWInterface?) async -> Answer? {
    await withCheckedContinuation { continuation in
      BonjourResolution().start(name: name, type: type, domain: domain, interfaceIndex: UInt32(interface?.index ?? 0), continuation: continuation)
    }
  }

  private func start(name: String, type: String, domain: String, interfaceIndex: UInt32, continuation: CheckedContinuation<Answer?, Never>) {
    self.continuation = continuation

    // Kept alive until it finishes, and handed to the reply, which can't capture anything.
    let context = Unmanaged.passRetained(self).toOpaque()
    let error = DNSServiceResolve(&self.reference, 0, interfaceIndex, name, type, domain, { _, _, _, error, _, hostTarget, port, _, _, context in
      guard let context else {
        return
      }
      let resolution = Unmanaged<BonjourResolution>.fromOpaque(context).takeUnretainedValue()
      guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let hostTarget else {
        resolution.finish(nil)
        return
      }
      // A fully qualified name, with a dot on the end, and the port in network byte order.
      var host = String(cString: hostTarget)
      if host.hasSuffix(".") {
        host.removeLast()
      }
      resolution.finish((host, UInt16(bigEndian: port)))
    }, context)

    guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let reference = self.reference else {
      self.finish(nil)
      return
    }
    DNSServiceSetDispatchQueue(reference, .main)

    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
      self.finish(nil)
    }
  }

  /// Answers once, with the first reply or nothing, and stops asking.
  private func finish(_ answer: Answer?) {
    guard let continuation = self.continuation else {
      return
    }
    self.continuation = nil
    if let reference = self.reference {
      DNSServiceRefDeallocate(reference)
      self.reference = nil
    }
    continuation.resume(returning: answer)
    Unmanaged.passUnretained(self).release()
  }
}
