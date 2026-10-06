import SwiftUI

struct IdentitySettingsView: View {
  @State private var hoveredUserIconID: Int = -1

  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      // Without spaces around it, and with none, "unnamed", as the field says when it's empty.
      DeferredTextField(title: "Nickname", text: $preferences.username, prompt: Text("unnamed"), cleanUp: { name in
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "unnamed" : name
      })

      Section("Icon") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 0)], spacing: 0) {
          ForEach(HotlineState.classicIconSet, id: \.self) { iconID in
            Image("Classic/\(iconID)")
              .resizable()
              .interpolation(.none)
              .scaledToFit()
              .frame(width: 32, height: 16)
              .help("Icon \(String(iconID))")
              .tag(iconID)
              .frame(width: 32, height: 32)
              .padding(4)
              .background(
                RoundedRectangle(cornerRadius: 5)
                  .fill(iconID == self.hoveredUserIconID ? Color.accentColor.opacity(0.1) : .clear)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 5)
                  .strokeBorder(iconID == preferences.userIconID ? Color.accentColor : .clear, lineWidth: 2)
              )
              .contentShape(Rectangle())
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
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
