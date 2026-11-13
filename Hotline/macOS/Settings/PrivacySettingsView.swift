import SwiftUI

/// What others can see of you, and who can reach you: which sites see your address as pictures load
/// from them, what you'd rather not see, who can message you, and which servers are only connected to
/// securely.
struct PrivacySettingsView: View {
  /// How the Mac has sensitive content shown, read again as the app comes back from System Settings.
  @State private var intervention = SensitiveContent.currentIntervention()
  @State private var showsEncryptedServers = false

  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      // Who can reach you, first.
      Section("Private Messages") {
        Toggle("Refuse private chat invites", isOn: $preferences.refusePrivateChat)
        Toggle("Refuse private messages", isOn: $preferences.refusePrivateMessages)
      }

      Section("Image Previews") {
        Picker(selection: $preferences.imagePreviews) {
          ForEach(ImagePreviews.allCases) { previews in
            Text(previews.title)
              .tag(previews)
          }
        } label: {
          Text("Show previews")
          if let explanation = preferences.imagePreviews.explanation {
            Text(explanation)
          }
        }
      }

      Section("Sensitive Content") {
        // Until it's chosen, on for a child, as Communication Safety is.
        Toggle("Hide offensive words", isOn: Binding(
          get: { HiddenWords.isOn },
          set: { Prefs.shared.hideOffensiveWords = $0 }
        ))

        // The Mac's own setting, which is what blurs them, so it's changed there.
        LabeledContent("Blur sensitive pictures") {
          HStack(spacing: 8) {
            Text(self.intervention == .none ? "Off" : "On")
              .foregroundStyle(.secondary)
            // A child's is set in Screen Time, by whoever looks after them. Small, as the
            // Downloads row's are, to fit beside it.
            if self.intervention != .descriptive {
              Button("Open System Settings") {
                NSWorkspace.shared.open(SensitiveContent.settingsURL)
              }
              .controlSize(.small)
            }
          }
        }
      }

      Section {
        LabeledContent {
          Button("Manage…") {
            self.showsEncryptedServers = true
          }
        } label: {
          Text(Self.serverCount(ServerTrust.shared.remembered.count))
          Text("Once you've connected to a server securely, Hotline won't connect to it any other way.")
        }
      } header: {
        Text("Encrypted Servers")
      } footer: {
        Text("Servers you connect to can see your IP address, and so can their admins.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      self.intervention = SensitiveContent.currentIntervention()
    }
    .sheet(isPresented: self.$showsEncryptedServers) {
      EncryptedServersView()
    }
  }

  /// How many servers are only connected to securely.
  private static func serverCount(_ count: Int) -> String {
    switch count {
    case 0: "No servers yet"
    case 1: "1 server"
    default: "\(count.formatted()) servers"
    }
  }
}

/// The servers that have been connected to securely, which are only connected to that way since,
/// each of which can be forgotten, as for one that's stopped taking secure connections.
struct EncryptedServersView: View {
  @Environment(\.dismiss) private var dismiss
  /// The server to forget, once it's asked about.
  @State private var forgetting: ServerTrust.Remembered?

  var body: some View {
    let servers = ServerTrust.shared.remembered

    VStack(spacing: 0) {
      Group {
        if servers.isEmpty {
          ContentUnavailableView("No Encrypted Servers", systemImage: "lock", description: Text("Servers you connect to securely are listed here."))
        }
        else {
          List(servers) { server in
            HStack(spacing: 8) {
              Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text(Self.name(of: server))
                Text(Self.details(of: server))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Forget…") {
                self.forgetting = server
              }
              .controlSize(.small)
            }
            .padding(.vertical, 2)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      HStack {
        Spacer()
        Button("Done") {
          self.dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
    .frame(width: 460, height: 340)
    .confirmationDialog(
      "Forget \(self.forgetting.map(Self.name(of:)) ?? "this server")?",
      isPresented: Binding(
        get: { self.forgetting != nil },
        set: { if !$0 { self.forgetting = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let server = self.forgetting {
        Button("Forget") {
          ServerTrust.shared.forget(address: server.address, port: server.port)
          self.forgetting = nil
        }
      }
      Button("Cancel", role: .cancel) {
        self.forgetting = nil
      }
    } message: {
      Text("The next time you connect, whatever certificate it has will be trusted, as it was the first time.")
    }
  }

  private static func name(of server: ServerTrust.Remembered) -> String {
    server.port == HotlinePorts.DefaultServerPort ? server.address : "\(server.address):\(server.port)"
  }

  /// Who its certificate's for, if that's another name, and when it was last connected to.
  private static func details(of server: ServerTrust.Remembered) -> String {
    let connected = "Connected \(server.record.date.formatted(.relative(presentation: .named)))"
    let name = server.record.name
    guard !name.isEmpty, name.caseInsensitiveCompare(server.address) != .orderedSame else {
      return connected
    }
    return "Certificate for \(name) · \(connected)"
  }
}
