import SwiftUI

struct MessageBoardView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var initialLoadComplete = false
  @State private var composerDisplayed = false
  @State private var composerText = ""
  
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading) {
          ForEach(model.messageBoard, id: \.self) {
            Text($0)
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
    .sheet(isPresented: $composerDisplayed) {
      TextEditor(text: $composerText)
        .padding()
        .font(.system(size: 13))
        .lineSpacing(4)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(idealWidth: 450, idealHeight: 350)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              composerDisplayed.toggle()
            }
          }
          
          ToolbarItem(placement: .primaryAction) {
            Button("Post") {
              composerDisplayed.toggle()
              let text = composerText
              composerText = ""
              model.postToMessageBoard(text: text)
              Task {
                await model.getMessageBoard()
              }
            }
          }
        }
    }
    .toolbar {
      ToolbarItem(placement:.primaryAction) {
        Button {
          composerDisplayed.toggle()
        } label: {
          Image(systemName: "square.and.pencil")
        }
      }
    }
  }
}

#Preview {
  MessageBoardView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
