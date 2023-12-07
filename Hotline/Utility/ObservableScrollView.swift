import SwiftUI

struct ScrollViewOffsetPreferenceKey: PreferenceKey {
  typealias Value = CGFloat
  static var defaultValue = CGFloat.zero
  static func reduce(value: inout Value, nextValue: () -> Value) {
    value += nextValue()
  }
}

struct ObservableScrollView<Content>: View where Content : View {
  @Namespace var scrollSpace
  @Binding var scrollOffset: CGFloat
  let content: () -> Content
  
  init(scrollOffset: Binding<CGFloat>,
       @ViewBuilder content: @escaping () -> Content) {
    _scrollOffset = scrollOffset
    self.content = content
  }
  
  var body: some View {
    ScrollView {
      content()
        .background(GeometryReader { geo in
          let offset = -geo.frame(in: .named(scrollSpace)).minY
          Color.clear
            .preference(key: ScrollViewOffsetPreferenceKey.self,
                        value: offset)
        })
      
    }
    .coordinateSpace(name: scrollSpace)
    .onPreferenceChange(ScrollViewOffsetPreferenceKey.self) { value in
      scrollOffset = value
    }
  }
}
