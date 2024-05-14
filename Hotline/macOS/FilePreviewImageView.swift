import SwiftUI
import UniformTypeIdentifiers

struct FilePreviewImageView: View {
  enum FilePreviewFocus: Hashable {
    case window
  }
  
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) var dismiss
  
  @Binding var info: PreviewFileInfo?
  
  @State var preview: FilePreview? = nil
  @FocusState private var focusField: FilePreviewFocus?
  
  var body: some View {
    Group {
      if preview?.state != .loaded {
        HStack(alignment: .center, spacing: 0) {
          ProgressView(value: max(0.0, min(1.0, preview?.progress ?? 0.0)))
            .focusable(false)
            .progressViewStyle(.circular)
            .controlSize(.extraLarge)
            .tint(.white)
            .frame(maxWidth: 300, alignment: .center)
        }
        .frame(minWidth: 350, maxWidth: 350, minHeight: 150, maxHeight: 150)
        .padding()
      }
      else {
        if let image = preview?.image {
          FileImageView(image: image)
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        }
        else {
          VStack(alignment: .center, spacing: 0) {
            Spacer()
            
            Image(systemName: "eye.trianglebadge.exclamationmark")
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .padding(.bottom)
            Group {
              Text("This file type is not previewable")
                .bold()
              Text("Try downloading and opening this file in another application.")
                .foregroundStyle(Color.secondary)
            }
            .font(.system(size: 14.0))
            .frame(maxWidth: 300)
            .multilineTextAlignment(.center)
            
            Spacer()
          }
          .frame(minWidth: 350, maxWidth: 350, minHeight: 150, maxHeight: 150)
          .padding()
        }
      }
    }
    .focusable()
    .focusEffectDisabled()
    .focused($focusField, equals: .window)
    .preferredColorScheme(.dark)
    .navigationTitle(info?.name ?? "Preview")
    .background(.black)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        FileIconView(filename: info?.name ?? "")
          .frame(width: 16, height: 16)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
      
      if let img = preview?.image {
        if let info = info {
          ToolbarItem(placement: .primaryAction) {
            Button {
              let _ = preview?.data?.saveAsFileToDownloads(filename: info.name)
            } label: {
              Label("Download Image...", systemImage: "arrow.down")
            }
            .help("Download Image")
          }
          
          ToolbarItem(placement: .primaryAction) {
            ShareLink(item: img, preview: SharePreview(info.name, image: img)) {
              Label("Share Image...", systemImage: "square.and.arrow.up")
            }
            .help("Share Image")
          }
        }
      }
    }
    .task {
      if let info = info {
        preview = FilePreview(info: info)
        preview?.download()
      }
    }
    .onAppear {
      if info == nil {
        Task {
          dismiss()
        }
        return
      }
      
      focusField = .window
    }
    .onDisappear {
      preview?.cancel()
      dismiss()
    }
    .onChange(of: preview?.state) {
      if preview?.state == .failed {
        dismiss()
      }
    }
  }
}
