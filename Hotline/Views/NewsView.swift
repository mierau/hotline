import SwiftUI

struct NewsView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  
  @State private var fetched = false
  @State private var selectedCategory: NewsCategory? = nil
  @State private var topListHeight: CGFloat = 200
  @State private var dividerHeight: CGFloat = 30
  
  var articleList: some View {
    
    // Your list content goes here
    List {
      ForEach(model.news, id: \.self) { category in
        DisclosureGroup {
          ProgressView(value: 0.4)
            .task {
              print("EXPANDED?", category.name)
//              hotline.sendGetNewsArticles(path: [cat.name]) {
//                print("OK")
//              }
            }
        } label: {
          Text(category.name)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
    .scrollBounceBehavior(.basedOnSize)
//    .listStyle(.plain)
  }
  
  var readerView: some View {
    // Your list content goes here
    ScrollView(.vertical) {
      HStack(alignment: .top, spacing: 0) {
        Text("HELLO")
          .multilineTextAlignment(.leading)
        Spacer()
      }
      .padding()
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(colorScheme == .dark ? Color(white: 0.1) : Color(uiColor: UIColor.systemBackground))
  }
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        articleList
          .frame(height: topListHeight)
        VStack(alignment: .center) {
          Divider()
          Spacer()
          HStack(alignment: .center) {
            Rectangle()
              .fill(.tertiary)
              .frame(width: 50, height: 6, alignment: .center)
              .cornerRadius(10)
          }
          Spacer()
        }
        .background(colorScheme == .dark ? Color(white: 0.1) : Color(uiColor: UIColor.systemBackground))
        .frame(maxWidth: .infinity)
        .frame(height: dividerHeight)
        .gesture(
          DragGesture()
            .onChanged { gesture in
              let delta = gesture.translation.height
              topListHeight = max(min(topListHeight + delta, 500), 50)
              //                bottomListHeight = max(min(bottomListHeight - delta, 400), 0)
            }
        )
        readerView
      }
      .task {
        if !fetched {
          let _ = await model.getNewsCategories()
          fetched = true
          
          //          hotline.sendGetNewsArticles(path: ["News"]) {
          //            print("GOT ARTICLES?")
          //          }
        }
      }
      //      .refreshable {
      //        hotline.sendGetNewsCategories()
      //      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(model.server?.name ?? "")
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
//        ToolbarItem(placement: .navigationBarTrailing) {
//          Button {
//            
//          } label: {
//            Image(systemName: "square.and.pencil")
//            //              .symbolRenderingMode(.hierarchical)
//            //              .foregroundColor(.secondary)
//          }
//          
//        }
      }
    }
    
  }
}

#Preview {
  MessageBoardView()
    .environment(HotlineState())
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
