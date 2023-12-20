import SwiftUI

enum FocusedField: Int, Hashable {
  case chatInput
}

struct ChatView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  
  @State var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  
  @FocusState private var focusedField: FocusedField?
  
  @Namespace var bottomID
    
  var body: some View {
    NavigationStack {
      ScrollViewReader { reader in

        VStack(alignment: .leading, spacing: 0) {
          
          // MARK: Scroll View
          GeometryReader { gm in
            ScrollView(.vertical) {
              LazyVStack(alignment: .leading) {
                ForEach(model.chat) { msg in
                  
                  // MARK: Agreement
                  if msg.type == .agreement {
                    if !msg.text.isEmpty {
                      HStack {
                        VStack(alignment: .leading) {
                          Text(msg.text)
                            .textSelection(.enabled)
                            .padding()
                            .opacity(0.75)
                        }
                        .frame(minWidth: 40, maxWidth: 400, alignment: .center)
                        .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow).cornerRadius(24))
                        .padding()
                      }
                      .frame(maxWidth: .infinity)
                      .padding()
                    }
                  }
                  // MARK: Status
                  else if msg.type == .status {
                    HStack {
                      Spacer()
                      Text(msg.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.disabled)
                        .opacity(0.3)
                      Spacer()
                    }
                    .padding()
                  }
                  else {
                    HStack(alignment: .firstTextBaseline) {
                      if let username = msg.username {
                        Text("**\(username):** \(msg.text)")
                          .textSelection(.enabled)
                      }
                      else {
                        Text(msg.text)
                          .textSelection(.enabled)
                      }
                      Spacer()
                    }
                    .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                  }
                }
                EmptyView().id(bottomID)
              }
              //          .padding(.bottom, 12)
            }
            //        .padding(.bottom, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.chat.count) {
              withAnimation {
                reader.scrollTo(bottomID, anchor: .bottom)
              }
              print("SCROLLED TO BOTTOM")
            }
            .onAppear {
              print("SCROLLED TO BOTTOM ON APPEAR")
              reader.scrollTo(bottomID, anchor: .bottom)
//              focusedField = .chatInput
            }
            .onChange(of: gm.size) {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
          }
        }
        
        // MARK: Input Divider
        Divider()
          .padding(.bottom, 0)
        
        // MARK: Input Bar
        HStack(alignment: .lastTextBaseline, spacing: 0) {
          TextField("", text: $input, axis: .vertical)
            .focused($focusedField, equals: .chatInput)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .multilineTextAlignment(.leading)
//            .frame(maxWidth: .infinity)
            .onSubmit {
              if !self.input.isEmpty {
                model.sendChat(self.input)
              }
              self.input = ""
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .overlay(alignment: .leadingLastTextBaseline) {
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
        
        
//        .overlay(alignment: .bottom) {
//          // MARK: Input Bar
//          VStack(alignment: .leading, spacing: 0) {
//            
//          }
//        }
        //      }
        
        //        VStack(alignment: .center) {
        //          Spacer()
        
        
        //            .onKeyPress(keys: [.return]) { event in
        //              print(event)
        //              guard
        //                event.phase == .down,
        //                event.key == .return else {
        //                return .ignored
        //              }
        //
        //              if event.modifiers.contains(.shift) {
        //                print("TRYING TO ADD NEW LINE")
        //                self.input += "\n"
        //                return .handled
        //              }
        //
        //              if !self.input.isEmpty {
        //                model.sendChat(self.input)
        //              }
        //              self.input = ""
        //
        //              return .handled
        //            }
        //            .onSubmit {
        //              if !self.input.isEmpty {
        //                model.sendChat(self.input)
        //              }
        //              self.input = ""
        //            }
        
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
    //    }
  }
}

#Preview {
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
