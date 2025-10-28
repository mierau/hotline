import SwiftUI

struct GeneralSettingsView: View {
  @State private var username: String = ""
  @State private var usernameChanged: Bool = false
  @State private var showClearHistoryConfirmation: Bool = false
  
  let saveTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
  
  var body: some View {
    @Bindable var preferences = Prefs.shared
    
    Form {
      TextField("Your Name", text: $username, prompt: Text("guest"))
      Toggle("Show Join/Leave in Chat", isOn: $preferences.showJoinLeaveMessages)
      Toggle("Refuse private messages", isOn: $preferences.refusePrivateMessages)
      Toggle("Refuse private chat", isOn: $preferences.refusePrivateChat)
      Toggle("Automatic Response", isOn: $preferences.enableAutomaticMessage)
      if preferences.enableAutomaticMessage {
        TextField("", text: $preferences.automaticMessage, prompt: Text("Write a response message"))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity)
          .onSubmit(of: .text) {
            preferences.username = self.username
          }
      }
      
      Divider()
      
      Button(role: .destructive) {
        showClearHistoryConfirmation = true
      } label: {
        Text("Clear Chat History…")
      }
    }
    .padding()
    .frame(width: 392)
    .confirmationDialog("Clear chat history?", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
      Button("Clear Chat History", role: .destructive) {
        Task {
          await ChatStore.shared.clearAll()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes all saved chat logs across servers. Active chats will repopulate only with new messages.")
    }
    .onAppear {
      self.username = preferences.username
      self.usernameChanged = false
    }
    .onDisappear {
      preferences.username = self.username
      self.usernameChanged = false
    }
    .onChange(of: username) { oldValue, newValue in
      self.usernameChanged = true
    }
    .onReceive(saveTimer) { _ in
      if self.usernameChanged {
        self.usernameChanged = false
        preferences.username = self.username
      }
    }
  }
}
