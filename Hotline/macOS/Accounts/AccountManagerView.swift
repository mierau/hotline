import SwiftUI

struct AccountManagerView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var accounts: [HotlineAccount] = []
  @State private var selection: HotlineAccount?
  @State private var loading: Bool = true
  
  @State private var pendingName: String = ""
  @State private var pendingLogin: String = ""
  @State private var pendingPassword: String = ""
  @State private var pendingAccess = HotlineUserAccessOptions.defaultAccess
  
  @State private var toDelete: HotlineAccount?
  
  let placeholderPassword = "xxxxxxxxxxxxxxxxxx"
  
  var body: some View {
    HStack(spacing: 0) {
      ZStack {
        accountList
        if loading {
          ProgressView()
        }
      }
      if selection != nil {
        accountDetails
      }
      else {
        ZStack(alignment: .center) {
          Text("No Account Selected")
            .font(.title)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
        }
        .frame(maxWidth: .infinity)
      }
    }
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .task {
      if loading {
        accounts = await model.getAccounts()
        loading = false
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          let newAccount = HotlineAccount("unnamed", "unnamed", HotlineUserAccessOptions.defaultAccess)
          
          pendingPassword = HotlineAccount.randomPassword()
          accounts.append(newAccount)
          selection = newAccount
        } label: {
          Label("New Account", systemImage: "plus")
        }
        .help("Create a new account")
        .disabled(model.access?.contains(.canCreateUsers) != true)
      }
      
      ToolbarItem(placement: .destructiveAction) {
        Button {
          toDelete = selection
        } label: {
          Label("Delete Account", systemImage: "trash")
        }
        .help("Delete account")
        .disabled(selection == nil || model.access?.contains(.canDeleteUsers) != true)
      }
    }
  }
  
  var accountDetails: some View {
    VStack(alignment: .center, spacing: 0) {
      ScrollView(.vertical) {
        Form {
          Section {
            TextField(text: $pendingName) {
              Text("Name")
            }
            TextField("Login", text: $pendingLogin)
              .disabled(selection?.persisted == true)
            if selection?.persisted == true {
              SecureField("Password", text: $pendingPassword)
            } else {
              TextField("Password", text: $pendingPassword)
            }
          }
          .textFieldStyle(.roundedBorder)
          .controlSize(.large)
          
          Section("File System Maintenance") {
            Toggle("Can Download Files", isOn: $pendingAccess.bind(.canDownloadFiles))
              .disabled(model.access?.contains(.canDownloadFiles) == false)
            Toggle("Can Download Folders", isOn: $pendingAccess.bind(.canDownloadFolders))
              .disabled(model.access?.contains(.canDownloadFolders) == false)
            Toggle("Can Upload Files", isOn: $pendingAccess.bind(.canUploadFiles))
              .disabled(model.access?.contains(.canUploadFiles) == false)
            Toggle("Can Upload Folders", isOn: $pendingAccess.bind(.canUploadFolders))
              .disabled(model.access?.contains(.canUploadFolders) == false)
            Toggle("Can Upload Anywhere", isOn: $pendingAccess.bind(.canUploadAnywhere))
              .disabled(model.access?.contains(.canUploadAnywhere) == false)
            Toggle("Can Delete Files", isOn: $pendingAccess.bind(.canDeleteFiles))
              .disabled(model.access?.contains(.canDeleteFiles) == false)
            Toggle("Can Rename Files", isOn: $pendingAccess.bind(.canRenameFiles))
              .disabled(model.access?.contains(.canRenameFiles) == false)
            Toggle("Can Move Files", isOn: $pendingAccess.bind(.canMoveFiles))
              .disabled(model.access?.contains(.canMoveFiles) == false)
            Toggle("Can Comment Files", isOn: $pendingAccess.bind(.canSetFileComment))
              .disabled(model.access?.contains(.canSetFileComment) == false)
            Toggle("Can Create Folders", isOn: $pendingAccess.bind(.canCreateFolders))
              .disabled(model.access?.contains(.canCreateFolders) == false)
            Toggle("Can Delete Folders", isOn: $pendingAccess.bind(.canDeleteFolders))
              .disabled(model.access?.contains(.canDeleteFolders) == false)
            Toggle("Can Rename Folders", isOn: $pendingAccess.bind(.canRenameFolders))
              .disabled(model.access?.contains(.canRenameFolders) == false)
            Toggle("Can Move Folders", isOn: $pendingAccess.bind(.canMoveFolders))
              .disabled(model.access?.contains(.canMoveFolders) == false)
            Toggle("Can Comment Folders", isOn: $pendingAccess.bind(.canSetFolderComment))
              .disabled(model.access?.contains(.canSetFolderComment) == false)
            Toggle("Can View Drop Boxes", isOn: $pendingAccess.bind(.canViewDropBoxes))
              .disabled(model.access?.contains(.canViewDropBoxes) == false)
            Toggle("Can Make Aliases", isOn: $pendingAccess.bind(.canMakeAliases))
              .disabled(model.access?.contains(.canMakeAliases) == false)
          }
          
          Section("User Maintenance") {
            Toggle("Can Create Accounts", isOn: $pendingAccess.bind(.canCreateUsers))
              .disabled(model.access?.contains(.canCreateUsers) == false)
            Toggle("Can Delete Accounts", isOn: $pendingAccess.bind(.canDeleteUsers))
              .disabled(model.access?.contains(.canDeleteUsers) == false)
            Toggle("Can Read Accounts", isOn: $pendingAccess.bind(.canOpenUsers))
              .disabled(model.access?.contains(.canOpenUsers) == false)
            Toggle("Can Modify Accounts", isOn: $pendingAccess.bind(.canModifyUsers))
              .disabled(model.access?.contains(.canModifyUsers) == false)
            Toggle("Can Get User Info", isOn: $pendingAccess.bind(.canGetClientInfo))
              .disabled(model.access?.contains(.canGetClientInfo) == false)
            
            Toggle("Can Disconnect Users", isOn: $pendingAccess.bind(.canDisconnectUsers))
              .disabled(model.access?.contains(.canDisconnectUsers) == false)
            Toggle("Cannot be Disconnected", isOn: $pendingAccess.bind(.cantBeDisconnected))
              .disabled(model.access?.contains(.cantBeDisconnected) == false)
          }
          
          Section("Messaging") {
            Toggle("Can Send Messages", isOn: $pendingAccess.bind(.canSendMessages))
              .disabled(model.access?.contains(.canSendMessages) == false)
            Toggle("Can Broadcast", isOn: $pendingAccess.bind(.canBroadcast))
              .disabled(model.access?.contains(.canBroadcast) == false)
          }
          
          Section("News") {
            Toggle("Can Read Articles", isOn: $pendingAccess.bind(.canReadMessageBoard))
              .disabled(model.access?.contains(.canReadMessageBoard) == false)
            Toggle("Can Post Articles", isOn: $pendingAccess.bind(.canPostMessageBoard))
              .disabled(model.access?.contains(.canPostMessageBoard) == false)
            Toggle("Can Delete Articles", isOn: $pendingAccess.bind(.canDeleteNewsArticles))
              .disabled(model.access?.contains(.canDeleteNewsArticles) == false)
            Toggle("Can Create Categories", isOn: $pendingAccess.bind(.canCreateNewsCategories))
              .disabled(model.access?.contains(.canCreateNewsCategories) == false)
            Toggle("Can Delete Categories", isOn: $pendingAccess.bind(.canDeleteNewsCategories))
              .disabled(model.access?.contains(.canDeleteNewsCategories) == false)
            Toggle("Can Create News Bundles", isOn: $pendingAccess.bind(.canCreateNewsFolders))
              .disabled(model.access?.contains(.canCreateNewsFolders) == false)
            Toggle("Can Delete News Bundles", isOn: $pendingAccess.bind(.canDeleteNewsFolders))
              .disabled(model.access?.contains(.canDeleteNewsFolders) == false)
          }
          
          Section("Chat") {
            Toggle("Can Initiate Private Chat", isOn: $pendingAccess.bind(.canCreateChat))
              .disabled(model.access?.contains(.canCreateChat) == false)
            Toggle("Can Read Chat", isOn: $pendingAccess.bind(.canReadChat))
              .disabled(model.access?.contains(.canReadChat) == false)
            Toggle("Can Send Chat", isOn: $pendingAccess.bind(.canSendChat))
              .disabled(model.access?.contains(.canSendChat) == false)
          }
          
          Section("Miscellaneous") {
            Toggle("Can Use Any Name", isOn: $pendingAccess.bind(.canUseAnyName))
              .disabled(model.access?.contains(.canUseAnyName) == false)
            Toggle("Don't Show Agreement", isOn: $pendingAccess.bind(.canSkipAgreement))
              .disabled(model.access?.contains(.canSkipAgreement) == false)
          }
        }
        .disabled(model.access?.contains(.canModifyUsers) == false)
        .formStyle(.grouped)
        .onChange(of: selection) {
          if let selection {
            pendingName = selection.name
            pendingLogin = selection.login
            pendingAccess = selection.access
            
            if selection.persisted {
              if selection.password == nil {
                pendingPassword = ""
              } else {
                pendingPassword = placeholderPassword
              }
            }
          }
        }
        .onAppear() {
          if let selection {
            pendingName = selection.name
            pendingLogin = selection.login
            pendingAccess = selection.access
            
            if selection.persisted {
              if selection.password == nil {
                pendingPassword = ""
              } else {
                pendingPassword = placeholderPassword
              }
            } else {
              pendingPassword =  HotlineAccount.randomPassword()
            }
          }
        }
      }
      .frame(maxWidth: .infinity)
      
      Divider()
      
      HStack() {
        Button("Revert") {
          if let selection {
            pendingAccess = selection.access
            pendingName = selection.name
            pendingLogin = selection.login
            
            if selection.password != nil {
              pendingPassword = selection.password!
            }
          }
        }
        .controlSize(.large)
        .frame(minWidth: 75)
        .disabled(!self.isSaveable())
//        .padding()
        
        Spacer()
        
        Button("Save"){
          guard let selection else {
            return
          }
          
          // Update existing account
          if selection.persisted == true {

            if pendingPassword == placeholderPassword {
              Task { @MainActor in
                model.client.sendSetUser(name: pendingName, login: pendingLogin, newLogin: nil, password: nil, access: pendingAccess.rawValue)
              }
            } else {
              Task { @MainActor in
                model.client.sendSetUser(name: pendingName, login: pendingLogin, newLogin: nil, password: pendingPassword, access: pendingAccess.rawValue)
              }
            }

          } else {
            // Create new existing account
            Task { @MainActor in
              model.client.sendCreateUser(name: pendingName, login: pendingLogin, password: pendingPassword, access: pendingAccess.rawValue)
            }
            self.selection?.password = pendingPassword
            pendingPassword = placeholderPassword
          }
          
          var account = HotlineAccount(pendingName, pendingLogin, pendingAccess)
          account.persisted = true
          account.password = placeholderPassword
          
          accounts = accounts.filter { $0.persisted == true && $0.login != selection.login }
          
          // Add new account to list
          accounts.append(account)
          
          // Re-sort accounts
          accounts.sort { $0.login < $1.login }
          self.selection = account
        }
        .controlSize(.large)
        .frame(minWidth: 75)
        .keyboardShortcut(.defaultAction)
        .disabled(!self.isSaveable())
      }
      .padding()
    }
    
  }
  
  var accountList: some View {
    List(accounts, id: \.self, selection: $selection) { account in
      HStack(spacing: 5) {
        if account.access.contains(.canDisconnectUsers) {
          Image("User Admin")
            .frame(width: 16, height: 16)
            .opacity(account.persisted ? 1.0 : 0.25)
          //                .padding(.leading, 4)
          Text(account.login)
            .foregroundStyle(Color.hotlineRed)
        }
        else if account.access.rawValue == 0 {
          Image("User")
            .frame(width: 16, height: 16)
          //                .padding(.leading, 4)
          Text(account.login)
            .foregroundStyle(.secondary)
        }
        //            else if account.persisted == false {
        //              HStack {
        //                Image("User")
        //                  .frame(width: 16, height: 16)
        ////                  .padding(.leading, 4)
        //                Text(account.login)
        //                  .italic()
        //              }
        //            }
        else {
          Image("User")
            .frame(width: 16, height: 16)
            .opacity(account.persisted ? 1.0 : 0.5)
          //                .padding(.leading, 4)
          Text(account.login)
        }
      }
    }
    .frame(width: 250)
    .sheet(item: $toDelete) { item in
      Form {
        HStack{
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 30))
          Text("Delete account \"\(item.name)\" and all associated files?")
            .lineSpacing(4)
        }
      }
      .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity, minHeight: 100, idealHeight: 100, maxHeight: .infinity)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            toDelete = nil
          }
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button("Delete") {
            guard let userToDelete = toDelete else {
              return
            }
            
            self.toDelete = nil
            self.selection = nil
            
            if userToDelete.persisted {
              Task { @MainActor in
                model.client.sendDeleteUser(login: userToDelete.login)
              }
            }
            
            accounts = accounts.filter { $0.login != userToDelete.login }
            
          }
        }
      }
    }
  }
  
  
  private func isSaveable() -> Bool {
    guard let selection else {
      return false
    }
    
    // Disable save if login field is cleared
    if pendingLogin == "" {
      return false
    }
    
    // If the account initial has a password and it was updated
    if selection.password != nil && pendingPassword != placeholderPassword {
      return true
    }
    
    // If the account initial has no password, but was updated to have one
    if selection.password == nil && pendingPassword != "" {
      return true
    }
    
    // If the access bits or user name have been changed
    return pendingAccess.rawValue != selection.access.rawValue || selection.name != pendingName
  }
}
