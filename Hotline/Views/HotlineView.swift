import SwiftUI

struct HotlineView: View {
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  @State private var isTrackerVisible = false
  
  var body: some View {
    NavigationStack {
      TrackerView()
    }
  }
}

#Preview {
  HotlineView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
}
