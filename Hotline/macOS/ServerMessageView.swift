import SwiftUI

struct ServerMessageView: View {
  let message: String
  
  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Image("Server Message")
        .symbolRenderingMode(.multicolor)
        .resizable()
        .scaledToFit()
        .frame(width: 20, height: 20)
      Text(message)
        .fontWeight(.semibold)
        .lineSpacing(4)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
      Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity)
#if os(iOS)
    .background(Color("Agreement Background"))
#elseif os(macOS)
    .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
#endif
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

#Preview {
  ServerMessageView(message: "This server has something important to say.")
}
