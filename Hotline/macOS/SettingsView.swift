import SwiftUI

struct GeneralSettingsView: View {
  @Environment(Prefs.self) private var preferences: Prefs
    
  var body: some View {
    @Bindable var preferences = preferences
    
    Form {
      TextField("Your Name", text: $preferences.username, prompt: Text("guest"))
      Toggle("Refuse private messages", isOn: $preferences.refusePrivateMessages)
      Toggle("Refuse private chat", isOn: $preferences.refusePrivateChat)
      Toggle("Automatic Response", isOn: $preferences.enableAutomaticMessage)
      if preferences.enableAutomaticMessage {
        TextField("", text: $preferences.automaticMessage, prompt: Text("Write a response message"))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
//          .fixedSize(horizontal: true, vertical: false)
          .frame(maxWidth: .infinity)
//          .lineLimit(2, reservesSpace: true)
      }
    }
    .padding(20)
    .frame(width: 350)
  }
}

struct IconSettingsView: View {
  @Environment(Prefs.self) private var preferences: Prefs
  
  @State private var hoveredUserIconID: Int = -1
  
//  @AppStorage(Prefs.userIconID) private var userIconID: Int = Prefs.defaultIconID
  
  var body: some View {
    @Bindable var preferences = preferences
    
    Form {
      ScrollViewReader { scrollProxy in
        ScrollView {
          LazyVGrid(columns: [
            GridItem(.fixed(4+64+4)),
            GridItem(.fixed(4+64+4)),
            GridItem(.fixed(4+64+4)),
            GridItem(.fixed(4+64+4)),
            GridItem(.fixed(4+64+4)),
            GridItem(.fixed(4+64+4)),
            GridItem(.fixed(4+64+4))
          ], spacing: 0) {
            ForEach(Hotline.classicIcons, id: \.self) { iconID in
              HStack {
                Image("Classic/\(iconID)")
                  .resizable()
                  .interpolation(.none)
                  .scaledToFit()
                  .frame(width: 64, height: 32)
              }
              .tag(iconID)
              .frame(width: 64, height: 64)
              .padding(4)
              .background(iconID == preferences.userIconID ? Color.accentColor : (iconID == hoveredUserIconID ? Color.accentColor.opacity(0.1) : Color(nsColor: .textBackgroundColor)))
              .clipShape(RoundedRectangle(cornerRadius: 5))
              .onTapGesture {
                preferences.userIconID = iconID
              }
              .onHover { hovered in
                if hovered {
                  self.hoveredUserIconID = iconID
                }
              }
            }
          }
          .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .onAppear {
          scrollProxy.scrollTo(preferences.userIconID, anchor: .center)
        }
        .frame(height: 415)
      }
    }
    .padding()
  }
}

struct SettingsView: View {
  private enum Tabs: Hashable {
    case general, icon
  }
  
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem {
          Label("General", systemImage: "gear")
        }
        .tag(Tabs.general)
      IconSettingsView()
        .tabItem {
          Label("Icon", systemImage: "person")
        }
        .tag(Tabs.icon)
    }
  }
}

#Preview {
  SettingsView()
}
