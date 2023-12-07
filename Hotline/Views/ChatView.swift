import SwiftUI

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
                      Text("\(msg.username):").bold()
                    }
                    Text(msg.text)
                      .textSelection(.enabled)
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
        
        Divider()
        
        HStack(alignment: .top) {
          Image(systemName: "chevron.right")
          TextField("", text: $input, axis: .vertical)
            .lineLimit(1...5)
            .onSubmit {
              hotline.sendChat(message: self.input)
              //        HotlineClient.shared.sendChat(message: self.input)
              self.input = ""
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
