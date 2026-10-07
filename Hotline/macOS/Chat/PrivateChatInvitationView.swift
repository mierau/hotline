import SwiftUI

/// An invitation to a private chat, at the top of your messages with whoever sent it. Not a card,
/// as their messages are, but something that's happened, centered on the page as Messages has
/// them: the icon private chats have, who it's from, under it what it's about, when the server says,
/// and buttons to turn it down or join, which goes to the chat.
struct PrivateChatInvitationView: View {
  @Environment(HotlineState.self) private var model: HotlineState

  let chat: PrivateChat
  /// Given the chat, once it's joined.
  var onJoin: (UInt32) -> Void

  @State private var joining: Bool = false

  var body: some View {
    VStack(spacing: 12) {
      Image("Section Users")
        .resizable()
        .scaledToFit()
        .frame(width: 32, height: 32)

      VStack(spacing: 2) {
        Text("\(self.chat.invitation?.name ?? "Someone") invited you to a private chat")
          .font(.headline)

        if !self.chat.subject.isBlank {
          Text(self.chat.subject)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Button("Decline") {
          Task {
            await self.model.declinePrivateChat(self.chat.id)
          }
        }

        Button("Join") {
          Task {
            self.joining = true
            await self.model.joinPrivateChat(self.chat.id)
            self.joining = false
            // Unless it was gone by then.
            if self.model.privateChat(self.chat.id)?.invitation == nil {
              self.onJoin(self.chat.id)
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(self.joining)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.top, 12)
    .padding(.bottom, 20)
  }
}
