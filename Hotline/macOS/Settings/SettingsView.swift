import SwiftUI

struct SettingsView: View {
  private enum Section: Hashable {
    case identity, general, chat, sound, notifications
  }

  @State private var selection: Section = .identity
  private var preferences = Prefs.shared

  var body: some View {
    NavigationSplitView {
      List(selection: self.$selection) {
        Label {
          Text(self.preferences.username.isEmpty ? "Identity" : self.preferences.username)
        } icon: {
          Image("Classic/\(self.preferences.userIconID)")
            .interpolation(.none)
        }
        .tag(Section.identity)

        Divider()

        Label {
          Text("General")
        } icon: {
          Image("Settings/General")
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .tag(Section.general)
        Label {
          Text("Chat")
        } icon: {
          Image("Settings/Chat")
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .tag(Section.chat)
        Label {
          Text("Sounds")
        } icon: {
          Image("Settings/Sounds")
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .tag(Section.sound)
        Label {
          Text("Notifications")
        } icon: {
          Image("Settings/Notifications")
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .tag(Section.notifications)
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(180)
    } detail: {
      switch self.selection {
      case .identity:
        IdentitySettingsView()
      case .general:
        GeneralSettingsView()
      case .chat:
        ChatSettingsView()
      case .sound:
        SoundSettingsView()
      case .notifications:
        NotificationSettingsView()
      }
    }
  }
}

/// A text field for a setting that goes out to servers, like your name, which only sets it once
/// you're done: when you press Return, leave the field, switch to another window, or close
/// Settings. Otherwise servers would get every keystroke, and pass each one on to everyone.
struct DeferredTextField: View {
  let title: String
  @Binding var text: String
  var prompt: Text? = nil
  /// What's set for what was typed, like a name without the spaces around it.
  var cleanUp: (String) -> String = { $0 }

  @State private var draft = ""
  @FocusState private var focused: Bool
  @Environment(\.appearsActive) private var appearsActive

  var body: some View {
    TextField(self.title, text: self.$draft, prompt: self.prompt)
      .focused(self.$focused)
      .onAppear {
        self.draft = self.text
      }
      .onSubmit(self.commit)
      .onChange(of: self.focused) { _, focused in
        if !focused {
          self.commit()
        }
      }
      .onChange(of: self.appearsActive) { _, active in
        if !active {
          self.commit()
        }
      }
      .onDisappear(perform: self.commit)
      // Quitting doesn't close Settings first.
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
        self.commit()
      }
      // Set some other way, the field shows it, unless you're in the middle of changing it.
      .onChange(of: self.text) { old, new in
        if self.cleanUp(self.draft) == old {
          self.draft = new
        }
      }
  }

  private func commit() {
    let value = self.cleanUp(self.draft)
    if value != self.text {
      self.text = value
    }
  }
}

#Preview {
  SettingsView()
}
