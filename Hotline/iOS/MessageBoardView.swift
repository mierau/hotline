import SwiftUI

struct MessageBoardView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var initialLoadComplete = false
  @State private var fetched = false
  
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
        if !initialLoadComplete {
          let _ = await model.getMessageBoard()
          initialLoadComplete = true
        }
      }
      .overlay {
        if !initialLoadComplete {
          VStack {
            ProgressView()
              .controlSize(.large)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .refreshable {
        let _ = await model.getMessageBoard()
        initialLoadComplete = true
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.serverTitle)
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
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            
          } label: {
            Image(systemName: "square.and.pencil")
          }
        }
      }
    }
    
  }
}

#Preview {
  MessageBoardView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
