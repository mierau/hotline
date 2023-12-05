import SwiftUI

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  @State private var selectedServer: HotlineServer?
  
  func shouldDisplayDescription(server: HotlineServer) -> Bool {
    guard let name = server.name, let desc = server.description else {
      return false
    }
    
    return desc.count > 0 && desc != name && !desc.contains(/^-+/)
  }
  
  var body: some View {
    @Bindable var config = appState
    
    List(selection: $selectedServer) {
      ForEach(tracker.servers) { server in
        NavigationLink {
          ServerView(server: server)
        } label: {
          HStack(alignment: .firstTextBaseline) {
            Text("🌎").font(.title3)
            VStack(alignment: .leading) {
              Text(server.name!).font(.title3).fontWeight(.medium)
              if shouldDisplayDescription(server: server) {
                Text(server.description!).opacity(0.6).font(.title3)
              }
            }
          }
        }
      }
    }
    .background(Color.white)
    .listStyle(.plain)
    .listRowSpacing(1)
    .frame(maxWidth: .infinity)
    .task {
      tracker.fetch()
    }
    //      .sheet(item: $selectedServer) { item in
    ////        Text("HELLO")
    //        TrackerServerView(server: item)
    //      }
    .refreshable {
      await withCheckedContinuation { continuation in
        tracker.fetch() {
          continuation.resume()
        }
      }
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
    }
    
    //    .interactiveDismissDisabled()
  }
}

#Preview {
  TrackerView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
    .environment(HotlineState())
  //    .modelContainer(for: Item.self, inMemory: true)
}
