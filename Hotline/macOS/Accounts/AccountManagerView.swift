import SwiftUI

let DEFAULT_ACCOUNT_NAME = "Untitled Account"

struct AccountManagerView: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss
  
  @State private var accounts: [HotlineAccount] = []
  @State private var selection: HotlineAccount?
  @State private var loading: Bool = true
  
  @State private var creatorShown: Bool = false
  @State private var deleteConfirm: Bool = false
  @State private var accountToEdit: HotlineAccount? = nil
  @State private var accountToDelete: HotlineAccount? = nil
  
  private func newAccount() {
    self.creatorShown = true
  }
  
  private func editAccount(_ account: HotlineAccount) {
    // Always get the latest version from the array to avoid stale data
    if let currentAccount = self.accounts.first(where: { $0.id == account.id }) {
      self.accountToEdit = currentAccount
    }
  }
  
  private func deleteAccount(_ account: HotlineAccount) {
    self.accountToDelete = account
    self.deleteConfirm = true
  }
  
  var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Accounts")
          .font(.headline)
        
        Spacer()
        
        HStack {
          Button {
            self.newAccount()
          } label: {
            Image(systemName: "plus")
              .padding(4)
          }
          .buttonBorderShape(.circle)
          .help("New Account")
          
          Button {
            if let account = self.selection {
              self.editAccount(account)
            }
          } label: {
            Image(systemName: "pencil")
              .padding(4)
          }
          .buttonBorderShape(.circle)
          .disabled(self.selection == nil)
          .help("Edit Account")
          
          Button {
            if let account = self.selection {
              self.deleteAccount(account)
            }
          } label: {
            Image(systemName: "trash")
              .padding(4)
          }
          .tint(.hotlineRed)
          .buttonBorderShape(.circle)
          .disabled(self.selection == nil)
          .help("Delete Account")
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 24)
      
      self.accountList
//        .overlay {
//          if self.loading {
//            ProgressView()
//              .progressViewStyle(.linear)
//              .controlSize(.extraLarge)
//              .frame(width: 100)
//          }
//        }
    }
    .environment(\.defaultMinListRowHeight, 34)
    .listStyle(.inset)
    .alternatingRowBackgrounds(.enabled)
    .task {
      if self.loading {
        do {
          self.accounts = try await self.model.getAccounts()
        }
        catch {
          self.dismiss()
        }
        
        self.loading = false
      }
    }
    .toolbar {
      if self.loading {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }
      
      ToolbarItem(placement: .confirmationAction) {
        Button {
          self.dismiss()
        } label: {
          Text("OK")
        }
      }
    }
  }
  
  private var accountList: some View {
    List(self.accounts, id: \.self, selection: self.$selection) { account in
      HStack(spacing: 5) {
        Image(account.access.contains(.canDisconnectUsers) ? "User Admin" : "User")
          .frame(width: 16, height: 16)
          .opacity((account.access.rawValue == 0) ? 0.5 : 1.0)
        Text(account.name)
          .foregroundStyle(account.access.contains(.canDisconnectUsers) ? Color.hotlineRed : ((account.access.rawValue == 0) ? Color.secondary : Color.primary))
        
        Spacer()
        
        Text(account.login)
          .lineLimit(1)
          .foregroundStyle(.secondary)
      }
    }
    .contextMenu(forSelectionType: HotlineAccount.self) { items in
      Button {
        if let item = items.first {
          self.editAccount(item)
        }
      } label: {
        Label("Edit Account...", systemImage: "pencil")
      }
      .disabled(items.isEmpty)
      
      Divider()
      
      Button(role: .destructive) {
        if let item = items.first {
          self.deleteAccount(item)
        }
      } label: {
        Label("Delete Account...", systemImage: "trash")
      }
      .disabled(items.isEmpty)
    } primaryAction: { items in
      if let account = items.first {
        self.editAccount(account)
      }
    }
    .alert("Are you sure you want to delete the \"\(self.accountToDelete?.name ?? "unknown")\" account?", isPresented: self.$deleteConfirm, actions: {
      Button("Delete", role: .destructive) {
        guard let account = self.accountToDelete else {
          return
        }
        
        self.accountToDelete = nil
        
        Task {
          self.selection = nil
          
          if account.persisted {
            do {
              try await self.model.deleteUser(login: account.login)
            }
            catch {
              // The server didn't delete it, so it stays.
              return
            }
          }
          
          self.accounts = self.accounts.filter { $0.id != account.id }
          self.deleteConfirm = false
        }
      }
    }, message: {
      Text("You cannot undo this action.")
    })
    .sheet(item: self.$accountToEdit) { account in
      AccountDetailsView(account: account) { editedAccount in
        if let i = self.accounts.firstIndex(of: editedAccount) {
          self.accounts.remove(at: i)
          self.accounts.insert(editedAccount, at: i)
        }
        self.accounts.sort { $0.name < $1.name }
        self.selection = editedAccount
        self.accountToEdit = nil
      }
      .id(account.id)
      .environment(self.model)
      .frame(width: 480)
      .frame(minHeight: 300, idealHeight: 400)
      .presentationSizing(.fitted)
    }
    .sheet(isPresented: self.$creatorShown) {
      AccountDetailsView { newAccount in
        self.accounts.append(newAccount)
        self.accounts.sort { $0.name < $1.name }
        self.selection = newAccount
      }
      .environment(self.model)
      .frame(width: 480)
      .frame(minHeight: 300, idealHeight: 400)
      .presentationSizing(.fitted)
    }
  }
}


