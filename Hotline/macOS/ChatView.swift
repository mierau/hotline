import SwiftUI

enum FocusedField: Int, Hashable {
  case chatInput
}

struct ChatView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.dismiss) var dismiss
  
  @State var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  
  @FocusState private var focusedField: FocusedField?
  
  @Namespace var bottomID
  
  @State private var showingExporter: Bool = false
  
  @State private var chatDocument: TextFile = TextFile()
    
  var body: some View {
    NavigationStack {
      ScrollViewReader { reader in

        VStack(alignment: .leading, spacing: 0) {
          
          // MARK: Scroll View
          GeometryReader { gm in
            ScrollView(.vertical) {
              LazyVStack(alignment: .leading) {
                  
                ForEach(model.chat) { msg in
                  
                  // MARK: Agreement
                  if msg.type == .agreement {
                    VStack(alignment: .center, spacing: 16) {
                      
                      if let bannerImage = self.model.bannerImage {
                        #if os(macOS)
                        Image(nsImage: bannerImage)
                          .resizable()
                          .scaledToFit()
                          .frame(maxWidth: 468.0)
                          .clipShape(RoundedRectangle(cornerRadius: 3))
                        #elseif os(iOS)
                        Image(uiImage: bannerImage)
                          .resizable()
                          .scaledToFit()
                          .frame(maxWidth: 468.0)
                          .clipShape(RoundedRectangle(cornerRadius: 3))
                        #endif
                      }
                                            
                      VStack(spacing: 0) {
                        ScrollView(.vertical) {
                          HStack {
                            Text(msg.text)
                              .font(.system(size: 12))
                              .fontDesign(.monospaced)
                              .textSelection(.enabled)
                            Spacer()
                          }
                          .padding(16)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: 375)
                      }
                      .background(Color(white: colorScheme == .light ? 0.0 : 1.0).opacity(0.05))
                      .frame(maxWidth: 468.0)
                      .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                  }
                  // MARK: Status
                  else if msg.type == .status {
                    HStack {
                      Spacer()
                      Text(msg.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.disabled)
                        .opacity(0.3)
                      Spacer()
                    }
                    .padding()
                  }
                  else {
                    HStack(alignment: .firstTextBaseline) {
                      if let username = msg.username {
                        Text("**\(username):** \(msg.text)")
                          .lineSpacing(4)
                          .multilineTextAlignment(.leading)
                          .textSelection(.enabled)
                      }
                      else {
                        Text(msg.text)
                          .lineSpacing(4)
                          .multilineTextAlignment(.leading)
                          .textSelection(.enabled)
                      }
                      Spacer()
                    }
                    .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                  }
                }
                EmptyView().id(bottomID)
              }
              //          .padding(.bottom, 12)
            }
            //        .padding(.bottom, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.chat.count) {
//              withAnimation {
              reader.scrollTo(bottomID, anchor: .bottom)
//              }
            }
            .onAppear {
              reader.scrollTo(bottomID, anchor: .bottom)
//              focusedField = .chatInput
            }
            .onChange(of: gm.size) {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
          }
        }
        
        // MARK: Input Divider
        Divider()
          .padding([.top, .bottom], 0)
        
        // MARK: Input Bar
        HStack(alignment: .lastTextBaseline, spacing: 0) {
          TextField("", text: $input, axis: .vertical)
            .focused($focusedField, equals: .chatInput)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .multilineTextAlignment(.leading)
//            .frame(maxWidth: .infinity)
            .onSubmit {
              if !self.input.isEmpty {
                model.sendChat(self.input)
              }
              self.input = ""
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .overlay(alignment: .leadingLastTextBaseline) {
          Image(systemName: "chevron.right").opacity(0.4).offset(x: 16)
        }
        .onContinuousHover { phase in
          switch phase {
          case .active(_):
            NSCursor.iBeam.set()
          case .ended:
            NSCursor.arrow.set()
            break
          }
        }
        .onTapGesture {
          focusedField = .chatInput
        }
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          if prepareChatDocument() {
            showingExporter = true
          }
        } label: {
          Image(systemName: "square.and.arrow.up")
        }.help("Save Chat...")
      }
    }
    .fileExporter(isPresented: $showingExporter, document: self.chatDocument, contentType: .utf8PlainText, defaultFilename: "\(self.model.serverTitle) Chat.txt") { result in
      switch result {
      case .success(let url):
        print("Saved to \(url)")
        
      case .failure(let error):
        print(error.localizedDescription)
      }
      self.chatDocument.text = ""
    }
  }
  
  private func prepareChatDocument() -> Bool {
    var text: String = String()
    
    self.chatDocument.text = ""
    for msg in model.chat {
      if msg.type == .agreement {
        text.append(msg.text)
        text.append("\n\n")
      }
      else if msg.type == .message {
        if let username = msg.username {
          text.append("\(username): \(msg.text)")
        }
        else {
          text.append(msg.text)
        }
        text.append("\n")
      }
      else if msg.type == .status {
        text.append(msg.text)
        text.append("\n")
      }
    }
    
    if text.isEmpty {
      return false
    }
    
    self.chatDocument.text = text
    
    return true
  }
}

#Preview {
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
