import SwiftUI

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  @State private var selectedServer: HotlineServer?
  
  var body: some View {
    @Bindable var config = appState
    
    NavigationView {
      List(selection: $selectedServer) {
        ForEach(tracker.servers) { server in
          TrackerServerView(server: server)
        }
      }
      .background(Color(white: 0.96))
      .listStyle(.plain)
      .frame(maxWidth: .infinity)
      .task {
        tracker.fetch()
      }
//      .sheet(item: $selectedServer) { item in
//        TrackerServerView(server: item)
//      }
      .refreshable {
        tracker.fetch()
      }
      .navigationTitle("Tracker")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            config.dismissTracker()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.hierarchical)
              .foregroundColor(.gray)
          }
        }
        //        ToolbarItem(placement: .topBarTrailing) {
        //          Image(systemName: "camera.fill")
        //        }
        //        ToolbarItem(placement: .principal) {
        //          Text("Username")
        //        }
      }
    }
//    .interactiveDismissDisabled()
  }
}

#Preview {
  TrackerView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
  //    .modelContainer(for: Item.self, inMemory: true)
}
