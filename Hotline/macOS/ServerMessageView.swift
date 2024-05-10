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
    }
    .padding()
    .background(Color("Agreement Background"))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

#Preview {
  ServerMessageView(message: "This server has something important to say.")
}
