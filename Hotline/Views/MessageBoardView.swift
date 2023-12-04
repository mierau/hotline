import SwiftUI

struct MessageBoardView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  var body: some View {
//    @Bindable var config = appState
    
    VStack(alignment: .leading) {
      ScrollView {
        VStack(alignment: .leading) {
          Text(hotline.messageBoard)
            .fontDesign(.monospaced)
            .padding()
            .dynamicTypeSize(.small)
            .textSelection(.enabled)
        }
      }
    }
    .presentationDetents([.fraction(0.6)])
    .presentationDragIndicator(.visible)
    .task {
      if !fetched {
        hotline.sendGetNews() {
          fetched = true
        }
      }
    }
    .refreshable {
      hotline.sendGetNews()
    }
  }
}

#Preview {
  MessageBoardView()
    .environment(HotlineState())
    .environment(HotlineClient())
}
