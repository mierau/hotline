import SwiftUI

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  //  @StateObject var tracker = HotlineTrackerClient(address: "hltracker.com")
  //  @StateObject var client = HotlineClient.shared
  
  @State private var selectedServer: HotlineServer?
  @State private var showingAgreement = false
  @State private var showingConnectSheet = false
  
  //  @Bindable var trackerTest = tracker
  
  var body: some View {
    List(selection: $selectedServer) {
      ForEach(tracker.servers) { server in
        HStack {
          Text("🌎")
          Text(server.name!).bold()
          Spacer()
          Text("\(server.users)").opacity(0.6)
        }
        .listRowBackground(Color(white: 0.96))
        .listRowInsets(EdgeInsets(top: 0, leading: 16.0, bottom: 0, trailing: 16.0))
        .listRowSeparator(.visible, edges: VerticalEdge.Set.all)
        .listRowSeparatorTint(Color(white: 1.0))
        .tag(server)
      }
    }
    .background(Color(white: 0.96))
    .listStyle(.plain)
    .frame(maxWidth: .infinity)
    .task {
      tracker.fetch()
    }
    .sheet(item: $selectedServer) { item in
      TrackerServerView(server: item)
    }
    .sheet(isPresented: Binding(get: { hotline.agreement != nil }, set: { _ in })) {
      AgreementView(text: hotline.agreement!)
    }
    .navigationTitle("Tracker")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Image(systemName: "gearshape.fill")
      }
      //        ToolbarItem(placement: .topBarTrailing) {
      //          Image(systemName: "camera.fill")
      //        }
      //        ToolbarItem(placement: .principal) {
      //          Text("Username")
      //        }
    }
    .refreshable {
      tracker.fetch()
    }
    .interactiveDismissDisabled()
  }
}

#Preview {
  TrackerView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
  //    .modelContainer(for: Item.self, inMemory: true)
}
