import SwiftUI

struct MessageBoardView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var composerDisplayed: Bool = false
  @State private var composerText: String = ""
  
  var body: some View {
    NavigationStack {
      if model.access?.contains(.canReadMessageBoard) != false {
        ScrollView {
          LazyVStack(alignment: .leading) {
            ForEach(model.messageBoard, id: \.self) { msg in
              Text(LocalizedStringKey(msg))
                .tint(Color("Link Color"))
                .lineLimit(100)
                .lineSpacing(4)
                .padding()
                .textSelection(.enabled)
              Divider()
            }
          }
          Spacer()
        }
        .task {
          if !model.messageBoardLoaded {
            let _ = await model.getMessageBoard()
          }
        }
        .overlay {
          if !model.messageBoardLoaded {
            VStack {
              ProgressView()
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
          }
        }
        .background(Color(nsColor: .textBackgroundColor))
      }
      else {
        ZStack(alignment: .center) {
          Text("No Message Board")
            .font(.title)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding()
        }
        .frame(maxWidth: .infinity)
      }
    }
    .sheet(isPresented: $composerDisplayed) {
      MessageBoardEditorView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(idealWidth: 450, idealHeight: 350)
//      RichTextEditor(text: $composerText)
//        .richEditorFont(NSFont.systemFont(ofSize: 16.0))
//        .richEditorAutomaticDashSubstitution(false)
//        .richEditorAutomaticQuoteSubstitution(false)
//        .richEditorAutomaticSpellingCorrection(false)
//        .background(Color(nsColor: .textBackgroundColor))
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .frame(idealWidth: 450, idealHeight: 350)
//        .toolbar {
//          ToolbarItem(placement: .cancellationAction) {
//            Button("Cancel") {
//              composerDisplayed.toggle()
//            }
//          }
//          
//          ToolbarItem(placement: .primaryAction) {
//            Button("Post") {
//              composerDisplayed.toggle()
//              let text = composerText
//              composerText = ""
//              model.postToMessageBoard(text: text)
//              Task {
//                await model.getMessageBoard()
//              }
//            }
//          }
//        }
    }
    .toolbar {
      ToolbarItem(placement:.primaryAction) {
        Button {
          composerDisplayed.toggle()
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .disabled(model.access?.contains(.canPostMessageBoard) == false)
        .help("Post to Message Board")
      }
    }
  }
}

#Preview {
  MessageBoardView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
