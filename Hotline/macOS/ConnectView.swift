import SwiftUI

struct ConnectView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  
  @Binding var address: String
  @Binding var login: String
  @Binding var password: String
  @Binding var useTLS: Bool

  var action: (() -> Void)? = nil
  
  @State private var bookmarkSheetPresented: Bool = false
  @State private var bookmarkName: String = ""
  
  private enum FocusFields {
    case address
    case login
    case password
  }
  
  @FocusState private var focusedField: FocusFields?
  
  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      Form {
        HStack(alignment: .top, spacing: 10) {
          Image("Server Large")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
          
          VStack(alignment: .leading) {
            Text("Connect to Server")
            Text("Enter the address of a Hotline server to connect to.")
              .foregroundStyle(.secondary)
              .font(.subheadline)
          }
        }
        
        TextField(text: self.$address) {
          Text("Address")
        }
        .focused($focusedField, equals: .address)
        
        TextField(text: self.$login, prompt: Text("Optional")) {
          Text("Login")
        }
        .focused($focusedField, equals: .login)
        
        SecureField(text: self.$password, prompt: Text("Optional")) {
          Text("Password")
        }
        .focused($focusedField, equals: .password)

        Toggle(isOn: self.$useTLS) {
          Text("Use TLS")
        }
      }
      .formStyle(.grouped)
      .fixedSize(horizontal: false, vertical: true)
      
      HStack {
        Button {
          if !self.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.bookmarkSheetPresented = true
          }
        } label: {
          Image(systemName: "bookmark.fill")
        }
        .disabled(self.address.isEmpty)
        .controlSize(.regular)
        .buttonStyle(.automatic)
        .help("Bookmark server")
        
        Spacer()
        
        Button("Cancel") {
          self.dismiss()
        }
        .controlSize(.regular)
        .buttonStyle(.automatic)
        .keyboardShortcut(.cancelAction)
        
        Button("Connect") {
          self.action?()
//          self.connectToServer()
        }
        .controlSize(.regular)
        .buttonStyle(.automatic)
        .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 20)
    }
//    .onChange(of: self.address) {
//      let (a, p) = Server.parseServerAddressAndPort(connectAddress)
//      server.address = a
//      server.port = p
//    }
//    .onChange(of: connectLogin) {
//      server.login = connectLogin.trimmingCharacters(in: .whitespacesAndNewlines)
//    }
//    .onChange(of: connectPassword) {
//      server.password = connectPassword
//    }
    .frame(maxWidth: 380)
    .padding()
    .onAppear {
      self.focusedField = .address
    }
    .sheet(isPresented: self.$bookmarkSheetPresented) {
      VStack(alignment: .leading) {
        Text("Save Bookmark")
          .foregroundStyle(.secondary)
          .padding(.bottom, 4)
        TextField("Bookmark Name", text: self.$bookmarkName)
          .textFieldStyle(.roundedBorder)
          .controlSize(.large)
      }
      .frame(width: 250)
      .padding()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            self.bookmarkSheetPresented = false
            self.bookmarkName = ""
          }
        }
        
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let name = String(self.bookmarkName.trimmingCharacters(in: .whitespacesAndNewlines))
            if !name.isEmpty {
              self.bookmarkSheetPresented = false
              self.bookmarkName = ""

              let (host, port) = Server.parseServerAddressAndPort(self.address)
              let login: String? = self.login.isBlank ? nil : self.login
              let password: String? = self.password.isBlank ? nil : self.password
              
              if !host.isEmpty {
                let newBookmark = Bookmark(type: .server, name: name, address: host, port: port, login: login, password: password, useTLS: self.useTLS)
                Bookmark.add(newBookmark, context: modelContext)
              }
            }
          }
        }
      }
    }
  }
}
