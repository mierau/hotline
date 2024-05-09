import SwiftUI

struct ServerMessageView: View {
  let message: String
  
  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .symbolRenderingMode(.multicolor)
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
      Text("**\(message)**")
        .lineSpacing(4)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
    }
    .padding()
    .background(Color("Agreement Background"))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

#Preview {
  ServerMessageView(message: "This server has something important to say.")
}
