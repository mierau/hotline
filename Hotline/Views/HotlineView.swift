import SwiftUI

struct HotlineView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  @State private var isTrackerVisible = true
  
  var body: some View {
    @Bindable var config = appState
    
    NavigationStack {
      ServerView()
    }
    .sheet(isPresented: $config.agreementPresented) {
      AgreementView(text: hotline.agreement!)
    }
    .sheet(isPresented: $config.trackerPresented) {
      TrackerView()
    }
  }
}

#Preview {
  HotlineView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
}
