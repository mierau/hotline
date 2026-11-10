import SwiftUI

/// A message for everyone on the server, in Markdown, written in a bubble as tall as it is, in
/// semibold, as chat shows a broadcast, and words alone, as a broadcast's lines are centered: bold,
/// italic, code and links, without lists, quotes or code blocks. Cancel throws away what's written,
/// and asks first, once something has been.
struct BroadcastMessageSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  @State private var editor = MarkdownEditor()
  @State private var sending: Bool = false
  @State private var confirmingDiscard = false
  /// How tall what's written is, with the room above and below it, as the editor tells it.
  @State private var written: CGFloat = 0

  /// How round the bubble is.
  private static let cornerRadius: CGFloat = 16
  /// How far in from the bubble's edges the message is, as in chat's.
  private static let inset = NSSize(width: 16, height: 10)
  /// In semibold, as chat shows it, and words alone.
  private static let layout = Markdown.Layout(
    font: .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
    lineSpacing: 3,
    imagePreviews: 0,
    blocks: false
  )
  /// As short as a line, with nothing written yet, as one line is.
  private static let shortest: CGFloat = 36
  /// As tall as about seven lines, and scrolling past them.
  private static let tallest: CGFloat = 160

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
    let room = Markdown.maximumLength - message.utf8.count

    VStack(alignment: .leading, spacing: 12) {
      // What it is, and who it's for, with the server's picture across from them, as chat has before
      // a broadcast.
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Broadcast Message")
            .font(.headline)
          Text("Sent to everyone on \(self.serverName).")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        // Half again as big as chat's, as tall as about the two lines beside it, from its biggest
        // picture, which is just as many pixels on a Retina screen.
        Image("Server Message")
          .resizable()
          .frame(width: 42, height: 30)
          .accessibilityHidden(true)
      }

      // In a bubble as tall as it is, as chat shows it, on what chat's on.
      PostEditor(text: $model.broadcastMessage, controller: self.editor, inset: Self.inset, layout: Self.layout, onFit: { self.written = $0 })
        .overlay(alignment: .topLeading) {
          if self.model.broadcastMessage.isEmpty {
            Text("Write a message…")
              .fontWeight(.semibold)
              .foregroundStyle(.tertiary)
              .padding(.horizontal, Self.inset.width)
              .padding(.vertical, Self.inset.height)
              .allowsHitTesting(false)
          }
        }
        .frame(height: min(max(self.written, Self.shortest), Self.tallest))
        .background(Color(nsColor: .textColor).opacity(0.06), in: .rect(cornerRadius: Self.cornerRadius))
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
    }
    .padding(20)
    // Wide enough for the formatting, Cancel and Broadcast, along the bottom.
    .frame(width: 440)
    .serverBackground(.content)
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
        PostCancelButton(room: room, what: "A broadcast") {
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
        .buttonStyle(.borderedProminent)
        // Return is for new lines.
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(message.isEmpty || room < 0 || self.sending)
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
