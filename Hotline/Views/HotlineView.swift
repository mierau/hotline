import SwiftUI

struct HotlineView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(HotlineTrackerClient.self) private var tracker
  
  var body: some View {
    @Bindable var config = appState
    
    NavigationStack {
      TrackerView()
    }
    .sheet(isPresented: $config.agreementPresented) {
      AgreementView(text: hotline.agreement!)
    }
  }
}

#Preview {
  HotlineView()
    .environment(HotlineClient())
    .environment(HotlineTrackerClient(tracker: HotlineTracker("hltracker.com")))
}
