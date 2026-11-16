import SwiftUI

/// A server's agreement, in a sheet: as it's shown on connecting, to agree to or not, and from the
/// Server menu, to read again, with OK. It's in Markdown, as the news and the board are, with its
/// drawings in a fixed-width font, as they were drawn, previews of its pictures, from where they
/// load by themselves, and swearing and slurs hidden, as Settings can have it.
struct ServerAgreementSheet: View {
  /// Why it's shown.
  enum Purpose {
    /// On connecting, to agree to, or not, which disconnects.
    case agreeing
    /// To read again, once it's been agreed to.
    case reading
  }

  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  var purpose: Purpose = .agreeing

  var body: some View {
    ScrollView(.vertical) {
      // The agreement that's kept, which is still there as the sheet goes once it's agreed to.
      MarkdownText(text: self.model.agreement ?? "", inset: NSSize(width: 24, height: 24))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .bottomBar {
      switch self.purpose {
      case .agreeing:
        self.buttonBar
      case .reading:
        self.okBar
      }
    }
    .frame(width: 450, height: 400)
    .interactiveDismissDisabled(self.purpose == .agreeing)
    // Escape closes it too, once it's been agreed to.
    .onExitCommand {
      if self.purpose == .reading {
        self.dismiss()
      }
    }
  }

  private var buttonBar: some View {
    VStack(spacing: 0) {
      if #unavailable(macOS 26) {
        Divider()
      }

      HStack {
        Button("Disagree", role: .cancel) {
          Task {
            await self.model.disconnect()
          }
        }
        .glassButtonStyle()
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)

        Spacer()

        Button("Agree") {
          Task {
            do {
              try await self.model.sendAgree()
            } catch {
              print("HotlineState: Agree failed: \(error), disconnecting")
              await self.model.disconnect()
            }
          }
        }
        .keyboardShortcut(.defaultAction)
        .buttonBorderShape(.capsule)
        .glassProminentButtonStyle()
        .controlSize(.extraLarge)
      }
      .padding(20)
    }
  }

  /// OK, to close it, once it's been read again.
  private var okBar: some View {
    HStack {
      Spacer()

      Button("OK") {
        self.dismiss()
      }
      .keyboardShortcut(.defaultAction)
      .buttonBorderShape(.capsule)
      .buttonStyle(.glassProminent)
      .controlSize(.extraLarge)
    }
    .padding(20)
  }
}
