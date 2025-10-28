import SwiftUI

struct SoundSettingsView: View {
  var body: some View {
    @Bindable var preferences = Prefs.shared
    
    Form {
      Toggle("Enable Sounds", isOn: $preferences.playSounds)
        .controlSize(.large)
      
      Section("Sounds") {
        Toggle("Chat", isOn: $preferences.playChatSound)
          .disabled(!preferences.playSounds)
        
        Toggle("File Transfers", isOn: $preferences.playFileTransferCompleteSound)
          .disabled(!preferences.playSounds)
        
        Toggle("Private Message", isOn: $preferences.playPrivateMessageSound)
          .disabled(!preferences.playSounds)
        
        Toggle("Join", isOn: $preferences.playJoinSound)
          .disabled(!preferences.playSounds)
        
        Toggle("Leave", isOn: $preferences.playLeaveSound)
          .disabled(!preferences.playSounds)
        
        Toggle("Logged in", isOn: $preferences.playLoggedInSound)
          .disabled(!preferences.playSounds)
        
        Toggle("Error", isOn: $preferences.playErrorSound)
          .disabled(!preferences.playSounds)
        
        Toggle("Chat Invitation", isOn: $preferences.playChatInvitationSound)
          .disabled(!preferences.playSounds)
      }
    }
    .formStyle(.grouped)
    .frame(width: 392, height: 433)
  }
}
