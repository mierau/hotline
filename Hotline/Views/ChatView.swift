import SwiftUI

struct ChatView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  
  var body: some View {
    VStack(spacing: 0) {
      List(hotline.chatMessages) { msg in
        if msg.username == "" {
          
        }
        HStack(alignment: .firstTextBaseline) {
          Text("\(msg.username):").bold().fontDesign(.monospaced).font(.system(size: 12))
          Text(msg.message)
            .fontDesign(.monospaced)
            .textSelection(.enabled)
            .font(.system(size: 12))
        }
      }
      .padding()
      
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
  }
}

#Preview {
  ChatView()
    .environment(HotlineClient())
}
