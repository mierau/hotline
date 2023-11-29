import SwiftUI
import SwiftData

struct TrackerView: View {
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @StateObject var tracker = HotlineTracker(address: "hltracker.com")
  @State private var selectedServer: HotlineServer?
  
  private var client: HotlineClient?
  
  var body: some View {
    List(selection: $selectedServer) {
      ForEach(tracker.servers) { server in
        HStack {
          Text(server.name!).bold()
          Spacer()
          HStack {
            Text("\(server.users)").font(.system(size: 12)).bold().opacity(0.3)
  //          Image(systemName: "person.fill").font(.system(size: 12)).opacity(0.3)
          }
          .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
          .background(Color(white: 0.94))
          .cornerRadius(20.0)
        }
//        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .tag(server)
  //      .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 0))
//        .onTapGesture {
//          self.selectedServer = server
//        }
      }
    }
    .listStyle(.plain)
    .frame(maxWidth: .infinity)
    .task {
      tracker.fetch()
    }
    .sheet(item: $selectedServer) { item in
      VStack(alignment: .leading) {
        Text(item.name!).bold().dynamicTypeSize(.xxLarge).padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
        Text(item.description!).opacity(0.4).dynamicTypeSize(.xLarge).padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
        Text(item.address).opacity(0.2).dynamicTypeSize(.medium)
        Spacer()
        HStack(alignment: .center) {
          Button("Connect") {
            print("WHAT", "HELLO", selectedServer!.address)
            HotlineClient.shared.connect(to: selectedServer!)
//            client = HotlineClient(server: selectedServer)
          }
          .bold()
          .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
          .frame(maxWidth: .infinity)
          .foregroundColor(.white)
          .background(Color(.black))
          .cornerRadius(8.0)
        }
      }
      .padding(EdgeInsets(top: 28.0, leading: 24.0, bottom: 24.0, trailing: 24.0))
      .presentationDetents([.fraction(0.4)])
      .presentationDragIndicator(.visible)
    }
//    List(tracker.servers) { server in
//      HStack {
//        Text(server.name!).bold()
//        Spacer()
//        HStack {
//          Text("\(server.users)").font(.system(size: 12)).bold().opacity(0.3)
////          Image(systemName: "person.fill").font(.system(size: 12)).opacity(0.3)
//        }
//        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
//        .background(Color(white: 0.94))
//        .cornerRadius(20.0)
//      }
//      .contentShape(Rectangle())
//      .listRowSeparator(.hidden)
////      .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 0))
//      .onTapGesture {
//        self.selectedServer = server
//      }
//    }
//    .listStyle(.plain)
//    .frame(maxWidth: .infinity)
//    .task {
//      tracker.fetch()
//    }
//    .sheet(item: $selectedServer) { item in
//      VStack(alignment: .leading) {
//        Text(item.name!).bold().dynamicTypeSize(.xxLarge).padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
//        Text(item.description!).opacity(0.4).dynamicTypeSize(.xLarge)
//        Spacer()
//        HStack(alignment: .center) {
//          Button("Connect") {
//            print("WHAT")
//          }
//          .bold()
//          .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
//          .frame(maxWidth: .infinity)
//          .foregroundColor(.white)
//          .background(Color(.black))
//          .cornerRadius(8.0)
//        }
//      }
//      .padding(EdgeInsets(top: 28.0, leading: 24.0, bottom: 24.0, trailing: 24.0))
//      .presentationDetents([.fraction(0.3)])
//      .presentationDragIndicator(.visible)
//    }
  }
}

#Preview {
  TrackerView()
  //    .modelContainer(for: Item.self, inMemory: true)
}
