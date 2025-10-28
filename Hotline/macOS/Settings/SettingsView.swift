import SwiftUI

struct SettingsView: View {
  private enum Tabs: Hashable {
    case general, icon
  }
  
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem {
          Label("General", systemImage: "person.text.rectangle")
        }
        .tag(Tabs.general)
      IconSettingsView()
        .tabItem {
          Label("Icon", systemImage: "person")
        }
        .tag(Tabs.icon)
      SoundSettingsView()
        .tabItem {
          Label("Sound", systemImage: "speaker.wave.3")
        }
        .tag(Tabs.icon)
    }
  }
}

#Preview {
  SettingsView()
}
