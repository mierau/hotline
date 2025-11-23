import SwiftUI

struct ServerBookmarkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var bookmark: Bookmark
  @State private var serverName: String = ""
  @State private var serverAddress: String = ""
  @State private var serverLogin: String = ""
  @State private var serverPassword: String = ""
  @State private var useTLS: Bool = false

  init(_ editingBookmark: Bookmark) {
    _bookmark = .init(initialValue: editingBookmark)
    _serverName = .init(initialValue: editingBookmark.name)
    _serverAddress = .init(initialValue: editingBookmark.displayAddress)
    _serverLogin = .init(initialValue: editingBookmark.login ?? "")
    _serverPassword = .init(initialValue: editingBookmark.password ?? "")
    _useTLS = .init(initialValue: editingBookmark.useTLS)
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
        Toggle(isOn: $useTLS) {
          Text("Use TLS")
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 350)
    .fixedSize(horizontal: true, vertical: true)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          let displayName = self.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
          let (host, port) = Server.parseServerAddressAndPort(self.serverAddress)
          let login = self.serverLogin.trimmingCharacters(in: .whitespacesAndNewlines)
          let password = self.serverPassword

          if !displayName.isEmpty && !host.isEmpty {
            self.bookmark.name = displayName
            self.bookmark.address = host
            self.bookmark.port = port
            self.bookmark.login = login.isEmpty ? nil : login
            self.bookmark.password = password.isEmpty ? nil : password
            self.bookmark.useTLS = self.useTLS

            self.dismiss()
          }
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }
    }
  }
}
