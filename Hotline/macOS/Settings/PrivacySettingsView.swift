import SwiftUI

/// What others can see of you, and who can reach you: which sites see your address as pictures load
/// from them, what you'd rather not see, who can message you, and which servers are only connected to
/// securely.
struct PrivacySettingsView: View {
  #if SENSITIVE_CONTENT_ANALYSIS
  /// How the Mac has sensitive content shown, read again as the app comes back from System Settings.
  @State private var intervention = SensitiveContent.currentIntervention()
  #endif
  @State private var showsEncryptedServers = false

  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      // Who can reach you, first.
      Section("Private Messages") {
        Toggle("Refuse private chat invites", isOn: $preferences.refusePrivateChat)
        Toggle("Refuse private messages", isOn: $preferences.refusePrivateMessages)
      }

      Section {
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
      } header: {
        Text("Image Previews")
      } footer: {
        Text("Image previews only load over secure connections from sites with registered names and never from IP addresses beyond the server you're on.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Section("Sensitive Content") {
        // Until it's chosen, on for a child, as Communication Safety is.
        Toggle("Hide offensive words", isOn: Binding(
          get: { HiddenWords.isOn },
          set: { Prefs.shared.hideOffensiveWords = $0 }
        ))

        #if SENSITIVE_CONTENT_ANALYSIS
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
        #endif
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
    #if SENSITIVE_CONTENT_ANALYSIS
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      self.intervention = SensitiveContent.currentIntervention()
    }
    #endif
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
/// any of which can be picked and forgotten, as for one that's stopped taking secure connections.
struct EncryptedServersView: View {
  @Environment(\.dismiss) private var dismiss
  /// The servers picked in the list.
  @State private var selection = Set<ServerTrust.Remembered.ID>()
  /// The servers to forget, once they're asked about.
  @State private var forgetting: [ServerTrust.Remembered] = []

  var body: some View {
    let servers = ServerTrust.shared.remembered

    VStack(spacing: 0) {
      Group {
        if servers.isEmpty {
          ContentUnavailableView("No Encrypted Servers", systemImage: "lock", description: Text("Servers you connect to securely are listed here."))
        }
        else {
          List(servers, selection: self.$selection) { server in
            HStack(spacing: 8) {
              Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text(Self.name(of: server))
                Text(Self.details(of: server))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .listRowSeparator(.hidden)
          }
          .alternatingRowBackgrounds()
          // Delete, and the menu for what's picked, or what's clicked, forget those too, and a
          // double-click, or Return, shows one's certificate.
          .onDeleteCommand {
            self.askToForget(self.selection, of: servers)
          }
          .contextMenu(forSelectionType: ServerTrust.Remembered.ID.self) { picked in
            if let server = Self.single(picked, of: servers) {
              Button("Show Certificate") {
                Self.showCertificate(of: server)
              }
              .disabled(server.record.certificate == nil)
            }
            Button("Forget…") {
              self.askToForget(picked, of: servers)
            }
          } primaryAction: { picked in
            if let server = Self.single(picked, of: servers) {
              Self.showCertificate(of: server)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      HStack {
        Button("Forget…") {
          self.askToForget(self.selection, of: servers)
        }
        .disabled(self.selection.isEmpty)
        let picked = Self.single(self.selection, of: servers)
        Button("Show Certificate") {
          if let picked {
            Self.showCertificate(of: picked)
          }
        }
        .disabled(picked?.record.certificate == nil)
        .help(picked != nil && picked?.record.certificate == nil
          ? "Its certificate's kept the next time you connect to it."
          : "The certificate it gave the last time you connected.")
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
      self.forgettingTitle,
      isPresented: Binding(
        get: { !self.forgetting.isEmpty },
        set: { if !$0 { self.forgetting = [] } }
      ),
      titleVisibility: .visible
    ) {
      Button("Forget") {
        for server in self.forgetting {
          ServerTrust.shared.forget(address: server.address, port: server.port)
        }
        self.selection.subtract(self.forgetting.map(\.id))
        self.forgetting = []
      }
      Button("Cancel", role: .cancel) {
        self.forgetting = []
      }
    } message: {
      Text(self.forgetting.count > 1
        ? "The next time you connect to each, whatever certificate it has will be trusted, as it was the first time."
        : "The next time you connect, whatever certificate it has will be trusted, as it was the first time.")
    }
  }

  /// The one server picked, should just one be.
  private static func single(_ picked: Set<ServerTrust.Remembered.ID>, of servers: [ServerTrust.Remembered]) -> ServerTrust.Remembered? {
    guard picked.count == 1, let id = picked.first else {
      return nil
    }
    return servers.first { $0.id == id }
  }

  /// Shows the certificate a server gave the last time it was connected to, once what asked for it
  /// is done, as the panel waits until it's closed.
  private static func showCertificate(of server: ServerTrust.Remembered) {
    guard let data = server.record.certificate else {
      return
    }
    DispatchQueue.main.async {
      ServerTrust.showCertificate(data)
    }
  }

  /// Asks about forgetting the servers picked, in the list's order.
  private func askToForget(_ picked: Set<ServerTrust.Remembered.ID>, of servers: [ServerTrust.Remembered]) {
    let chosen = servers.filter { picked.contains($0.id) }
    if !chosen.isEmpty {
      self.forgetting = chosen
    }
  }

  /// The server it asks about forgetting, by name, or how many.
  private var forgettingTitle: String {
    guard self.forgetting.count > 1 else {
      return "Forget \(self.forgetting.first.map(Self.name(of:)) ?? "this server")?"
    }
    return "Forget \(self.forgetting.count) servers?"
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
