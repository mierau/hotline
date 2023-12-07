import SwiftUI

extension View {
  func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

struct ChatView: View {
  @Environment(HotlineClient.self) private var hotline
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
              ForEach(hotline.chatMessages) { msg in
                if msg.type == .agreement {
                  VStack(alignment: .leading) {
                    Text(msg.text)
                      .font(.system(size: 11, weight: .regular, design: .monospaced))
                      .padding()
                      .opacity(0.75)
                      .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96))
                      .cornerRadius(16)
                  }
                  .padding()
                }
                else {
                  HStack(alignment: .firstTextBaseline) {
                    if !msg.username.isEmpty {
                      Text("**\(msg.username):** \(msg.text)")
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
              Text("").id(bottomID)
            }
            .onChange(of: hotline.chatMessages.count) {
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
                hotline.sendChat(message: self.input)
              }
              self.input = ""
            }
            .frame(maxWidth: .infinity)
          Button {
            if !self.input.isEmpty {
              hotline.sendChat(message: self.input)
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
          Text(hotline.server?.name ?? "")
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            hotline.disconnect()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.hierarchical)
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
    .environment(HotlineClient())
}
