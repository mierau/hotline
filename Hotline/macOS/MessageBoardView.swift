import SwiftUI

struct MessageBoardView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var initialLoadComplete = false
  
  var body: some View {
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
        if !model.messageBoardLoaded {
          let _ = await model.getMessageBoard()
//          self.initialLoadComplete = true
          print("INITIAL LOAD?")
        }
      }
      .overlay {
        if !model.messageBoardLoaded {
          VStack {
            ProgressView()
              .controlSize(.large)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .background(Color(nsColor: .textBackgroundColor))
    }
    .toolbar {
      ToolbarItem(placement:.primaryAction) {
        Button {
          
        } label: {
          Image(systemName: "square.and.pencil")
        }
      }
    }
  }
}

#Preview {
  MessageBoardView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
