import SwiftUI

enum FileImageViewStatus {
  case notloaded
  case loading
  case loaded
}

enum FileImageType {
  case banner
  case file
}

struct FileImageView: View {
  @Environment(Hotline.self) private var model: Hotline
  @State var status: FileImageViewStatus = .notloaded
  
  @MainActor func startLoading() {
    if self.status != .notloaded {
      return
    }
    
    self.status = .loading
    self.model.downloadBanner { success in
      if success {
        self.status = .loaded
      }
      else {
        self.status = .notloaded
      }
    }
  }
  
  var body: some View {
    HStack(spacing: 0) {
      if let img = self.model.bannerImage {
        #if os(macOS)
        Image(nsImage: img)
          .resizable()
          .scaledToFit()
        #elseif os(iOS)
        Image(uiImage: img)
          .resizable()
          .scaledToFit()
        #endif
      }
    }
    .task {
      self.startLoading()
    }
  }
}

#Preview {
  FileImageView()
}
