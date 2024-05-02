import SwiftUI

struct GeneralSettingsView: View {
  @Environment(Prefs.self) private var preferences: Prefs
  
  @State private var username: String = ""
  @State private var usernameChanged: Bool = false
  
  let saveTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
  var body: some View {
    @Bindable var preferences = preferences
    
    Form {
      TextField("Your Name", text: $username, prompt: Text("guest"))
      Toggle("Refuse private messages", isOn: $preferences.refusePrivateMessages)
      Toggle("Refuse private chat", isOn: $preferences.refusePrivateChat)
      Toggle("Automatic Response", isOn: $preferences.enableAutomaticMessage)
      if preferences.enableAutomaticMessage {
        TextField("", text: $preferences.automaticMessage, prompt: Text("Write a response message"))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity)
          .onSubmit(of: .text) {
            preferences.username = self.username
          }
      }
    }
    .padding(20)
    .frame(width: 350)
    .onAppear {
      self.username = preferences.username
      self.usernameChanged = false
    }
    .onDisappear {
      preferences.username = self.username
      self.usernameChanged = false
    }
    .onChange(of: username) { oldValue, newValue in
      self.usernameChanged = true
    }
    .onReceive(saveTimer) { _ in
      if self.usernameChanged {
        self.usernameChanged = false
        preferences.username = self.username
      }
    }
  }
}

struct IconSettingsView: View {
  @Environment(Prefs.self) private var preferences: Prefs
  
  @State private var hoveredUserIconID: Int = -1
  
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
            ForEach(Hotline.classicIconSet, id: \.self) { iconID in
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

struct SoundSettingsView: View {
  @Environment(Prefs.self) private var preferences: Prefs
    
  var body: some View {
    @Bindable var preferences = preferences
    Form {
      Toggle("Play Sounds for:", isOn: $preferences.playSounds)

      Toggle("Chat", isOn: $preferences.playChatSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

      Toggle("File transfer complete", isOn: $preferences.playFileTransferCompleteSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)
      Toggle("Private Message", isOn: $preferences.playPrivateMessageSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

      Toggle("Join", isOn: $preferences.playJoinSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

      Toggle("Leave", isOn: $preferences.playLeaveSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

      Toggle("Logged in", isOn: $preferences.playLoggedInSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

      Toggle("Error", isOn: $preferences.playErrorSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

      Toggle("Chat Invitation", isOn: $preferences.playChatInvitationSound)
        .disabled(!preferences.playSounds)
        .padding([.leading], 20)

    }
    .padding(20)
    .frame(width: 350)
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
