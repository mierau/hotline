import SwiftUI
import Combine

struct IdentitySettingsView: View {
  @State private var username: String = ""
  @State private var usernameChanged: Bool = false
  @State private var hoveredUserIconID: Int = -1

  let saveTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      TextField("Nickname", text: self.$username, prompt: Text("unnamed"))

      Section("Icon") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 0)], spacing: 0) {
          ForEach(HotlineState.classicIconSet, id: \.self) { iconID in
            Image("Classic/\(iconID)")
              .resizable()
              .interpolation(.none)
              .scaledToFit()
              .frame(width: 32, height: 16)
              .help("Icon \(String(iconID))")
              .tag(iconID)
              .frame(width: 32, height: 32)
              .padding(4)
              .background(
                RoundedRectangle(cornerRadius: 5)
                  .fill(iconID == self.hoveredUserIconID ? Color.accentColor.opacity(0.1) : .clear)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 5)
                  .strokeBorder(iconID == preferences.userIconID ? Color.accentColor : .clear, lineWidth: 2)
              )
              .contentShape(Rectangle())
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
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      self.username = preferences.username
      self.usernameChanged = false
    }
    .onDisappear {
      preferences.username = self.username
      self.usernameChanged = false
    }
    .onChange(of: self.username) { oldValue, newValue in
      self.usernameChanged = true
      preferences.username = newValue
    }
    .onReceive(self.saveTimer) { _ in
      if self.usernameChanged {
        self.usernameChanged = false
        preferences.username = self.username
      }
    }
  }
}
