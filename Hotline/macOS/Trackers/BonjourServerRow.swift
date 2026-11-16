import SwiftUI

struct BonjourServerRow: View {
  @Environment(\.openWindow) private var openWindow
  
  let server: BonjourState.BonjourServer

  /// Whether its TXT record says the port it takes TLS on, or it's been connected to over TLS.
  private var isSecure: Bool {
    guard let server = self.server.server else {
      return false
    }
    return server.tlsPort != nil || ServerTrust.shared.record(address: server.address, port: server.port) != nil
  }

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      ServerIcon(isSecure: self.isSecure)
        .frame(width: 16, height: 16, alignment: .center)
      Text(self.server.displayName).lineLimit(1).truncationMode(.tail)
      // Where a tracker's servers show their description, which Bonjour doesn't have.
      if let address = self.server.server?.displayAddress {
        Text(address)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
