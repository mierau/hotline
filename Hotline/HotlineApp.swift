import SwiftUI
import SwiftData

@main
struct HotlineApp: App {
//  var sharedModelContainer: ModelContainer = {
//    let schema = Schema([
//      Item.self,
//    ])
//    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//    
//    do {
//      return try ModelContainer(for: schema, configurations: [modelConfiguration])
//    } catch {
//      fatalError("Could not create ModelContainer: \(error)")
//    }
//  }()
  
  @State private var appState = HotlineState()
  @State private var hotline = HotlineClient()
  
  private var model = Hotline(trackerClient: HotlineTrackerClient())
  
  var body: some Scene {
    
    WindowGroup {
      TrackerView()
        .environment(appState)
        .environment(hotline)
//        .environment(tracker)
        .environment(model)
    }
//    .modelContainer(sharedModelContainer)
  }
}
