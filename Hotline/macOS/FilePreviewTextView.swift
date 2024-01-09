import SwiftUI
import UniformTypeIdentifiers

struct FilePreviewTextView: View {
  enum FilePreviewFocus: Hashable {
    case window
  }
  
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) var dismiss
  
  @Binding var info: PreviewFileInfo?
  @State var preview: FilePreview? = nil
  @Namespace var mainNamespace
  @FocusState private var focusField: FilePreviewFocus?
  
  var body: some View {
    Group {
      if preview?.state != .loaded {
        VStack(alignment: .center, spacing: 0) {
          Spacer()
          ProgressView(value: max(0.0, min(1.0, preview?.progress ?? 0.0)))
            .focusable(false)
            .progressViewStyle(.circular)
            .controlSize(.extraLarge)
            .tint(.white)
            .frame(maxWidth: 300, alignment: .center)
          Spacer()
          Spacer()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 350, maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        .padding()
      }
      else {
        if let text = preview?.text {
          TextEditor(text: .constant(text))
            .textEditorStyle(.plain)
            .font(.system(size: 14))
            .lineSpacing(3)
            .padding(16)
            .contentMargins(.top, -16.0, for: .scrollIndicators)
            .contentMargins(.bottom, -16.0, for: .scrollIndicators)
            .contentMargins(.trailing, -16.0, for: .scrollIndicators)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Spacer()
          }
          .frame(minWidth: 350, maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
          .padding()
        }
      }
    }
    .focusable()
    .focusEffectDisabled()
    .background(Color(nsColor: .textBackgroundColor))
    .focused($focusField, equals: .window)
    .navigationTitle(info?.name ?? "File Preview")
    .toolbar {
      ToolbarItem(placement: .navigation) {
        FileIconView(filename: info?.name ?? "")
          .frame(width: 16, height: 16)
          .opacity(controlActiveState == .inactive ? 0.5 : 1.0)
      }
      
      if let _ = preview?.text {
        if let info = info {
          ToolbarItem(placement: .primaryAction) {
            Button {
              let _ = preview?.data?.saveAsFileToDownloads(filename: info.name)
            } label: {
              Label("Save Text File...", systemImage: "square.and.arrow.down")
            }
            .help("Save Text File")
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
