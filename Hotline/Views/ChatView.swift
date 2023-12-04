import SwiftUI

struct ChatView: View {
//  @Binding private var input: String
  @State var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  
  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geometry in
        ScrollView(.vertical) {
          ScrollViewReader { scrollReader in
            VStack(alignment: .leading) {
              Spacer()
              LazyVStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                  Text("bolt:").bold().fontDesign(.monospaced).frame(minWidth: 60)
                  Text("hello!").fontDesign(.monospaced).textSelection(.enabled)
                }
                ForEach(0..<50) { i in
                  HStack(alignment: .firstTextBaseline) {
                    Text("mierau:").bold().fontDesign(.monospaced)
                    Text("g'day to you. what's going on this afternoon?")
                      .fontDesign(.monospaced)
                      .textSelection(.enabled)
                  }
                }
                Text("").font(.system(size: 0)).id("bottomScroll")
              }
              .padding()
            }
            //          .frame(width: geometry.size.width)
            .frame(minHeight: geometry.size.height)
//            .background(Color.red)
            .onAppear() {
              scrollReader.scrollTo("bottomScroll", anchor: .bottom)
            }
            //          .onChange() {
            //            scrollReader.scrollTo(10000, anchor: .bottomTrailing)
            //          }
          }
        }
      }
      
      Divider()
      
      HStack(alignment: .top) {
        Image(systemName: "chevron.right")
        TextField("This is a chat topic", text: $input, axis: .vertical)
          .lineLimit(1...5)
          .onSubmit {
            //        HotlineClient.shared.sendChat(message: self.input)
            self.input = ""
          }
      }.padding()
    }
  }
}

#Preview {
  ChatView()
}
