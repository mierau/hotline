import SwiftUI

fileprivate let PASSWORD_PLACEHOLDER = "xxxxxxxxxxxxxxxxxx"

enum AccountDetailsError: Error {
  case noLogin
  case failedToSave
  
  var alertTitle: String {
    switch self {
    case .noLogin: "A login is required"
    case .failedToSave: "Failed to save account"
    }
  }
  
  var alertMessage: String {
    switch self {
    case .noLogin: "Users with accounts are required to have a login. Please add one and try again."
    case .failedToSave: "An error occurred while saving this account. Please try again."
    }
  }
}

struct AccountDetailsView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss
  
  @State var account: HotlineAccount = HotlineAccount(DEFAULT_ACCOUNT_NAME, "", HotlineUserAccessOptions.defaultAccess)
  
  let saved: ((HotlineAccount) -> Void)?
  
  @State private var password: String = ""
  @State private var saving: Bool = false
  @State private var alertTitle: String = ""
  @State private var alertMessage: String = ""
  @State private var alertShown: Bool = false
  
  var body: some View {
    self.detailsView
      .alert(self.alertTitle, isPresented: self.$alertShown, actions: {
        if #available(macOS 26.0, *) {
          Button("OK", role: .confirm) {
            self.alertShown = false
          }
        }
        else {
          Button("OK") {
            self.alertShown = false
          }
        }
        
      }, message: {
        Text(self.alertMessage)
      })
      .onAppear {
        // Display a placeholder for accounts that have been saved to the server
        // because we don't have the account password on hand to display.
        if self.account.persisted {
          self.password = PASSWORD_PLACEHOLDER
        }
      }
      .toolbar {
        if self.saving {
          ToolbarItem {
            ProgressView()
              .controlSize(.small)
          }
        }
        
        ToolbarItem(placement: .cancellationAction) {
          Button {
            self.dismiss()
          } label: {
            Text("Cancel")
          }
        }
        
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task {
              do {
                try await self.save()
              }
              catch {
                let error = error as? AccountDetailsError ?? .failedToSave
                self.alertTitle = error.alertTitle
                self.alertMessage = error.alertMessage
                self.alertShown = true
              }
            }
          } label: {
            Text(self.account.persisted ? "Save" : "Create")
          }
          .disabled(self.saving)
        }
      }
  }
  
  private func save() async throws {
    guard !self.account.login.isBlank else {
      throw AccountDetailsError.noLogin
    }
    
    self.account.name = self.account.name.trimmingCharacters(in: .whitespacesAndNewlines)
    self.account.login = self.account.login.trimmingCharacters(in: .whitespacesAndNewlines)
    
    self.saving = true
    defer { self.saving = false }
    
    // We create a name var here so we don't see the default account name
    // flash in the UI while saving.
    var accountName: String = self.account.name
    if accountName.isBlank {
      accountName = DEFAULT_ACCOUNT_NAME
    }
    
    do {
      // Update existing account
      if self.account.persisted {
        if self.password == PASSWORD_PLACEHOLDER {
          try await self.model.setUser(name: accountName, login: self.account.login, newLogin: nil, password: nil, access: self.account.access.rawValue)
        } else {
          try await model.setUser(name: accountName, login: self.account.login, newLogin: nil, password: self.password, access: self.account.access.rawValue)
        }
        
      } else {
        // Create new existing account
        try await model.createUser(name: accountName, login: self.account.login, password: self.password, access: self.account.access.rawValue)
      }
    }
    catch {
      throw AccountDetailsError.failedToSave
    }
    
    self.account.persisted = true
    self.account.name = accountName
    self.saved?(self.account)
  }
  
  private var isEditable: Bool {
    self.model.access?.contains(.canModifyUsers) == true
  }
  
  private var detailsView: some View {
    Form {
      Section {
        TextField(text: self.$account.name, prompt: Text(DEFAULT_ACCOUNT_NAME)) {
          Text("Account")
        }
      }
      .disabled(!self.isEditable)
      
      Section {
        TextField("Login", text: self.$account.login, prompt: Text("Required"))
          .disabled(self.account.persisted)
        
        if self.account.persisted {
          SecureField("Password", text: self.$password, prompt: Text("Optional"))
        } else {
          TextField("Password", text: self.$password, prompt: Text("Optional"))
        }
      }
      .sectionActions {
        HStack {
          Spacer()
          Text("The following permissions define what users of this account can do on this server. Accounts that can disconnect other users are shown in red.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Spacer()
        }
      }
      .disabled(!self.isEditable)
      
      Section("Files") {
        Toggle("Download Files", isOn: self.$account.access.bind(.canDownloadFiles))
//          .disabled(self.model.access?.contains(.canDownloadFiles) == false)
        Toggle("Download Folders", isOn: self.$account.access.bind(.canDownloadFolders))
//          .disabled(model.access?.contains(.canDownloadFolders) == false)
        Toggle("Upload Files", isOn: self.$account.access.bind(.canUploadFiles))
//          .disabled(model.access?.contains(.canUploadFiles) == false)
        Toggle("Upload Folders", isOn: self.$account.access.bind(.canUploadFolders))
//          .disabled(model.access?.contains(.canUploadFolders) == false)
        Toggle("Upload Anywhere", isOn: self.$account.access.bind(.canUploadAnywhere))
//          .disabled(model.access?.contains(.canUploadAnywhere) == false)
        Toggle("Delete Files", isOn: self.$account.access.bind(.canDeleteFiles))
//          .disabled(model.access?.contains(.canDeleteFiles) == false)
        Toggle("Rename Files", isOn: self.$account.access.bind(.canRenameFiles))
//          .disabled(model.access?.contains(.canRenameFiles) == false)
        Toggle("Move Files", isOn: self.$account.access.bind(.canMoveFiles))
//          .disabled(model.access?.contains(.canMoveFiles) == false)
        Toggle("Comment Files", isOn: self.$account.access.bind(.canSetFileComment))
//          .disabled(model.access?.contains(.canSetFileComment) == false)
        Toggle("Create Folders", isOn: self.$account.access.bind(.canCreateFolders))
//          .disabled(model.access?.contains(.canCreateFolders) == false)
        Toggle("Delete Folders", isOn: self.$account.access.bind(.canDeleteFolders))
//          .disabled(model.access?.contains(.canDeleteFolders) == false)
        Toggle("Rename Folders", isOn: self.$account.access.bind(.canRenameFolders))
//          .disabled(model.access?.contains(.canRenameFolders) == false)
        Toggle("Move Folders", isOn: self.$account.access.bind(.canMoveFolders))
//          .disabled(model.access?.contains(.canMoveFolders) == false)
        Toggle("Comment Folders", isOn: self.$account.access.bind(.canSetFolderComment))
//          .disabled(model.access?.contains(.canSetFolderComment) == false)
        Toggle("View Drop Boxes", isOn: self.$account.access.bind(.canViewDropBoxes))
//          .disabled(model.access?.contains(.canViewDropBoxes) == false)
        Toggle("Make Aliases", isOn: self.$account.access.bind(.canMakeAliases))
//          .disabled(model.access?.contains(.canMakeAliases) == false)
      }
      .disabled(!self.isEditable)
      
      Section("User Maintenance") {
        Toggle("Create Accounts", isOn: self.$account.access.bind(.canCreateUsers))
//          .disabled(model.access?.contains(.canCreateUsers) == false)
        Toggle("Delete Accounts", isOn: self.$account.access.bind(.canDeleteUsers))
//          .disabled(model.access?.contains(.canDeleteUsers) == false)
        Toggle("Read Accounts", isOn: self.$account.access.bind(.canOpenUsers))
//          .disabled(model.access?.contains(.canOpenUsers) == false)
        Toggle("Modify Accounts", isOn: self.$account.access.bind(.canModifyUsers))
//          .disabled(model.access?.contains(.canModifyUsers) == false)
        Toggle("Get User Info", isOn: self.$account.access.bind(.canGetClientInfo))
//          .disabled(model.access?.contains(.canGetClientInfo) == false)
        
        Toggle("Disconnect Users", isOn: self.$account.access.bind(.canDisconnectUsers))
//          .disabled(model.access?.contains(.canDisconnectUsers) == false)
        Toggle("Cannot be Disconnected", isOn: self.$account.access.bind(.cantBeDisconnected))
//          .disabled(model.access?.contains(.cantBeDisconnected) == false)
      }
      .disabled(!self.isEditable)
      
      Section("Messaging") {
        Toggle("Send Messages", isOn: self.$account.access.bind(.canSendMessages))
//          .disabled(model.access?.contains(.canSendMessages) == false)
        Toggle("Broadcast", isOn: self.$account.access.bind(.canBroadcast))
//          .disabled(model.access?.contains(.canBroadcast) == false)
      }
      .disabled(!self.isEditable)
      
      Section("News") {
        Toggle("Read Articles", isOn: self.$account.access.bind(.canReadMessageBoard))
//          .disabled(model.access?.contains(.canReadMessageBoard) == false)
        Toggle("Post Articles", isOn: self.$account.access.bind(.canPostMessageBoard))
//          .disabled(model.access?.contains(.canPostMessageBoard) == false)
        Toggle("Delete Articles", isOn: self.$account.access.bind(.canDeleteNewsArticles))
//          .disabled(model.access?.contains(.canDeleteNewsArticles) == false)
        Toggle("Create Categories", isOn: self.$account.access.bind(.canCreateNewsCategories))
//          .disabled(model.access?.contains(.canCreateNewsCategories) == false)
        Toggle("Delete Categories", isOn: self.$account.access.bind(.canDeleteNewsCategories))
//          .disabled(model.access?.contains(.canDeleteNewsCategories) == false)
        Toggle("Create News Bundles", isOn: self.$account.access.bind(.canCreateNewsFolders))
//          .disabled(model.access?.contains(.canCreateNewsFolders) == false)
        Toggle("Delete News Bundles", isOn: self.$account.access.bind(.canDeleteNewsFolders))
//          .disabled(model.access?.contains(.canDeleteNewsFolders) == false)
      }
      .disabled(!self.isEditable)
      
      Section("Chat") {
        Toggle("Initiate Private Chat", isOn: self.$account.access.bind(.canCreateChat))
//          .disabled(model.access?.contains(.canCreateChat) == false)
        Toggle("Read Chat", isOn: self.$account.access.bind(.canReadChat))
//          .disabled(model.access?.contains(.canReadChat) == false)
        Toggle("Send Chat", isOn: self.$account.access.bind(.canSendChat))
//          .disabled(model.access?.contains(.canSendChat) == false)
      }
      .disabled(!self.isEditable)
      
      Section("Miscellaneous") {
        Toggle("Use Any Name", isOn: self.$account.access.bind(.canUseAnyName))
//          .disabled(model.access?.contains(.canUseAnyName) == false)
        Toggle("Don't Show Agreement", isOn: self.$account.access.bind(.canSkipAgreement))
//          .disabled(model.access?.contains(.canSkipAgreement) == false)
      }
      .disabled(!self.isEditable)
    }
    .formStyle(.grouped)
  }
}
