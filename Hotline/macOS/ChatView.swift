import SwiftUI

enum FocusedField: Int, Hashable {
  case chatInput
}

struct ChatJoinedMessageView: View {
  let message: ChatMessage
  
  var body: some View {
    HStack(alignment: .center, spacing: 4) {
      Image(systemName: "arrow.right")
        .resizable()
        .scaledToFit()
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
        .frame(width: 12, height: 12)
      
      Text(message.text)
        .lineLimit(1)
        .truncationMode(.middle)
        .fontWeight(.semibold)
        .textSelection(.disabled)

      Spacer()
    }
    .opacity(0.3)
  }
}

struct ChatLeftMessageView: View {
  let message: ChatMessage
  
  var body: some View {
    HStack(alignment: .center, spacing: 4) {
      Image(systemName: "arrow.left")
        .resizable()
        .scaledToFit()
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
        .frame(width: 12, height: 12)
      
      Text(message.text)
        .lineLimit(1)
        .truncationMode(.middle)
        .fontWeight(.semibold)
        .textSelection(.disabled)

      Spacer()
    }
    .opacity(0.3)
  }
}


struct ChatDisconnectedMessageView: View {
  let message: ChatMessage
  
  var body: some View {
    HStack {
      Spacer()
    }
    .frame(height: 5)
    .background(Color.primary)
    .clipShape(.capsule)
    .opacity(0.1)
  }
}

struct ChatMessageView: View {
  let message: ChatMessage
  
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      if let username = message.username {
        //                        if msg.text.isImageURL() {
        //                          HStack(alignment: .bottom) {
        //                            Text("**\(username):** ")
        //
        //                            let imageURL = URL(string: msg.text)!
        //                            AsyncImage(url: imageURL) { phase in
        //                              switch phase {
        //                              case .failure:
        //                                Text(LocalizedStringKey(msg.text.convertLinksToMarkdown()))
        //                                  .lineSpacing(4)
        //                                  .multilineTextAlignment(.leading)
        //                                  .textSelection(.enabled)
        //                                  .tint(Color("Link Color"))
        //                              case .success(let img):
        //                                Link(destination: imageURL) {
        //                                  img
        //                                    .resizable()
        //                                    .scaledToFit()
        //                                    .frame(maxWidth: 250, maxHeight: 150, alignment: .leading)
        //                                    .onAppear {
        //                                      reader.scrollTo(bottomID, anchor: .bottom)
        //                                    }
        //                                }
        //                              default:
        //                                ProgressView().controlSize(.small)
        //                              }
        //                            }
        //
        //                            Spacer()
        //                          }
        //                        }
        //                        else {
        Text(LocalizedStringKey("**\(username):** \(message.text)".convertingLinksToMarkdown()))
          .lineSpacing(4)
          .multilineTextAlignment(.leading)
          .textSelection(.enabled)
          .tint(Color("Link Color"))
        //                        }
      }
      else {
        Text(message.text)
          .lineSpacing(4)
          .multilineTextAlignment(.leading)
          .textSelection(.enabled)
          .tint(Color("Link Color"))
      }
      Spacer()
    }
  }
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
              LazyVStack(alignment: .leading, spacing: 8) {
                
                ForEach(model.chat) { msg in
                  if msg.type == .agreement {
                    VStack(alignment: .center, spacing: 16) {
                      if let bannerImage = self.model.bannerImage {
                        HStack(spacing: 0) {
                          Spacer(minLength: 0)
                          ZStack {
                            Image(nsImage: bannerImage)
                              .resizable()
                              .scaledToFit()
                              .frame(maxWidth: 468.0)
                              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                              .offset(y: 1.5)
                              .blur(radius: 4)
                              .opacity(0.2)
                            
                            Image(nsImage: bannerImage)
                              .resizable()
                              .scaledToFit()
                              .frame(maxWidth: 468.0)
                              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                          }
                          
                          Spacer(minLength: 0)
                        }
                      }

                      ServerAgreementView(text: msg.text)
                    }
                    .padding(.vertical, 24)
                  }
                  else if msg.type == .server {
                    ServerMessageView(message: msg.text)
                  }
                  else if msg.type == .joined {
                    ChatJoinedMessageView(message: msg)
                  }
                  else if msg.type == .left {
                    ChatLeftMessageView(message: msg)
                  }
                  else if msg.type == .signOut {
                    ChatDisconnectedMessageView(message: msg)
                      .padding(.vertical, 24)
                  }
                  else {
                    ChatMessageView(message: msg)
                  }
                }
              }
              .padding()
              
              VStack(spacing: 0) {}.id(bottomID)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.chat.count) {
              reader.scrollTo(bottomID, anchor: .bottom)
              model.markPublicChatAsRead()
            }
            .onAppear {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: gm.size) {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: self.model.bannerImage) {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
          }
          
          // MARK: Input Divider
          Divider()
          
          // MARK: Input Bar
          HStack(alignment: .lastTextBaseline, spacing: 0) {
            TextField("", text: $input, axis: .vertical)
              .focused($focusedField, equals: .chatInput)
              .textFieldStyle(.plain)
              .lineLimit(1...5)
              .multilineTextAlignment(.leading)
              .onSubmit {
                if !self.input.isEmpty {
                  model.sendChat(self.input, announce: NSEvent.modifierFlags.contains(.shift))
                }
                self.input = ""
              }
              .frame(maxWidth: .infinity)
              .padding()
          }
          .frame(maxWidth: .infinity, minHeight: 28)
          .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          .overlay(alignment: .leadingLastTextBaseline) {
            Image(systemName: "chevron.right").fontWeight(.semibold).opacity(0.4).offset(x: 16)
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
    }
    .background(Color(nsColor: .textBackgroundColor))
    //    .toolbar {
    //      ToolbarItem(placement: .primaryAction) {
    //        Button {
    //          if prepareChatDocument() {
    //            showingExporter = true
    //          }
    //        } label: {
    //          Image(systemName: "square.and.arrow.up")
    //        }.help("Save Chat...")
    //      }
    //    }
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
  
//  private func prepareChatDocument() -> Bool {
//    var text: String = String()
//    
//    self.chatDocument.text = ""
//    for msg in model.chat {
//      if msg.type == .agreement {
//        text.append(msg.text)
//        text.append("\n\n")
//      }
//      else if msg.type == .message {
//        if let username = msg.username {
//          text.append("\(username): \(msg.text)")
//        }
//        else {
//          text.append(msg.text)
//        }
//        text.append("\n")
//      }
//      else if msg.type == .status {
//        text.append(msg.text)
//        text.append("\n")
//      }
//    }
//    
//    if text.isEmpty {
//      return false
//    }
//    
//    self.chatDocument.text = text
//    
//    return true
//  }
}

#Preview {
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
