import SwiftUI

/// Your automatic response on this server: whether it's on, and what's sent back to whoever sends
/// you a private message, in Markdown, styled as it's written, as a message is, as it arrives as one.
/// It starts as Settings has it, and what's changed here is for this window alone. Nothing's changed
/// until OK.
struct AutomaticResponseSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  @State private var isOn: Bool = false
  @State private var response: String = ""
  @State private var editor = MarkdownEditor()

  /// How round the reply's box is.
  private static let cornerRadius: CGFloat = 6
  /// How far in from the box's edges the reply is.
  private static let inset = NSSize(width: 8, height: 6)

  /// The reply as it's sent: without blank lines before it or space after it, as a message is.
  private var trimmed: String {
    MessageBoardPost.cleaned(self.response)
  }

  /// The server it's for, by name, so it's clear it's for this one alone.
  private var serverName: String {
    self.model.serverTitle.isEmpty ? "this server" : self.model.serverTitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Automatically reply to private messages")
            .font(.headline)
          Text("Anyone who sends you a private message on \(self.serverName) is sent this reply.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Toggle("Automatically reply to private messages", isOn: self.$isOn)
          .toggleStyle(.switch)
          .labelsHidden()
      }

      // Written ahead of time too, while it's off, to turn on later, in a box, as a text field is.
      PostEditor(text: self.$response, controller: self.editor, inset: Self.inset)
        .overlay(alignment: .topLeading) {
          if self.response.isEmpty {
            Text("Write a reply…")
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
    .frame(width: 400)
    .onAppear {
      self.isOn = self.model.automaticResponseOn
      self.response = self.model.automaticResponse
    }
    // On, with nothing to send yet, it's written next.
    .onChange(of: self.isOn) { _, isOn in
      if isOn && self.trimmed.isEmpty, let textView = self.editor.textView {
        textView.window?.makeFirstResponder(textView)
      }
    }
    .toolbar {
      // The formatting, at the bottom on the left, across from Cancel and OK, as the private message
      // sheet has it. See there.
      ToolbarItem(placement: .destructiveAction) {
        PostFormattingBar(editor: self.editor)
      }

      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("OK") {
          // Only what's changed, as telling the server tells everyone there.
          if self.isOn != self.model.automaticResponseOn || self.trimmed != self.model.automaticResponse {
            self.model.setOptions(automaticResponseOn: self.isOn, automaticResponse: self.trimmed)
          }
          self.dismiss()
        }
        // On, an empty response would send nothing.
        .disabled(self.isOn && self.trimmed.isEmpty)
      }
    }
  }
}

#Preview {
  AutomaticResponseSheet()
    .environment(HotlineState())
}
