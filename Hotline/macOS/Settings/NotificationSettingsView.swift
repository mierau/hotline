import SwiftUI

struct NotificationSettingsView: View {
  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      // First, as it's the one that shows while you're using Hotline, and below all the
      // notifications it'd be scrolled out of sight.
      Section("Dock") {
        Toggle(isOn: $preferences.showUnreadDockBadge) {
          Text("Show Unread Count")
          Text("Unread message and board post count.")
        }
      }

      // Notifications only come while you're in another app.
      Section {
        Toggle(isOn: $preferences.showChatNotifications) {
          Text("Chat Messages")
          Text("Every unread message in public chat.")
        }
        Toggle(isOn: $preferences.showMentionNotifications) {
          Text("Mentions")
          Text("Chat messages that mention you.")
        }
        Toggle(isOn: $preferences.showWatchWordNotifications) {
          Text("Highlighted Words")
          Text("Chat messages with words you've highlighted.")
        }
      } header: {
        Text("Chat")
      }

      Section("Private") {
        Toggle("Private Messages", isOn: $preferences.showPrivateMessageNotifications)
        Toggle(isOn: $preferences.showPrivateChatNotifications) {
          Text("Private Chats")
          Text("Messages from private chats and invitations.")
        }
      }

      Section("Server") {
        Toggle(isOn: $preferences.showBroadcastNotifications) {
          Text("Broadcasts")
          Text("Important messages broadcast to everyone on a server.")
        }
        Toggle(isOn: $preferences.showBoardPostNotifications) {
          Text("Message Board")
          Text("New posts on a server's message board.")
        }
        Toggle(isOn: $preferences.showDisconnectNotifications) {
          Text("Disconnections")
          Text("When an administrator disconnects you.")
        }
        Toggle(isOn: $preferences.showTransferNotifications) {
          Text("File Transfers")
          Text("When a download or upload completes or fails.")
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

#Preview {
  NotificationSettingsView()
}
