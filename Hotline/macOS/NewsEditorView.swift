import SwiftUI

private enum FocusFields {
  case title
  case body
}

struct NewsEditorView: View {
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @Environment(Hotline.self) private var model: Hotline
  
  let editorTitle: String
  let isReply: Bool
  let path: [String]
  let parentID: UInt32
  
  @State var title: String = ""
  @State private var text: String = ""
  @State private var sending: Bool = false
  
  @FocusState private var focusedField: FocusFields?
  
  func sendArticle() async -> Bool {
    sending = true
    
    let success = await model.postNewsArticle(title: title, body: text, at: path, parentID: parentID)
    if success {
      await model.getNewsList(at: path)
    }
    
    sending = false
    
    return success
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .opacity(0.5)
        }
        .buttonStyle(.plain)
        .frame(width: 16, height: 16)
        
        Spacer()
        
        if !isReply {
          Image("News Category")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .padding(.trailing, 6)
        }
        
        Text(editorTitle)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.middle)
        
        Spacer()
        
        if sending {
          ProgressView()
            .controlSize(.small)
            .frame(width: 22, height: 22)
        }
        else {
          Button {
            Task {
              if await sendArticle() {
                dismiss()
              }
            }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .foregroundColor((title.isEmpty || text.isEmpty) ? .secondary : .accentColor)
          }
          .buttonStyle(.plain)
          .frame(width: 22, height: 22)
          .help("Post to Newsgroup")
          .disabled(title.isEmpty || text.isEmpty)
        }
      }
      .frame(maxWidth: .infinity)
      .padding([.leading, .top, .trailing])
      
      TextField("Title", text: $title, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(3)
        .padding()
        .focusEffectDisabled()
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity)
        .border(Color.pink, width: 0)
        .background(.tertiary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
        .focused($focusedField, equals: .title)
      
      Divider()
      
      TextEditor(text: $text)
        .textEditorStyle(.plain)
        .font(.system(size: 14, design: .monospaced))
        .lineSpacing(3)
        .padding(16)
        .contentMargins(.top, -16.0, for: .scrollIndicators)
        .contentMargins(.bottom, -16.0, for: .scrollIndicators)
        .contentMargins(.trailing, -16.0, for: .scrollIndicators)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .focused($focusedField, equals: .body)
      
      HStack(alignment: .center) {
        Spacer()
        
        Text(String("**bold**  _italics_  [link name](url)  ![image name](url)"))
          .foregroundStyle(.secondary)
          .font(.caption)
          .fontDesign(.monospaced)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding()
        
        Spacer()
      }
      .frame(maxWidth: .infinity)
      .background(.tertiary.opacity(0.15))
    }
    .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity, minHeight: 300, idealHeight: 500, maxHeight: .infinity)
    .background(Color(nsColor: .textBackgroundColor))
    .presentationCompactAdaptation(.sheet)
    .toolbarTitleDisplayMode(.inlineLarge)
    .onAppear {
      if !title.isEmpty {
        focusedField = .body
      }
    }
    .onDisappear {
      dismiss()
    }
  }
}
