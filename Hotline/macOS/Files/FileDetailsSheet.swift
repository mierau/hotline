import Foundation
import SwiftUI

struct FileDetailsSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  var details: FileDetails
  
  @State private var saving: Bool = false
  @State private var comment: String = ""
  @State private var filename: String = ""
  
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 16){
        if self.isFolder {
          FolderIconView()
            .frame(width: 32, height: 32)
        }
        else {
          FileIconView(filename: self.details.name, fileType: nil)
            .frame(width: 32, height: 32)
        }
        
        TextField("File Name", text: $filename)
          .disabled(!self.canRename)
      }
      
      let rows: [(String, String)] = [
        ("Type", self.details.type),
        ("Creator", self.details.creator),
        ("Size", self.formattedSize(byteCount: self.details.size)),
        ("Created", Self.dateFormatter.string(from: self.details.created)),
        ("Modified", Self.dateFormatter.string(from: self.details.modified))
      ]
      
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
        ForEach(rows, id: \.0) { label, value in
          GridRow {
            Text(label)
              .font(.body.bold())
              .gridColumnAlignment(.trailing) // right-align label column
            Text(value)
              .font(.body)
              .gridColumnAlignment(.leading)  // left-align value column
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 32 + 16)
      
      TextField(text: self.$comment, prompt: Text("Comments"), axis: .vertical) {
        EmptyView()
      }
      .font(.body)
      .lineLimit(10, reservesSpace: true)
      .padding(.leading, 32 + 16)
      .disabled(!self.canSetComment)
    }
    .padding(.vertical, 24)
    .padding(.horizontal, 24)
    .frame(width: 400)
    .toolbar {
      if self.saving {
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
      
      ToolbarItem(placement: .primaryAction) {
        Button{
          var editedFilename: String?
          if self.filename != self.details.name {
            editedFilename = self.filename
          }
          
          var editedComment: String?
          if self.comment != self.details.comment {
            editedComment = self.comment
          }
          
          Task {
            self.saving = true
            defer { self.saving = false }
            
            if editedComment != nil || editedFilename != nil {
              do {
                if try await self.model.setFileInfo(fileName: self.details.name, path: self.details.path, fileNewName: editedFilename, comment: editedComment) {
                  try await self.model.getFileList(path: self.details.path)
                }
              }
              catch {
                // SwiftUI doesn't show the server's error alert above this sheet, so the sheet
                // stays open instead, with the new name or comment still in it to try again.
                return
              }
            }
            
            self.dismiss()
          }
        } label: {
          Text("Save")
        }
      }
    }
    .onAppear {
      self.filename = self.details.name
      self.comment = self.details.comment
    }
  }
  
  private var isFolder: Bool {
    self.details.type == "Folder" || self.details.type == "fldr"
  }
  
  private func isEdited() -> Bool {
    return self.filename != self.details.name || self.comment != self.details.comment
  }
  
  private var canRename: Bool {
    if self.isFolder {
      return self.model.access?.contains(.canRenameFolders) == true
    }
    return self.model.access?.contains(.canRenameFiles) == true
  }
  
  private var canSetComment: Bool {
    if self.isFolder {
      return self.model.access?.contains(.canSetFolderComment) == true
    }
    return self.model.access?.contains(.canSetFileComment) == true
  }
  
  static var dateFormatter: DateFormatter = {
    var dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .long
    dateFormatter.timeStyle = .short
    
    // Original format: Fri, Aug 20, 2021, 5:14:07 PM
    return dateFormatter
  }()
  
  static var byteCountSizeFormatter: NumberFormatter = {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    return numberFormatter
  }()
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt) -> String {
    FileItemView.byteFormatter.allowedUnits = [.useAll]
    FileItemView.byteFormatter.countStyle = .file
    return FileItemView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
  
  // Format byte count Int into string like: 23.4M (24,601,664 bytes)
  private func formattedSize(byteCount: Int) -> String {
    let formattedByteCount = Self.byteCountSizeFormatter.string(from: NSNumber(value:byteCount)) ?? "0"
    return "\(FileItemView.byteFormatter.string(fromByteCount: Int64(byteCount))) (\(formattedByteCount) bytes)"
  }
}

//#Preview {
//  FileDetailsView(details: FileDetails(name: "AppleWorks 6.sit", path: [""], size: 24601664, comment: "test comment", type: "SITD", creator: "SIT!", created: Date.now, modified: Date.now ))
//}
