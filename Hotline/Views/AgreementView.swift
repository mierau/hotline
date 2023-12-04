import SwiftUI

struct AgreementView: View {
  @Environment(\.dismiss) var dismiss
  
  let text: String
  
  var body: some View {
    VStack(alignment: .leading) {
      ScrollView {
        VStack(alignment: .leading) {
          Text(text)
            .fontDesign(.monospaced)
            .padding()
            .dynamicTypeSize(.small)
            .textSelection(.enabled)
        }
      }
      Button("OK") {
        print("DONE")
      }
      .bold()
      .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
      .frame(maxWidth: .infinity)
    }
  }
}

#Preview {
  AgreementView(text: """
Welcome!

Take it on real one.
""")
}
