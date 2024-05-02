import SwiftUI

struct MessageBoardView: View {
  @Environment(Hotline.self) private var model: Hotline
  
  @State private var initialLoadComplete = false
  @State private var composerDisplayed = false
  @State private var composerText = ""
  
  var body: some View {
    NavigationStack {
      if model.access?.contains(.canReadMessageBoard) != false {
        ScrollView {
          LazyVStack(alignment: .leading) {
            ForEach(model.messageBoard, id: \.self) {
              Text(LocalizedStringKey($0.convertLinksToMarkdown()))
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
        VStack {
          Text("No Message Board")
            .bold()
            .foregroundStyle(.secondary)
            .font(.title3)
          Text("This server has the message board turned off.")
            .foregroundStyle(.tertiary)
            .font(.system(size: 13))
        }
        .padding()
      }
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
