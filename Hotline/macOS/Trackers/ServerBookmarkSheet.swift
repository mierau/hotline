import SwiftUI
import SwiftData

struct ServerBookmarkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  /// The bookmark being edited, or nil for a new one.
  @State private var bookmark: Bookmark?
  @State private var serverName: String = ""
  @State private var serverAddress: String = ""
  @State private var serverLogin: String = ""
  @State private var serverPassword: String = ""
  /// Whether it's connected to over TLS, and on which port.
  @State private var encrypted: Bool = false
  @State private var tlsPort: String = String(HotlinePorts.DefaultTLSPort)
  /// Checking whether the server supports secure connections, and what was found.
  @State private var checking: Bool = false
  @State private var checkResult: ServerTrust.CheckResult? = nil
  @State private var checkTask: Task<Void, Never>? = nil

  init(_ editingBookmark: Bookmark) {
    _bookmark = .init(initialValue: editingBookmark)
    _serverName = .init(initialValue: editingBookmark.name)
    _serverAddress = .init(initialValue: editingBookmark.displayAddress)
    _serverLogin = .init(initialValue: editingBookmark.login ?? "")
    _serverPassword = .init(initialValue: editingBookmark.password ?? "")
    // On for one that's been connected to over TLS, too, which it is from then on.
    _encrypted = .init(initialValue: editingBookmark.isSecure)
    let tlsPort = editingBookmark.tlsPort ?? ServerTrust.shared.record(address: editingBookmark.address, port: editingBookmark.port)?.tlsPort
    _tlsPort = .init(initialValue: String(tlsPort ?? HotlinePorts.DefaultTLSPort))
  }

  /// A new bookmark, filled in with whatever's known of it already, like the TLS port it's
  /// connected on, for one that's encrypted.
  init(name: String = "", address: String = "", login: String = "", password: String = "", tlsPort: Int? = nil) {
    _bookmark = .init(initialValue: nil)
    _serverName = .init(initialValue: name)
    _serverAddress = .init(initialValue: address)
    _serverLogin = .init(initialValue: login)
    _serverPassword = .init(initialValue: password)
    _encrypted = .init(initialValue: tlsPort != nil)
    _tlsPort = .init(initialValue: String(tlsPort ?? HotlinePorts.DefaultTLSPort))
  }

  /// The TLS port, as it's typed, if it's one there's room after for file transfers.
  private var validTLSPort: Int? {
    guard let port = Int(self.tlsPort.trimmingCharacters(in: .whitespaces)), (1..<Int(UInt16.max)).contains(port) else {
      return nil
    }
    return port
  }

  /// Checks whether the server supports secure connections: on the TLS port as it's typed, and on
  /// the one Mobius usually uses, and turns them on, on the one it finds.
  private func check() {
    let host = Server.parseServerAddress(self.serverAddress).host
    guard !host.isEmpty else {
      return
    }
    var ports = [self.validTLSPort ?? HotlinePorts.DefaultTLSPort]
    if !ports.contains(HotlinePorts.DefaultTLSPort) {
      ports.append(HotlinePorts.DefaultTLSPort)
    }

    self.checkTask?.cancel()
    self.checking = true
    self.checkResult = nil
    self.checkTask = Task {
      let result = await ServerTrust.shared.checkSecureConnection(address: host, ports: ports)
      guard !Task.isCancelled else {
        return
      }
      self.checking = false
      self.checkResult = result
      if case .found(let port, _) = result {
        withAnimation(.snappy) {
          self.encrypted = true
          self.tlsPort = String(port)
        }
      }
    }
  }

  var body: some View {
    Form {
      Section {
        TextField(text: $serverName) {
          Text("Name")
        }
      }

      Section {
        TextField(text: $serverAddress) {
          Text("Address")
        }
        TextField(text: $serverLogin, prompt: Text("Optional")) {
          Text("Login")
        }
        SecureField(text: $serverPassword, prompt: Text("Optional")) {
          Text("Password")
        }
      }

      Section {
        Toggle("Secure connection", isOn: $encrypted)
        if self.encrypted {
          TextField(text: $tlsPort, prompt: Text(String(HotlinePorts.DefaultTLSPort))) {
            Text("TLS Port")
          }
        }
        SecureConnectionCheckRow(checking: self.checking, result: self.checkResult) {
          self.check()
        }
        .disabled(Server.parseServerAddress(self.serverAddress).host.isEmpty)
      } footer: {
        Text("For servers that support secure connections on port \(String(HotlinePorts.DefaultTLSPort)) unless it's set otherwise.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .frame(width: 350)
    .fixedSize(horizontal: true, vertical: true)
    .animation(.snappy, value: self.encrypted)
    // What was found is for the server, and port, it was found on.
    .onChange(of: self.serverAddress) {
      self.checkTask?.cancel()
      self.checking = false
      self.checkResult = nil
      // A hotlines:// address is to connect securely, on its port, which is checked as it's turned
      // on.
      if let tlsPort = Server.parseServerAddress(self.serverAddress).tlsPort {
        self.tlsPort = String(tlsPort)
        self.encrypted = true
      }
    }
    // Turned on, checked, so the port's known to be right, or the right one's found, unless it was
    // a check that turned it on.
    .onChange(of: self.encrypted) { _, encrypted in
      guard encrypted, !self.checking else {
        return
      }
      if case .found = self.checkResult {
        return
      }
      if !Server.parseServerAddress(self.serverAddress).host.isEmpty {
        self.check()
      }
    }
    .onChange(of: self.tlsPort) {
      if case .found(let port, _) = self.checkResult, String(port) == self.tlsPort {
        return
      }
      self.checkResult = nil
    }
    .onDisappear {
      self.checkTask?.cancel()
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(self.bookmark == nil ? "Create" : "Save") {
          let displayName = self.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
          let (host, port) = Server.parseServerAddressAndPort(self.serverAddress)
          let login = self.serverLogin.trimmingCharacters(in: .whitespacesAndNewlines)
          let password = self.serverPassword
          let tlsPort = self.encrypted ? self.validTLSPort : nil

          if !displayName.isEmpty && !host.isEmpty {
            if let bookmark = self.bookmark {
              bookmark.name = displayName
              bookmark.address = host
              bookmark.port = port
              bookmark.tlsPort = tlsPort
              bookmark.login = login.isEmpty ? nil : login
              bookmark.password = password.isEmpty ? nil : password
            }
            else {
              let bookmark = Bookmark(type: .server, name: displayName, address: host, port: port, tlsPort: tlsPort, login: login.isEmpty ? nil : login, password: password.isEmpty ? nil : password)
              Bookmark.add(bookmark, context: self.modelContext)
            }

            // Off, it isn't connected to over TLS, even if it has been before, unless a tracker
            // lists it with a TLS port.
            if !self.encrypted {
              ServerTrust.shared.forget(address: host, port: port)
            }

            self.dismiss()
          }
        }
        .disabled(self.serverName.isBlank || Server.parseServerAddress(self.serverAddress).host.isEmpty || (self.encrypted && self.validTLSPort == nil))
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }
    }
  }
}

/// Checking whether a server supports secure connections, from its bookmark: what was found, or
/// what checking does, until it's checked, with Check beside it.
struct SecureConnectionCheckRow: View {
  let checking: Bool
  let result: ServerTrust.CheckResult?
  let check: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      self.status
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Check", action: self.check)
        .disabled(self.checking)
    }
  }

  @ViewBuilder
  private var status: some View {
    if self.checking {
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Checking…")
          .foregroundStyle(.secondary)
      }
    }
    else {
      switch self.result {
      case .found(let port, let name):
        // Who its certificate is for under what was found, past the checkmark.
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("Supports secure connections on port \(String(port))")
              .fixedSize(horizontal: false, vertical: true)
            if !name.isEmpty {
              Text("Certificate for \(name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
        } icon: {
          DrawnInSymbol(systemName: "checkmark.circle.fill", style: AnyShapeStyle(.green))
        }
      case .notFound(let ports) where !ports.isEmpty:
        // In gray, as it's how most servers are, rather than anything wrong.
        Label {
          Text(ports.count == 1 ? "No secure connection on port \(String(ports[0]))" : "No secure connection on ports \(ports.map { String($0) }.formatted(.list(type: .or)))")
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          DrawnInSymbol(systemName: "xmark.circle.fill", style: AnyShapeStyle(.secondary))
        }
        .foregroundStyle(.secondary)
      case .unknownAddress:
        // Something to put right, as a typo in the address is, in the warning's yellow.
        Label {
          Text("Couldn't find the server")
        } icon: {
          DrawnInSymbol(systemName: "exclamationmark.triangle.fill", multicolor: true)
        }
        .foregroundStyle(.secondary)
      default:
        Text("See if the server supports secure connections.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// What checking found, as a symbol that draws itself in as it shows, or before macOS 26, which
/// can't, grows in: the green checkmark of a server that supports secure connections, and the gray
/// X of one that doesn't, or a warning.
private struct DrawnInSymbol: View {
  let systemName: String
  var style: AnyShapeStyle = AnyShapeStyle(.primary)
  /// In the symbol's own colors, as the warning's yellow is, rather than `style`.
  var multicolor: Bool = false

  @State private var shown = false

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        Image(systemName: self.systemName)
          .symbolEffect(.drawOff, isActive: !self.shown)
      }
      else {
        Image(systemName: self.systemName)
          .scaleEffect(self.shown ? 1 : 0.3)
          .opacity(self.shown ? 1 : 0)
      }
    }
    .symbolRenderingMode(self.multicolor ? .multicolor : .monochrome)
    .foregroundStyle(self.style)
    // What was found says so.
    .accessibilityHidden(true)
    .task {
      // Once it's showing, so it's seen to come in.
      try? await Task.sleep(for: .milliseconds(60))
      withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
        self.shown = true
      }
    }
  }
}
