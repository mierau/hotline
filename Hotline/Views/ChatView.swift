import SwiftUI

extension View {
  func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

struct ChatView: View {
//  @Environment(HotlineClient.self) private var hotline
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  
  @State var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  
  @Namespace var bottomID
    
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          ScrollViewReader { reader in
            LazyVStack(alignment: .leading) {
              ForEach(model.chat) { msg in
                if msg.type == .agreement {
                  VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 0) {
                      Text(msg.text)
                        .textSelection(.enabled)
                        .padding()
                        .opacity(0.75)
                      HStack {
                        Spacer()
                        Text((model.server?.name ?? "") + " Server Agreement")
                          .font(.caption)
                          .fontWeight(.medium)
                          .opacity(0.4)
                          .lineLimit(1)
                          .truncationMode(.middle)
                        Spacer()
                      }
                      .padding()
                      .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.9))
                    }
                    .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96))
                    .cornerRadius(16)
                    .frame(maxWidth: .infinity)
                  }
                  .padding()
                }
                else if msg.type == .status {
                  HStack {
                    Spacer()
                    Text(msg.text)
                      .lineLimit(1)
                      .truncationMode(.middle)
                      .opacity(0.3)
                    Spacer()
                  }
                  .padding()
                }
                else {
                  HStack(alignment: .firstTextBaseline) {
                    if let username = msg.username {
                      Text("**\(username):** \(msg.text)")
                    }
                    else {
                      Text(msg.text)
                        .textSelection(.enabled)
                    }
                    Spacer()
                  }
                  .padding()
                }
              }
              EmptyView().id(bottomID)
            }
            .onChange(of: model.chat.count) {
              withAnimation {
                reader.scrollTo(bottomID, anchor: .bottom)
              }
              print("SCROLLED TO BOTTOM")
            }
            .onAppear {
              withAnimation {
                reader.scrollTo("bottom view", anchor: .bottom)
              }
            }
          }
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
          self.endEditing()
        }
        
        Divider()
        
        HStack(alignment: .top) {
          Image(systemName: "chevron.right").opacity(0.4)
          TextField("", text: $input, axis: .vertical)
            .autocapitalization(.none)
            .lineLimit(1...5)
            .onSubmit {
              if !self.input.isEmpty {
                model.sendChat(self.input)
//                hotline.sendChat(message: self.input)
              }
              self.input = ""
            }
            .frame(maxWidth: .infinity)
          Button {
            if !self.input.isEmpty {
              model.sendChat(self.input)
//              hotline.sendChat(message: self.input)
            }
            self.input = ""
          } label: {
            Image(systemName: self.input.isEmpty ? "arrow.up.circle" : "arrow.up.circle.fill")
              .resizable()
              .scaledToFit()
              .frame(width: 24.0, height: 24.0)
              .opacity(self.input.isEmpty ? 0.4 : 1.0)
          }
        }.padding()
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.server?.name ?? "")
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            model.disconnect()
          } label: {
            Text(Image(systemName: "xmark.circle.fill"))
              .symbolRenderingMode(.hierarchical)
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
      }
      
    }
    
    
    //      GeometryReader { geometry in
    //        ScrollView(.vertical) {
    //          ScrollViewReader { scrollReader in
    //            VStack(alignment: .leading) {
    //              Spacer()
    //              List(hotline.chatMessages) { msg in
    //                HStack(alignment: .firstTextBaseline) {
    //                  Text("\(msg.username):").bold().fontDesign(.monospaced)
    //                  Text(msg.message)
    //                    .fontDesign(.monospaced)
    //                    .textSelection(.enabled)
    //                }
    //              }
    //              .padding()
    //            }
    //            //          .frame(width: geometry.size.width)
    //            .frame(minHeight: geometry.size.height)
    ////            .background(Color.red)
    //            .onAppear() {
    ////              scrollReader.scrollTo("bottomScroll", anchor: .bottom)
    //            }
    //            //          .onChange() {
    //            //            scrollReader.scrollTo(10000, anchor: .bottomTrailing)
    //            //          }
    //          }
    //        }
    //      }
    
    
  }
}

#Preview {
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineNewClient()))
}
