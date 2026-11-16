import SwiftUI

struct NewFolderPopover: View {
  @Environment(\.dismiss) private var dismiss
  
  let action: ((String) -> Void)?
  
  @State private var folderName: String = "Untitled Folder"
  
  var body: some View {
    VStack(spacing: 16) {
      TextField("Folder Name", text: self.$folderName)
        .onSubmit(of: .text) {
          self.createFolder()
        }
      
      HStack(spacing: 8) {
        Spacer()
        
        Button("Cancel", role: .cancel) {
          self.dismiss()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        
        Button("New Folder", role: .confirm) {
          self.createFolder()
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
      }
    }
    .frame(width: 250)
    .padding()
  }
  
  private func createFolder() {
    self.dismiss()
    self.action?(self.folderName)
  }
}
