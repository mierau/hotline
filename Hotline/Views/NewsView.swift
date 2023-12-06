import SwiftUI

struct NewsView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  
  var body: some View {
//    @Bindable var config = appState
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading) {
//          ForEach(hotline.messageBoardMessages, id: \.self) {
//            Text($0)
//              .lineLimit(100)
//              .padding()
//              .textSelection(.enabled)
//            Divider()
//          }
        }
        Spacer()
      }
      .task {
        if !fetched {
          hotline.sendGetNewsCategories() {
            fetched = true
          }
        }
      }
      .refreshable {
        hotline.sendGetNewsCategories()
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
    .environment(HotlineState())
    .environment(HotlineClient())
}
