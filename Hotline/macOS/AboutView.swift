import SwiftUI

struct AboutView: View {
  @Environment(\.openURL) private var openURL
  
  var body: some View {
    VStack(alignment: .center) {
      Spacer()
      Image("About Hotline")
        .padding(.top, 32)
      Text("Hotline")
        .font(.title)
        .fontWeight(.semibold)
        .padding(.top, 16)
      let appDetails = getAppVersionAndBuild()
      Text("\(appDetails.version)b\(appDetails.build)")
        .fontWeight(.semibold)
        .opacity(0.6)
      Button("Download Latest") {
        if let url = URL(string: "https://github.com/mierau/hotline/releases/latest") {
          openURL(url)
        }
      }
      .controlSize(.large)
      .padding(.top, 16)
      Spacer()
    }
    .frame(width: 300, height: 400)
    .ignoresSafeArea()
  }
  
  func getAppVersionAndBuild() -> (version: String, build: String) {
    let infoDictionary = Bundle.main.infoDictionary
    let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let build = infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    return (version, build)
  }
}

#Preview {
  AboutView()
}
