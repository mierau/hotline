import SwiftUI

/// A message for everyone on the server, in Markdown, styled as it's written, but words alone, as a
/// broadcast is shown centered: bold, italic, code and links, without lists, quotes or code blocks.
/// Cancel throws away what's written, and asks first, once something has been.
struct BroadcastMessageSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  @State private var editor = MarkdownEditor()
  @State private var sending: Bool = false
  @State private var confirmingDiscard = false

  /// How round the message's box is.
  private static let cornerRadius: CGFloat = 6
  /// How far in from the box's edges the message is.
  private static let inset = NSSize(width: 8, height: 6)
  /// As it's written: words alone, as it's shown.
  private static let layout = Markdown.Layout(imagePreviews: 0, blocks: false)

  /// The message as it's sent: without blank lines before it or space after it, as a post is.
  private var message: String {
    MessageBoardPost.cleaned(self.model.broadcastMessage)
  }

  /// The server it's for, by name.
  private var serverName: String {
    self.model.serverTitle.isEmpty ? "this server" : self.model.serverTitle
  }

  var body: some View {
    @Bindable var model = self.model
    let message = self.message

    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Broadcast Message")
          .font(.headline)
        Text("Sent to everyone on \(self.serverName).")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      // In a box, as a text field is, as the Auto-Reply sheet has it.
      PostEditor(text: $model.broadcastMessage, controller: self.editor, inset: Self.inset, layout: Self.layout)
        .overlay(alignment: .topLeading) {
          if self.model.broadcastMessage.isEmpty {
            Text("Write a message…")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, Self.inset.width)
              .padding(.vertical, Self.inset.height)
              .allowsHitTesting(false)
          }
        }
        .frame(height: 96)
        .serverBackground(.post)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: Self.cornerRadius)
            .strokeBorder(.separator)
        }
    }
    .padding(20)
    // Wide enough for the formatting, Cancel and Broadcast, along the bottom.
    .frame(width: 440)
    .discardConfirmation("Discard this message?", isPresented: self.$confirmingDiscard, discard: self.discard)
    .toolbar {
      if self.sending {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }

      // The formatting, at the bottom on the left, across from Cancel and Broadcast, as the private
      // message sheet has it. See there.
      ToolbarItem(placement: .destructiveAction) {
        PostFormattingBar(editor: self.editor)
      }

      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          if self.model.broadcastMessage.isWritten() {
            self.confirmingDiscard = true
          }
          else {
            self.discard()
          }
        }
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("Broadcast") {
          self.send(message)
        }
        // Return is for new lines.
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(message.isEmpty || message.utf8.count > Markdown.maximumLength || self.sending)
        .help("Broadcast Message (⌘↩)")
      }
    }
  }

  /// Throws away what's written, and puts the sheet away.
  private func discard() {
    self.model.broadcastMessage = ""
    self.dismiss()
  }

  /// Sends it, and once it's gone, puts the sheet away. If it doesn't go out, the sheet stays open,
  /// with it, to try again.
  private func send(_ message: String) {
    Task {
      self.sending = true
      defer { self.sending = false }

      do {
        try await self.model.sendBroadcast(message)
        self.model.broadcastMessage = ""
        self.dismiss()
      }
      catch {
        // Still here, as above.
      }
    }
  }
}

#Preview {
  BroadcastMessageSheet()
    .environment(HotlineState())
}
