import SwiftUI
import UniformTypeIdentifiers

struct FileView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State var file: HotlineFile
  @State var loaded = false
  @State var fileList: [HotlineFile] = []
  
  let depth: Int
  let path: [String]
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt32) -> String {
    //    let bcf = ByteCountFormatter()
    FileView.byteFormatter.allowedUnits = [.useAll]
    FileView.byteFormatter.countStyle = .file
    return FileView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
  
  private func fileIcon(name: String) -> UIImage {
    //    func utTypeForFilename(_ filename: String) -> UTType? {
    let fileExtension = (name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      print("\(name) \(fileExtension) = \(fileType)")
      
      if fileType.isSubtype(of: .movie) {
        return UIImage(systemName: "play.rectangle")!
      }
      else if fileType.isSubtype(of: .image) {
        return UIImage(systemName: "photo")!
      }
      else if fileType.isSubtype(of: .archive) {
        return UIImage(systemName: "doc.zipper")!
      }
      else if fileType.isSubtype(of: .text) {
        return UIImage(systemName: "doc.text")!
      }
      else {
        return UIImage(systemName: "doc")!
      }
    }
    
    return UIImage(systemName: "doc")!
  }
  
  var body: some View {
    if file.isFolder {
      DisclosureGroup {
        if !loaded {
          Text("Loading...")
            .task {
              if !loaded {
                hotline.sendGetFileList(path: path) {
                  print("FETCHED!")
                } reply: { newFiles in
                  print("GOT FILES REPLY?", newFiles)
                  
                  fileList = newFiles
                  loaded = true
                }
              }
            }
        }
        else {
          FileListView(fileList: fileList, depth: depth + 1, path: path + [file.name])
        }
      } label: {
        VStack {
          HStack {
            HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
              Image(systemName: "folder.fill")
            }
            .frame(minWidth: 25)
            Text(file.name).fontWeight(.medium)
            Spacer()
            Text("\(file.fileSize)").foregroundStyle(.secondary)
          }
        }
        .frame(height: 44)
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        
        //            Divider()
        //              .padding(EdgeInsets(top: 0, leading: 16 + 25 + 8, bottom: 0, trailing: 0))
      }
      .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: depth == 0 ? 16 : 0))
      .background(Color(uiColor: UIColor.systemBackground))
    }
    else {
      VStack {
        HStack {
          HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
            Image(uiImage: fileIcon(name: file.name))
              .renderingMode(.template)
              .foregroundColor(.accentColor)
          }
          .frame(minWidth: 25)
          Text(file.name)
          Spacer()
          Text(formattedFileSize(file.fileSize)).foregroundStyle(.gray)
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
      }
      .frame(height: 44)
      .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: depth == 0 ? 16 : 0))
      .background(Color(uiColor: UIColor.systemBackground))
      
      Divider()
        .padding(EdgeInsets(top: 0, leading: 16 + 25 + 8, bottom: 0, trailing: 0))
    }
  }
}

struct FileListView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State private var fetched = false
  @State private var loaded = false
  @State var fileList: [HotlineFile] = []
  @State var expanded = false
  
  var depth = 0
  
  var path: [String] = []
  
  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      Section {
        ForEach(fileList, id: \.self) { file in
          FileView(file: file, depth: depth, path: path + [file.name])
        }
      }
      Spacer()
    }
    .listStyle(.plain)
    .animation(.default, value: fileList)
  }
}

struct BestFileView: View {
  @Environment(HotlineClient.self) private var hotline
  
  @State var expanded = false
  
  var file: HotlineFile
  
  var body: some View {
    if file.isFolder {
      DisclosureGroup(isExpanded: $expanded) {
        ForEach(file.files!) { childFile in
          BestFileView(file: childFile)
            .frame(height: 44)
        }
      } label: {
        HStack {
          HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
            Image(systemName: "folder.fill")
          }
          .frame(minWidth: 25)
          Text(file.name).fontWeight(.medium)
          Spacer()
          Text("\(file.fileSize)").foregroundStyle(.secondary)
        }
      }
      .onChange(of: expanded) {
        print("EXPANDED CHANGED")
        
        hotline.sendGetFileList(path: file.path)
      }
    }
    else {
      HStack {
        HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
          Image(uiImage: fileIcon(name: file.name))
        }
        .frame(minWidth: 25)
        Text(file.name).fontWeight(.medium)
        Spacer()
        Text(formattedFileSize(file.fileSize)).foregroundStyle(.secondary)
      }
    }
  }
  
  static let byteFormatter = ByteCountFormatter()
  
  private func formattedFileSize(_ fileSize: UInt32) -> String {
    //    let bcf = ByteCountFormatter()
    BestFileView.byteFormatter.allowedUnits = [.useAll]
    BestFileView.byteFormatter.countStyle = .file
    return BestFileView.byteFormatter.string(fromByteCount: Int64(fileSize))
  }
  
  private func fileIcon(name: String) -> UIImage {
    //    func utTypeForFilename(_ filename: String) -> UTType? {
    let fileExtension = (name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      print("\(name) \(fileExtension) = \(fileType)")
      
      if fileType.isSubtype(of: .movie) {
        return UIImage(systemName: "play.rectangle")!
      }
      else if fileType.isSubtype(of: .image) {
        return UIImage(systemName: "photo")!
      }
      else if fileType.isSubtype(of: .archive) {
        return UIImage(systemName: "doc.zipper")!
      }
      else if fileType.isSubtype(of: .text) {
        return UIImage(systemName: "doc.text")!
      }
      else {
        return UIImage(systemName: "doc")!
      }
    }
    
    return UIImage(systemName: "doc")!
  }
}

struct FilesView: View {
  @Environment(HotlineClient.self) private var hotline
    
  @State var initialLoad = false
  
  var body: some View {
    NavigationStack {
      List(hotline.fileList) { file in
//        OutlineGroup(hotline.fileList, children: \.files, expanded: $expandedFolders) { file in
        BestFileView(file: file)
          .frame(height: 44)
//        }
      }
      .task {
        if !initialLoad {
          hotline.sendGetFileList(path: []) {
            initialLoad = true
          }
        }
      }
      .listStyle(.plain)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(hotline.server?.name ?? "")
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            hotline.disconnect()
          } label: {
            Text(Image(systemName: "xmark.circle.fill"))
              .symbolRenderingMode(.hierarchical)
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }
}

#Preview {
  FilesView()
    .environment(HotlineClient())
}
