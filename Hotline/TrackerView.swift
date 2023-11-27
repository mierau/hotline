import SwiftUI
import SwiftData

struct TrackerView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var items: [Item]
  
  @StateObject var tracker = HotlineTracker(address: "hltracker.com", callback: { s in
    print("ALL DONE")
  })
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        ForEach(tracker.servers) { server in
          HStack {
            VStack(alignment: .leading) {
              Text(server.name!).bold()
              Image(systemName: "person.fill").opacity(0.3)
              Text("\(server.users)").font(.system(size: 12))
              Text(server.description!).foregroundColor(.secondary).font(.system(size: 14))
            }
            .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
            Spacer()
          }
          .background(.white)
          .cornerRadius(16)
          .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
          .frame(minWidth: 0, maxWidth: .infinity)
        }
      }
      .padding()
    }
    .background(Color(white: 0.9))
//    .toolbar {
//      ToolbarItem(placement: .navigationBarTrailing) {
//        EditButton()
//      }
//        ToolbarItem {
//          Button(action: addItem) {
//            Label("Add Item", systemImage: "plus")
//          }
//        }
//    }
    .task {
      tracker.fetch()
    }
  }
  
  private func addItem() {
    withAnimation {
      let newItem = Item(timestamp: Date())
      modelContext.insert(newItem)
    }
  }
  
  private func deleteItems(offsets: IndexSet) {
    withAnimation {
      for index in offsets {
        modelContext.delete(items[index])
      }
    }
  }
}

#Preview {
  TrackerView()
    .modelContainer(for: Item.self, inMemory: true)
}
