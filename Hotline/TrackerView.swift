import SwiftUI
import SwiftData

struct AgreementView: View {
  @Environment(\.dismiss) var dismiss
  
  let text: String
  
  var body: some View {
    Text(text)
  }
}

struct TrackerServerView: View {
  @Environment(\.dismiss) var dismiss
  
  let server: HotlineServer
  
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("🌎")
        Text(server.name!).bold().dynamicTypeSize(.xxLarge)
      }
      .padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
      Text(server.description!).opacity(0.6).dynamicTypeSize(.xLarge).padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
      Text(server.address).opacity(0.3).dynamicTypeSize(.medium)
      Spacer()
      HStack(alignment: .center) {
        Button("Connect") {
          print("WHAT", "HELLO", server.address)
          HotlineClient.shared.connect(to: server)
          dismiss()
//            client = HotlineClient(server: selectedServer)
        }
        .bold()
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
        .frame(maxWidth: .infinity)
        .foregroundColor(.black)
        .background(LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom))
        .
        overlay(
          RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(0.4)
        )
        .cornerRadius(10.0)
      }
    }
    .padding(EdgeInsets(top: 28.0, leading: 24.0, bottom: 24.0, trailing: 24.0))
    .presentationDetents([.fraction(0.4)])
    .presentationDragIndicator(.automatic)
  }
}

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @StateObject var tracker = HotlineTracker(address: "hltracker.com")
  @StateObject var client = HotlineClient.shared
  
  @State private var selectedServer: HotlineServer?
  @State private var showingAgreement = false
  @State private var showingConnectSheet = false
    
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
    .sheet(isPresented: Binding(get: { client.agreement != nil }, set: { _ in })) {
      AgreementView(text: client.agreement!)
    }
  }
}

#Preview {
  TrackerView()
  //    .modelContainer(for: Item.self, inMemory: true)
}
