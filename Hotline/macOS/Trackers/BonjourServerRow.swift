import SwiftUI

struct BonjourServerRow: View {
  @Environment(\.openWindow) private var openWindow
  
  let server: BonjourState.BonjourServer

  /// Whether it's been connected to over TLS, which is all there is to go on, as Bonjour doesn't
  /// say whether a server takes TLS.
  private var isSecure: Bool {
    guard let server = self.server.server else {
      return false
    }
    return ServerTrust.shared.record(address: server.address, port: server.port) != nil
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
