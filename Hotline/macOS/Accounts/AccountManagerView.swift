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
  /// For the selected account's buttons to be drawn as one piece of glass.
  @Namespace private var glass
  
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
      self.header
        .padding(.horizontal, 16)
        .padding(.top, 20)
      
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
  
  /// How many there are, once they've come.
  private var summary: Text {
    guard !self.loading else {
      return Text("Loading accounts…")
    }
    return Text("^[\(self.accounts.count) account](inflect: true)")
  }
  
  /// What the sheet's for, and how many there are, with what can be done to them across from it, as
  /// a toolbar has it: the selected one's, edited or deleted, together in one piece, as they're both
  /// for it, in the text's color, as a toolbar's symbols are, and last, at the edge, a new one, in
  /// glass of its own in the accent, as a default button is.
  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Accounts")
          .font(.headline)
        self.summary
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      
      Spacer(minLength: 0)
      
      AccountHeaderGlass(spacing: AccountHeaderButtonStyle.spacing) {
        HStack(spacing: AccountHeaderButtonStyle.spacing) {
          HStack(spacing: 0) {
            Button {
              if let account = self.selection {
                self.editAccount(account)
              }
            } label: {
              Image(systemName: "pencil")
            }
            .buttonStyle(AccountHeaderButtonStyle(joined: "selected", in: self.glass))
            .help("Edit Account")
            
            Button {
              if let account = self.selection {
                self.deleteAccount(account)
              }
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(AccountHeaderButtonStyle(joined: "selected", in: self.glass))
            .help("Delete Account")
          }
          .disabled(self.selection == nil)
          .accountHeaderJoined()
          
          Button {
            self.newAccount()
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(AccountHeaderButtonStyle(prominent: true))
          .help("New Account")
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
      // Its login in from the row's right edge, about as far as its icon is from its left.
      .padding(.trailing, 4)
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

// MARK: - Header Buttons

/// A symbol's button in the accounts' header, as a toolbar's are from macOS 26: round Liquid Glass
/// that gives as it's clicked, or joined with the buttons beside it that share its `joined` into one
/// piece, in the text's color, and faint when it can't be clicked. Prominent, it's glass in the
/// accent, or a server's theme's, with a white symbol, as a default button is. Before macOS 26, the
/// symbol alone, on the accent, or on a gray its group puts behind it.
private struct AccountHeaderButtonStyle: ButtonStyle {
  /// How big each button is, across and down.
  static let size: CGFloat = 32
  /// The room between a button on its own and the buttons joined beside it.
  static let spacing: CGFloat = 8

  var prominent = false
  var joined: String? = nil
  var namespace: Namespace.ID? = nil

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.serverTheme) private var theme

  init(prominent: Bool = false) {
    self.prominent = prominent
  }

  init(joined: String, in namespace: Namespace.ID) {
    self.joined = joined
    self.namespace = namespace
  }

  /// The accent, as the server's theme has it, or the system's.
  private var accent: Color {
    self.theme?.accent.map { Color(nsColor: $0) } ?? .accentColor
  }

  @ViewBuilder
  func makeBody(configuration: Configuration) -> some View {
    // Plain when it can't be clicked, as glassProminent is.
    let tinted = self.prominent && self.isEnabled
    let label = configuration.label
      .font(.system(size: 14, weight: tinted ? .semibold : .medium))
      .foregroundStyle(tinted ? AnyShapeStyle(.white) : self.isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
      .frame(width: Self.size, height: Self.size)
      .contentShape(.capsule)
    if #available(macOS 26, *) {
      // Giving as it's clicked only when it can be.
      let glass = label.glassEffect(tinted ? .regular.tint(self.accent).interactive() : self.isEnabled ? .regular.interactive() : .regular, in: .capsule)
      if let joined = self.joined, let namespace = self.namespace {
        glass.glassEffectUnion(id: joined, namespace: namespace)
      }
      else {
        glass
      }
    }
    else {
      label
        .background {
          if tinted {
            Circle().fill(self.accent)
          }
          else if self.joined == nil {
            Circle().fill(.quaternary)
          }
        }
        .opacity(configuration.isPressed ? 0.6 : 1)
    }
  }
}

/// The header's glass, drawn together, from macOS 26, as glass can't show the glass beside it.
private struct AccountHeaderGlass<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    if #available(macOS 26, *) {
      GlassEffectContainer(spacing: self.spacing) {
        self.content
      }
    }
    else {
      self.content
    }
  }
}

private extension View {
  /// Buttons joined into one piece: their glass is from macOS 26, and before, a gray capsule behind
  /// them all.
  @ViewBuilder
  func accountHeaderJoined() -> some View {
    if #available(macOS 26, *) {
      self
    }
    else {
      self.background(.quaternary, in: .capsule)
    }
  }
}
