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

  init(_ editingBookmark: Bookmark) {
    _bookmark = .init(initialValue: editingBookmark)
    _serverName = .init(initialValue: editingBookmark.name)
    _serverAddress = .init(initialValue: editingBookmark.displayAddress)
    _serverLogin = .init(initialValue: editingBookmark.login ?? "")
    _serverPassword = .init(initialValue: editingBookmark.password ?? "")
  }

  /// A new bookmark, filled in with whatever's known of it already.
  init(name: String = "", address: String = "", login: String = "", password: String = "") {
    _bookmark = .init(initialValue: nil)
    _serverName = .init(initialValue: name)
    _serverAddress = .init(initialValue: address)
    _serverLogin = .init(initialValue: login)
    _serverPassword = .init(initialValue: password)
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
    }
    .formStyle(.grouped)
    .frame(width: 350)
    .fixedSize(horizontal: true, vertical: true)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(self.bookmark == nil ? "Create" : "Save") {
          let displayName = self.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
          let (host, port) = Server.parseServerAddressAndPort(self.serverAddress)
          let login = self.serverLogin.trimmingCharacters(in: .whitespacesAndNewlines)
          let password = self.serverPassword

          if !displayName.isEmpty && !host.isEmpty {
            if let bookmark = self.bookmark {
              bookmark.name = displayName
              bookmark.address = host
              bookmark.port = port
              bookmark.login = login.isEmpty ? nil : login
              bookmark.password = password.isEmpty ? nil : password
            }
            else {
              let bookmark = Bookmark(type: .server, name: displayName, address: host, port: port, login: login.isEmpty ? nil : login, password: password.isEmpty ? nil : password)
              Bookmark.add(bookmark, context: self.modelContext)
            }

            self.dismiss()
          }
        }
        .disabled(self.serverName.isBlank || Server.parseServerAddress(self.serverAddress).host.isEmpty)
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }
    }
  }
}
