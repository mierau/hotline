import SwiftUI

struct MessageBoardView: View {
  @Environment(Hotline.self) private var model: Hotline
//  @Environment(HotlineState.self) private var appState
//  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  var body: some View {
//    @Bindable var config = appState
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading) {
          ForEach(model.messageBoard, id: \.self) {
            Text($0)
              .lineLimit(100)
              .padding()
              .textSelection(.enabled)
            Divider()
          }
        }
        Spacer()
      }
      .task {
        if !fetched {
          let _ = await model.getMessageBoard()
//          hotline.sendGetMessageBoard() {
          fetched = true
//          }
        }
      }
      .refreshable {
        let _ = await model.getMessageBoard()
//        hotline.sendGetMessageBoard()
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
//            hotline.disconnect()
          } label: {
            Text(Image(systemName: "xmark.circle.fill"))
              .symbolRenderingMode(.hierarchical)
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            
          } label: {
            Image(systemName: "square.and.pencil")
//              .symbolRenderingMode(.hierarchical)
//              .foregroundColor(.secondary)
          }
          
        }
      }
    }
    
  }
}

#Preview {
  MessageBoardView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineNewClient()))
//    .environment(HotlineState())
//    .environment(HotlineClient())
}
