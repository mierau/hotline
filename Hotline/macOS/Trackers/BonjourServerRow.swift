import SwiftUI

struct BonjourServerRow: View {
  @Environment(\.openWindow) private var openWindow
  
  let server: BonjourState.BonjourServer
  
  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      Image("Server")
        .resizable()
        .scaledToFit()
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
