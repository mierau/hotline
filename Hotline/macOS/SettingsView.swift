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
  
//  @AppStorage(Prefs.userIconID) private var userIconID: Int = Prefs.defaultIconID
  
  var body: some View {
    @Bindable var preferences = preferences
    
    Form {
      ScrollView {
        LazyVGrid(columns: [
          GridItem(.flexible(minimum: 20, maximum: 50)),
          GridItem(.flexible(minimum: 20, maximum: 50)),
          GridItem(.flexible(minimum: 20, maximum: 50)),
          GridItem(.flexible(minimum: 20, maximum: 50)),
          GridItem(.flexible(minimum: 20, maximum: 50)),
          GridItem(.flexible(minimum: 20, maximum: 50)),
          GridItem(.flexible(minimum: 20, maximum: 50))
        ]) {
          ForEach(Hotline.classicIcons, id: \.self) { iconID in
            Image("Classic/\(iconID)")
              .font(.largeTitle)
              .frame(maxWidth: .infinity)
              .padding(4)
              .background(iconID == preferences.userIconID ? .blue : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 5))
              .onTapGesture {
                preferences.userIconID = iconID
              }
          }
        }
        .padding()
      }
//      for (iconID, iconText) in Hotline.defaultIconSet {
        
//        Text(iconText)
//      }
    }
    .frame(width: 350, height: 300)
    
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
          Label("Icon", systemImage: "person.crop.circle")
        }
        .tag(Tabs.icon)
    }
  }
}

#Preview {
  SettingsView()
}
