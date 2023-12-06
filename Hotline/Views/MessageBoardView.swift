import SwiftUI

struct MessageBoardView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  var body: some View {
//    @Bindable var config = appState
    
    ScrollView {
      LazyVStack(alignment: .leading) {
        ForEach(hotline.messageBoardMessages, id: \.self) {
          Text($0)
            .lineLimit(100)
            .padding()
          Divider()
        }
      }
    }
//    List(hotline.messageBoardMessages, id: \.self) {
//      Text($0)
//        .lineLimit(100)
//        .padding()
//      Divider()
//        .listRowSeparator(.hidden)
//        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
//    }
//    .listStyle(.plain)
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
