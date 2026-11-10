import SwiftUI

/// Your automatic response on this server: whether it's on, and what's sent back to whoever sends
/// you a private message. It starts as Settings has it, and what's changed here is for this window
/// alone. Nothing's changed until OK.
struct AutomaticResponseSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  @State private var isOn: Bool = false
  @State private var response: String = ""
  @FocusState private var responseFocused: Bool

  private var trimmed: String {
    self.response.trimmingCharacters(in: .whitespacesAndNewlines)
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

      // Written ahead of time too, while it's off, to turn on later.
      TextField("Write a reply...", text: self.$response, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(4, reservesSpace: true)
        .focused(self.$responseFocused)
    }
    .padding(20)
    .frame(width: 400)
    .onAppear {
      self.isOn = self.model.automaticResponseOn
      self.response = self.model.automaticResponse
    }
    // On, with nothing to send yet, it's written next.
    .onChange(of: self.isOn) { _, isOn in
      if isOn && self.trimmed.isEmpty {
        self.responseFocused = true
      }
    }
    .toolbar {
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
