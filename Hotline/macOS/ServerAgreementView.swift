import SwiftUI

fileprivate let MAX_AGREEMENT_HEIGHT: CGFloat = 280

struct ServerAgreementView: View {
  let text: String
  
  @State private var expandable: Bool = false
  @State private var expanded: Bool = false
  
  var body: some View {
    ScrollView(.vertical) {
      HStack(alignment: .top) {
        Spacer()
        Text(text.convertToAttributedStringWithLinks())
          .font(.system(size: 12))
          .fontDesign(.monospaced)
          .textSelection(.enabled)
          .tint(Color("Link Color"))
          .frame(maxWidth: 400)
          .padding(16)
          .background(
            GeometryReader { geometry in
              Color.clear.onAppear {
                if geometry.size.height > MAX_AGREEMENT_HEIGHT {
                  expandable = true
                }
                else {
                  expandable = false
                }
              }
            }
          )
        Spacer()
      }
    }
    .scrollIndicators(.never)
    .frame(maxWidth: .infinity, maxHeight: (expandable && expanded) ? nil : MAX_AGREEMENT_HEIGHT)
    .scrollBounceBehavior(.basedOnSize)
#if os(iOS)
    .background(Color("Agreement Background"))
#elseif os(macOS)
    .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
#endif
    .overlay(
      ZStack(alignment: .bottomTrailing) {
        Group {
          if !expandable || expanded {
            EmptyView()
          }
          else {
            Button(action: {
              withAnimation(.easeOut(duration: 0.15)) {
                expanded = true
              }
            }, label: {
              Color.black
                .opacity(0.00001)
                .frame(width: 32, height: 32)
                .overlay(
                  Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: 12, height: 12)
                    .foregroundColor(.primary.opacity(0.8))
                  , alignment: .center)
            })
            .buttonStyle(.plain)
            .help("Expand Server Agreement")
          }
        }
      }
      , alignment: .bottomTrailing)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

#Preview {
  ServerAgreementView(text: "Hello there and welcome to this server.")
}
