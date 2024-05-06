import SwiftUI

enum VersionCheckState {
  case needToCheck
  case checking
  case upToDate
  case updateAvailable(version: String)
}

struct AboutView: View {
  @Environment(\.openURL) private var openURL
  
  @State private var versionCheck: VersionCheckState = .needToCheck
  @State private var downloadURL: String = "https://github.com/mierau/hotline/releases/latest"
  
  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      Spacer()
      
      Image("About Hotline")
        .padding(.top, 32)
      
      Text("Hotline")
        .font(.title)
        .fontWeight(.semibold)
        .padding(.top, 16)
        .foregroundColor(.white)
      
      let appDetails = getAppVersionAndBuild()
      Text("\(String(format: "%.1f", appDetails.version))b\(appDetails.build)")
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .opacity(0.6)
      
      HStack(alignment: .center) {
        switch versionCheck {
        case .needToCheck:
          Button("Check for Updates") {
            Task {
              await checkForUpdate()
            }
          }
          .controlSize(.regular)
        case .checking:
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
              .tint(.white)
            Text("Checking for updates...")
              .fontWeight(.semibold)
              .foregroundStyle(.white)
          }
        case .upToDate:
          Label("Hotline is up to date.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.white)
            .fontWeight(.semibold)
            .tint(.white)
            .onTapGesture {
              versionCheck = .needToCheck
            }
        case .updateAvailable(let version):
          Button("Download Latest \(version)") {
            if let url = URL(string: downloadURL) {
              openURL(url)
            }
          }
          .controlSize(.regular)
        }
      }
      .frame(height: 40)
      .padding(.top, 8)

      Spacer()
    }
    .frame(width: 300, height: 400)
    .ignoresSafeArea()
  }
  
  func checkForUpdate() async {
    let appDetails = getAppVersionAndBuild()
    
    self.versionCheck = .checking
    
    do {
      let url = URL(string: "https://api.github.com/repos/mierau/hotline/releases/latest")!
      let (data, _) = try await URLSession.shared.data(from: url)
      let versionExpression = /^([0-9\.]+)beta([0-9]+)/
      
      if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
         let tagName = json["tag_name"] as? String,
         let assets = json["assets"] as? [[String: Any]],
         let firstAsset = assets.first,
         let assetDownloadURL = firstAsset["browser_download_url"] as? String,
         let versionMatches = try? versionExpression.wholeMatch(in: tagName) {
        if let versionNumber = Double(versionMatches.1),
           let buildNumber = Int(versionMatches.2),
           versionNumber > appDetails.version || buildNumber > appDetails.build {
            let versionString = "\(versionMatches.1)b\(versionMatches.2)"
            self.versionCheck = .updateAvailable(version: versionString)
            downloadURL = assetDownloadURL
        }
        else {
          self.versionCheck = .upToDate
        }
      }
      else {
        self.versionCheck = .needToCheck
      }
    }
    catch {
      self.versionCheck = .needToCheck
    }
  }
  
  func getAppVersionAndBuild() -> (version: Double, build: Int) {
    let infoDictionary = Bundle.main.infoDictionary!
    let version = Double(infoDictionary["CFBundleShortVersionString"]! as! String)!
    let build = Int(infoDictionary["CFBundleVersion"]! as! String)!
    return (version, build)
  }
}

#Preview {
  AboutView()
}
