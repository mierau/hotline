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

/// A setting that goes out to servers, like your name, written as a draft, which only sets it once
/// you're done: when you leave what it's written in, switch to another window, or close Settings,
/// and what's written in says so too, as a text field does as Return's pressed. Otherwise servers
/// would get every keystroke, and pass each one on to everyone.
struct DeferredSetting<Content: View>: View {
  @Binding var text: String
  /// What's set for what was written, like a name without the spaces around it.
  var cleanUp: (String) -> String = { $0 }
  /// What it's written in, with the draft, and what sets it, for it to say when you're done.
  @ViewBuilder let content: (_ draft: Binding<String>, _ commit: @escaping () -> Void) -> Content

  @State private var draft = ""
  @Environment(\.appearsActive) private var appearsActive

  var body: some View {
    self.content(self.$draft, self.commit)
      .onAppear {
        self.draft = self.text
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
      // Set some other way, it shows it, unless you're in the middle of changing it.
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

/// A text field for a setting that goes out to servers, like your name, which only sets it once
/// you're done, as `DeferredSetting` has it, or Return's pressed.
struct DeferredTextField: View {
  let title: String
  @Binding var text: String
  var prompt: Text? = nil
  /// What's set for what was typed, like a name without the spaces around it.
  var cleanUp: (String) -> String = { $0 }

  @FocusState private var focused: Bool

  var body: some View {
    DeferredSetting(text: self.$text, cleanUp: self.cleanUp) { draft, commit in
      TextField(self.title, text: draft, prompt: self.prompt)
        .focused(self.$focused)
        .onSubmit(commit)
        .onChange(of: self.focused) { _, focused in
          if !focused {
            commit()
          }
        }
    }
  }
}

/// Markdown for a setting that goes out to servers, like your automatic reply, styled as it's
/// written, as it's shown, which only sets it once you're done, as `DeferredSetting` has it. Without
/// a box of its own, across a form's row, from the left, as a text field without a label is, and
/// with the Format menu, and its keys, for its formatting.
struct DeferredMarkdownField: View {
  @Binding var text: String
  let prompt: String
  /// How many lines show, before the rest scroll.
  var lines = 3

  @State private var editor = MarkdownEditor()

  /// How tall a line is, as it's written, with the room after it.
  private static let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: Markdown.Layout.board.font)) + Markdown.Layout.board.lineSpacing

  var body: some View {
    DeferredSetting(text: self.$text, cleanUp: MessageBoardPost.cleaned) { draft, commit in
      PostEditor(text: draft, controller: self.editor, startsHere: false, inset: .zero, onEndEditing: commit)
        .overlay(alignment: .topLeading) {
          if draft.wrappedValue.isEmpty {
            Text(self.prompt)
              .foregroundStyle(.tertiary)
              .allowsHitTesting(false)
          }
        }
        .frame(height: CGFloat(self.lines) * Self.lineHeight)
    }
  }
}

#Preview {
  SettingsView()
}
