import SwiftUI

struct NewsView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(\.colorScheme) var colorScheme
  
  @State private var fetched = false
  @State private var selectedCategory: HotlineNewsCategory? = nil
  @State private var topListHeight: CGFloat = 200
  @State private var dividerHeight: CGFloat = 30
  
  var topList: some View {
    
    // Your list content goes here
    List {
      ForEach(hotline.newsCategories, id: \.self) { cat in
        DisclosureGroup {
          ProgressView(value: 0.4)
            .task {
              print("EXPANDED?", cat.name)
              hotline.sendGetNewsArticles(path: [cat.name]) {
                print("OK")
              }
            }
        } label: {
          Text(cat.name)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
//    .listStyle(.plain)
  }
  
  var bottomList: some View {
    // Your list content goes here
    ScrollView(.vertical) {
      HStack(alignment: .top, spacing: 0) {
        Text("HELLO")
          .multilineTextAlignment(.leading)
        Spacer()
      }
      .padding()
    }
    .background(colorScheme == .dark ? Color(white: 0.1) : Color(uiColor: UIColor.systemBackground))
  }
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        topList
          .frame(height: topListHeight)
        VStack(alignment: .center) {
          Divider()
          Spacer()
          HStack(alignment: .center) {
            Rectangle()
              .fill(.tertiary)
              .frame(width: 50, height: 6, alignment: .center)
              .cornerRadius(10)
//              .opacity(0.3)
//            Image(systemName: "line.3.horizontal")
//              .opacity(0.2)
//              .font(.system(size: 14))
          }
          Spacer()
//          Divider()
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
        bottomList
      }
      .task {
        if !fetched {
          hotline.sendGetNewsCategories() {
            fetched = true
          }
          
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
          Text(hotline.server?.name ?? "")
            .font(.headline)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            hotline.disconnect()
          } label: {
            Text(Image(systemName: "xmark.circle.fill"))
              .symbolRenderingMode(.hierarchical)
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            
          } label: {
            Image(systemName: "square.and.pencil")
            //              .symbolRenderingMode(.hierarchical)
            //              .foregroundColor(.secondary)
          }
          
        }
      }
    }
    
  }
}

#Preview {
  MessageBoardView()
    .environment(HotlineState())
    .environment(HotlineClient())
}
