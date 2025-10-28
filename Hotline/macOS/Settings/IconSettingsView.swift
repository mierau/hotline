import SwiftUI

struct IconSettingsView: View {
  @State private var hoveredUserIconID: Int = -1
  
  var body: some View {
    @Bindable var preferences = Prefs.shared
    
    Form {
      ScrollViewReader { scrollProxy in
        ScrollView {
          LazyVGrid(columns: [
            GridItem(.fixed(4+32+4)),
            GridItem(.fixed(4+32+4)),
            GridItem(.fixed(4+32+4)),
            GridItem(.fixed(4+32+4)),
            GridItem(.fixed(4+32+4)),
            GridItem(.fixed(4+32+4)),
            GridItem(.fixed(4+32+4))
          ], spacing: 0) {
            ForEach(Hotline.classicIconSet, id: \.self) { iconID in
              HStack {
                Image("Classic/\(iconID)")
                  .resizable()
                  .interpolation(.none)
                  .scaledToFit()
                  .frame(width: 32, height: 16)
                  .help("Icon \(String(iconID))")
              }
              .tag(iconID)
              .frame(width: 32, height: 32)
              .padding(4)
              .background(iconID == preferences.userIconID ? Color.accentColor : (iconID == hoveredUserIconID ? Color.accentColor.opacity(0.1) : Color(nsColor: .textBackgroundColor)))
              .clipShape(RoundedRectangle(cornerRadius: 5))
              .onTapGesture {
                preferences.userIconID = iconID
              }
              .onHover { hovered in
                if hovered {
                  self.hoveredUserIconID = iconID
                }
              }
            }
          }
          .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .onAppear {
          scrollProxy.scrollTo(preferences.userIconID, anchor: .center)
        }
        .frame(height: 355)
      }
    }
    .padding()
  }
}
