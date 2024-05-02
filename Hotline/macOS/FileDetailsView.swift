import Foundation
import SwiftUI

struct FileDetailsView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.presentationMode) var presentationMode

  var fd: FileDetails
  
  @State private var comment: String = ""
  @State private var filename: String = ""
  
  var body: some View {
    VStack (alignment: .leading){
      Form {
        HStack(alignment: .center){
          FileIconView(filename: fd.name)
            .frame(width: 16, height: 16)
          TextField("", text: $filename)
            .disabled(!self.canRename())
        }
        HStack(alignment: .center){
          Text("Type:").bold().padding(.leading, 43)
          Text(fd.type)
        }
        HStack(alignment: .center){
          Text("Creator:").bold().padding(.leading, 26)
          Text(fd.creator)
        }
        HStack(alignment: .center){
          Text("Size:").bold().bold().padding(.leading, 48)
          Text(self.formattedSize(byteCount: fd.size))
        }
        HStack(alignment: .center){
          Text("Created:").bold().padding(.leading, 24)
          Text("\(FileDetailsView.dateFormatter.string(from: fd.created))")
        }
        HStack(alignment: .center){
          Text("Modified:").bold().padding(.leading, 19)
          Text("\(FileDetailsView.dateFormatter.string(from: fd.modified))")
        }
        HStack(alignment: .center){
          Text("Comments:").bold().padding(.top, 8)
            .padding(.leading, 5)
        }
        
        VStack(alignment: .trailing){
          TextEditor(text: $comment)
            .padding(.leading, 2)
            .padding(.top, 1)
            .font(.system(size: 13))
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color.secondary, width: 1)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .disabled(!self.canSetComment())
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            presentationMode.wrappedValue.dismiss()
          }
        }
        
        ToolbarItem(placement: .primaryAction) {
          Button{
            var editedFilename: String?
            if filename != fd.name {
              editedFilename = filename
            }
            
            var editedComment: String?
            if comment != fd.comment {
              editedComment = comment
            }
            
            model.client.sendSetFileInfo(fileName: fd.name, path: fd.path, fileNewName: editedFilename, comment: editedComment)
            presentationMode.wrappedValue.dismiss()
            
            // TODO: Update the file list if the filename was changed
          } label: {
            Text("Save")
          }.disabled(!isEdited())
        }
      }

      .onAppear {
        self.filename = fd.name
        self.comment = fd.comment
      }
      .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
    }
    .frame(minWidth: 400, minHeight: 400)
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
    FileView.byteFormatter.allowedUnits = [.useAll]
    FileView.byteFormatter.countStyle = .file
    return FileView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
  
  // Format byte count Int into string like: 23.4M (24,601,664 bytes)
  private func formattedSize(byteCount: Int) -> String {
    let formattedByteCount = FileDetailsView.byteCountSizeFormatter.string(from: NSNumber(value:byteCount)) ?? "0"
    return "\(FileView.byteFormatter.string(fromByteCount: Int64(byteCount))) (\(formattedByteCount) bytes)"
  }
  
  private func isEdited() -> Bool {
    return self.filename != fd.name || self.comment != fd.comment
  }
  
  private func canRename() -> Bool {
    if self.fd.type == "fldr" {
      return model.access?.contains(.canRenameFolders) == true
    }
    return model.access?.contains(.canRenameFiles) == true
  }
  
  private func canSetComment() -> Bool {
    if self.fd.type == "fldr" {
      return model.access?.contains(.canSetFolderComment) == true
    }
    return model.access?.contains(.canSetFileComment) == true
  }
}

//#Preview {
//  FileDetailsView(fd: FileDetails(name: "AppleWorks 6.sit", path: [""], size: 24601664, comment: "test comment", type: "SITD", creator: "SIT!", created: Date.now, modified: Date.now ))
//}
