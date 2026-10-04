import SwiftUI

fileprivate let CHARACTER_LIMIT: Int = 255

struct BroadcastMessageSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss
  
  @State private var sending: Bool = false
  
  private var message: String {
    self.model.broadcastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  var body: some View {
    @Bindable var model = self.model
    
    VStack {
      TextField("Write a message...", text: $model.broadcastMessage, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(5, reservesSpace: true)
    }
    .padding(.leading, 32)
    .padding(.top, 2)
    .overlay(alignment: .topLeading) {
      Image("Server Message")
    }
    .padding(16)
    .frame(width: 400)
    .toolbar {
      if self.sending {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }
      
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }
      
      ToolbarItem(placement: .confirmationAction) {
        Button("Broadcast") {
          let message = self.message
          model.broadcastMessage = ""
          
          guard !message.isBlank else {
            return
          }
          
          Task {
            self.sending = true
            defer { self.sending = false }
            
            do {
              try await model.sendBroadcast(message)
              self.dismiss()
            }
            catch {
              // It didn't go out, so the sheet stays open to try again.
            }
          }
        }
        .disabled(self.message.isEmpty)
      }
    }
  }
}
