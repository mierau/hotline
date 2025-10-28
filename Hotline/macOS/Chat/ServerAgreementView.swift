import SwiftUI

fileprivate let MAX_AGREEMENT_HEIGHT: CGFloat = 340

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
    .overlay(alignment: .bottomTrailing) {
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
              Image(systemName: "arrow.up.and.down.circle.fill")
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .frame(width: 16, height: 16)
                .foregroundColor(.primary.opacity(0.5))
            })
            .buttonStyle(.plain)
            .buttonBorderShape(.circle)
            .help("Expand Server Agreement")
            .padding([.trailing, .bottom], 16)
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

#Preview {
  ServerAgreementView(text: "Hello there and welcome to this server.")
}
