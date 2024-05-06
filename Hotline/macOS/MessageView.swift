import SwiftUI

struct MessageView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) private var colorScheme
  
  @State private var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  @Namespace private var bottomID
  @FocusState private var focusedField: FocusedField?
  
  var userID: UInt16
    
  var body: some View {
    ScrollViewReader { reader in
      VStack(alignment: .leading, spacing: 0) {
        
        // MARK: Scroll View
        GeometryReader { gm in
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading) {
              ForEach(model.instantMessages[userID] ?? [InstantMessage]()) { msg in
                HStack(alignment: .firstTextBaseline) {
                  if msg.direction == .outgoing {
                    Spacer()
                  }
                  
                  Text(LocalizedStringKey(msg.text))
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .tint(msg.direction == .outgoing ? Color("Outgoing Message Link") : Color("Link Color"))
                    .foregroundStyle(msg.direction == .outgoing ? Color("Outgoing Message Text") : Color("Incoming Message Text"))
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    .background(msg.direction == .outgoing ? Color("Outgoing Message Background") : Color("Incoming Message Background"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                  
                  if msg.direction == .incoming {
                    Spacer()
                  }
                }
                .padding(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
              }
              
              EmptyView().id(bottomID)
            }
            .padding()
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .defaultScrollAnchor(.bottom)
          .onChange(of: model.instantMessages[userID]?.count) {
            withAnimation(.easeOut(duration: 0.15).delay(0.25)) {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
            model.markInstantMessagesAsRead(userID: userID)
          }
          .onAppear {
            reader.scrollTo(bottomID, anchor: .bottom)
            model.markInstantMessagesAsRead(userID: userID)
          }
          .onChange(of: gm.size) {
            reader.scrollTo(bottomID, anchor: .bottom)
          }
        }
        
        // MARK: Input Divider
        Divider()
        
        // MARK: Input Bar
        HStack(alignment: .lastTextBaseline, spacing: 0) {
          let user = model.users.first(where: { $0.id == userID })
          TextField("Message \(user?.name ?? "")", text: $input, axis: .vertical)
            .focused($focusedField, equals: .chatInput)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .multilineTextAlignment(.leading)
            .onSubmit {
              if !self.input.isEmpty {
                model.sendInstantMessage(self.input, userID: self.userID)
              }
              self.input = ""
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .overlay(alignment: .leadingFirstTextBaseline) {
          Image(systemName: "chevron.right").opacity(0.4).offset(x: 16)
        }
        .onContinuousHover { phase in
          switch phase {
          case .active(_):
            NSCursor.iBeam.set()
          case .ended:
            NSCursor.arrow.set()
            break
          }
        }
        .onTapGesture {
          focusedField = .chatInput
        }
      }
      .background(Color(nsColor: .textBackgroundColor))
    }
  }
}

#Preview {
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
