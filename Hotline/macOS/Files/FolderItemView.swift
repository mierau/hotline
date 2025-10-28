import SwiftUI

struct FolderItemView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State var loading = false
  @State var dragOver = false
  
  var file: FileInfo
  let depth: Int
  
  @MainActor private func uploadFile(file fileURL: URL) {
    var filePath: [String] = [String](self.file.path)
    if !self.file.isFolder {
      filePath.removeLast()
    }
    
    print("UPLOADING TO PATH: ", filePath)
    
    model.uploadFile(url: fileURL, path: filePath) { info in
      Task {
        // Refresh file listing to display newly uploaded file.
        let _ = await model.getFileList(path: filePath)
      }
    }
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Spacer()
        .frame(width: CGFloat(depth * (12 + 2)))
      
      Button {
        if file.isFolder {
          file.expanded.toggle()
        }
      } label: {
        Text(Image(systemName: file.expanded ? "chevron.down" : "chevron.right"))
          .bold()
          .font(.system(size: 10))
          .foregroundStyle(dragOver ? Color.white : Color.primary)
          .opacity(0.5)
      }
      .buttonStyle(.plain)
      .frame(width: 10)
      .padding(.leading, 4)
      .padding(.trailing, 8)
      
      HStack(alignment: .center) {
        if file.isUnavailable {
          Image(systemName: "questionmark.app.fill")
            .frame(width: 16, height: 16)
            .opacity(0.5)
        }
        else if file.isAdminDropboxFolder {
          Image("Admin Drop Box")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else if file.isDropboxFolder {
          Image("Drop Box")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        else {
          Image("Folder")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
      }
      .frame(width: 16)
      .padding(.trailing, 6)
      
      Text(file.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(dragOver ? Color.white : Color.primary)
        .opacity(file.isUnavailable ? 0.5 : 1.0)
      
      if loading {
        ProgressView().controlSize(.small).padding([.leading, .trailing], 5)
      }
      Spacer()
      if !file.isUnavailable {
        Text(file.fileSize == 0 ? "Empty" : "^[\(file.fileSize) \("file")](inflect: true)")
          .foregroundStyle(dragOver ? Color.white.opacity(0.75) : Color.secondary)
          .lineLimit(1)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 4.0)
        .fill(dragOver ? Color(nsColor: NSColor.selectedContentBackgroundColor) : Color.clear)
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
    )
    .onChange(of: file.expanded) {
      loading = false
      if file.expanded && file.fileSize > 0 {
        Task {
          loading = true
          let _ = await model.getFileList(path: file.path)
          loading = false
        }
      }
    }
    .onDrop(of: [.fileURL], isTargeted: $dragOver) { items in
      guard let item = items.first,
            let identifier = item.registeredTypeIdentifiers.first else {
        return false
      }
      
      item.loadItem(forTypeIdentifier: identifier, options: nil) { (urlData, error) in
        DispatchQueue.main.async {
          if let urlData = urlData as? Data,
             let fileURL = URL(dataRepresentation: urlData, relativeTo: nil, isAbsolute: true) {
            uploadFile(file: fileURL)
          }
        }
      }
      
      return true
    }
    
    if file.expanded {
      ForEach(file.children!, id: \.self) { childFile in
        if childFile.isFolder {
          FolderItemView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
        else {
          FileItemView(file: childFile, depth: self.depth + 1).tag(file.id)
        }
      }
    }
  }
}
