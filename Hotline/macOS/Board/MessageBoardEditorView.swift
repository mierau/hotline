import SwiftUI

private enum FocusFields {
  case body
}

struct MessageBoardEditorView: View {
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @Environment(Hotline.self) private var model: Hotline
    
  @State private var text: String = ""
  @State private var sending: Bool = false
  
  @FocusState private var focusedField: FocusFields?
  
  func sendPost() async {
    sending = true
    
    let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    
    model.postToMessageBoard(text: cleanedText)
    let _ = await model.getMessageBoard()
    
//    let success = await model.postNewsArticle(title: title, body: text, at: path, parentID: parentID)
//    if success {
//      await model.getNewsList(at: path)
//    }
    
    sending = false
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
        
//        Image("Message Board Post")
//          .resizable()
//          .scaledToFit()
//          .frame(width: 16, height: 16)
//          .padding(.trailing, 6)
        
        Text("New Post")
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
            sending = true
            model.postToMessageBoard(text: text)
            Task {
              let _ = await model.getMessageBoard()
              Task { @MainActor in
                sending = false
                dismiss()
              }
            }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
          }
          .buttonStyle(.plain)
          .frame(width: 22, height: 22)
          .help("Post to Message Board")
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .frame(maxWidth: .infinity)
      .padding()
      
      Divider()
      
      BetterTextEditor(text: $text)
        .betterEditorFont(NSFont.systemFont(ofSize: 14.0))
        .betterEditorAutomaticSpellingCorrection(true)
        .betterEditorTextInset(.init(width: 16, height: 18))
        .lineSpacing(20)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focused($focusedField, equals: .body)
    }
    .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity, minHeight: 300, idealHeight: 500, maxHeight: .infinity)
    .background(Color(nsColor: .textBackgroundColor))
    .presentationCompactAdaptation(.sheet)
    .onAppear {
      focusedField = .body
    }
    .onDisappear {
      dismiss()
    }
  }
}
