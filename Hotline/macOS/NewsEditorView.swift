import SwiftUI
import UniformTypeIdentifiers

struct NewsEditorView: View {
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @Environment(Hotline.self) private var model: Hotline
  
//  @Binding var article: NewsArticle?
  @State var title: String = ""
  @State var text: String = ""
  
  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .resizable()
              .scaledToFit()
          }
          .buttonStyle(.plain)
          .frame(width: 16, height: 16)
          .padding()
          
          Spacer()
          
          Button {
          } label: {
            Image(systemName: "paperplane")
              .resizable()
              .scaledToFit()
          }
          .buttonStyle(.plain)
          .frame(width: 16, height: 16)
          .padding()
        }
        .frame(maxWidth: .infinity)
        TextField("Title", text: $title, axis: .vertical)
          .textFieldStyle(.plain)
          .padding()
          .focusEffectDisabled()
          .font(.title)
          .frame(maxWidth: .infinity)
          .border(Color.pink, width: 0)
        Divider()
        TextEditor(text: $text)
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
    }
    .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity, minHeight: 300, idealHeight: 500, maxHeight: .infinity)
    .background(Color(nsColor: .textBackgroundColor))
    .presentationCompactAdaptation(.sheet)
    .toolbarTitleDisplayMode(.inlineLarge)
//    .toolbar {
//      ToolbarItem(placement: .navigation) {
//        Button("Post", action: {})
//      }
//      ToolbarItem(placement: .automatic) {
//        Button("Delete", action: {
//          dismiss()
//        })
//      }
//    }
    .task {
//      if let info = info {
//        preview = FilePreview(info: info)
//        preview?.download()
//      }
    }
    .onAppear {
//      if info == nil {
//        Task {
//          dismiss()
//        }
//        return
//      }
    }
    .onDisappear {
//      preview?.cancel()
      dismiss()
    }
//    .onChange(of: preview?.state) {
//      if preview?.state == .failed {
//        dismiss()
//      }
//    }
  }
}
