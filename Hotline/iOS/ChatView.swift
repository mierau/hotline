import SwiftUI

extension View {
  func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

struct ChatView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  
  @State var input: String = ""
  @State private var scrollPos: Int?
  @State private var contentHeight: CGFloat = 0
  
  @Namespace var bottomID
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(alignment: .leading) {
              ForEach(model.chat) { msg in
                if msg.type == .agreement {
                  
                  VStack(alignment: .center) {
                    if let bannerImage = self.model.bannerImage {
                      Image(uiImage: bannerImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 468.0)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    
                    VStack(alignment: .leading) {
                      HStack {
                        Text(msg.text)
                          .textSelection(.enabled)
                          .font(.system(size: 12))
                          .fontDesign(.monospaced)
                          .lineSpacing(2)
                          .padding()
                        Spacer()
                      }
                    }
                    .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96))
                    .frame(maxWidth: .infinity)
                    .cornerRadius(5)
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                }
                else if msg.type == .signOut {
                  HStack {
                    Spacer()
                    Label {
                      Text(msg.text)
                        .font(.footnote)
                    } icon: {
                      Image(systemName: "arrow.up.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.red)
                    .opacity(0.8)
                    Spacer()
                  }
                  .padding(.vertical, 6)
                }
                else {
                  HStack(alignment: .firstTextBaseline) {
                    if let username = msg.username {
                      Text("**\(username):** \(msg.text)")
                    }
                    else {
                      Text(msg.text)
                        .textSelection(.enabled)
                    }
                    Spacer()
                  }
                  .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
              }
              EmptyView().id(bottomID)
            }
            .padding(.bottom, 12)
          }
          .defaultScrollAnchor(.bottom)
          .onChange(of: model.chat.count) {
            withAnimation {
              reader.scrollTo(bottomID, anchor: .bottom)
            }
            print("SCROLLED TO BOTTOM")
          }
          .onAppear {
            reader.scrollTo(bottomID, anchor: .bottom)
          }
          .scrollDismissesKeyboard(.interactively)
          .onTapGesture {
            self.endEditing()
          }
        }
        
        Divider()
        
        HStack(alignment: .top) {
          Image(systemName: "chevron.right").opacity(0.4)
          TextField("", text: $input, axis: .vertical)
            .autocapitalization(.none)
            .lineLimit(1...5)
            .onSubmit {
              if !self.input.isEmpty {
                model.sendChat(self.input)
                //                hotline.sendChat(message: self.input)
              }
              self.input = ""
            }
            .frame(maxWidth: .infinity)
          Button {
            if !self.input.isEmpty {
              model.sendChat(self.input)
              //              hotline.sendChat(message: self.input)
            }
            self.input = ""
          } label: {
            Image(systemName: self.input.isEmpty ? "arrow.up.circle" : "arrow.up.circle.fill")
              .resizable()
              .scaledToFit()
              .frame(width: 24.0, height: 24.0)
              .opacity(self.input.isEmpty ? 0.4 : 1.0)
          }
        }.padding()
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.serverTitle)
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            model.disconnect()
          } label: {
            Text(Image(systemName: "xmark.circle.fill"))
              .symbolRenderingMode(.hierarchical)
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
      }
      
    }
  }
}

#Preview {
  ChatView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
