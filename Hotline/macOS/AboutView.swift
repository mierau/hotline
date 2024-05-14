import SwiftUI

enum VersionCheckState {
  case needToCheck
  case checking
  case upToDate
  case updateAvailable(version: String)
}

struct AboutContributor: Identifiable {
  let id: UUID = UUID()
  let username: String
  let webURL: URL
  let pictureURL: URL?
}

struct AboutView: View {
  @Environment(\.openURL) private var openURL
  
  @State private var versionCheck: VersionCheckState = .needToCheck
  @State private var downloadURL: String = "https://github.com/mierau/hotline/releases/latest"
  @State private var contributors: [AboutContributor] = []
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      VStack(alignment: .center, spacing: 0) {
        Spacer()
        
        Image("About Hotline")
          .padding(.top, 44)
        
        Text("Hotline")
          .font(.system(size: 28))
          .fontWeight(.bold)
          .padding(.top, 12)
          .kerning(-1.0)
          .foregroundColor(.white)
        
        let appDetails = getAppVersionAndBuild()
        Text("Version \(String(format: "%.1f", appDetails.version))b\(appDetails.build)")
          .foregroundColor(.white)
          .opacity(0.4)
        
        HStack(alignment: .center) {
          switch versionCheck {
          case .needToCheck:
            Button("Check for Updates") {
              Task {
                await checkForUpdate()
              }
            }
            .controlSize(.small)
          case .checking:
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Checking for updates...")
                .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .tint(.white)
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
            .controlSize(.small)
          }
        }
        .frame(height: 40)

        Spacer()
      }
      .frame(width: 250)
      
      Spacer()
      
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 16) {
          
          VStack(alignment: .leading, spacing: 4) {
            Link(destination: URL(string: "https://github.com/mierau/hotline")!) {
              HStack(alignment: .center, spacing: 4) {
                Text("Contributors")
                  .lineLimit(1)
                  .font(.system(size: 16))
                  .fontWeight(.semibold)
                  .foregroundStyle(.black)
                  .opacity(0.75)

                Image(systemName: "arrow.forward.circle.fill")
                  .resizable()
                  .fontWeight(.bold)
                  .scaledToFit()
                  .frame(width: 12, height: 12)
                  .foregroundStyle(.black)
                  .opacity(0.75)
              }
            }
            .padding(.top, 24)
            
            Text("Hotline is an open source project made possible by its contributors.")
              .font(.system(size: 11))
              .foregroundStyle(.black)
              .blendMode(.overlay)
              .padding(.trailing, 32)
          }
          .padding(.bottom, 8)
          
          ForEach(contributors) { contributor in
            Link(destination: contributor.webURL) {
              HStack {
                if let pictureURL = contributor.pictureURL {
                  AsyncImage(url: pictureURL) { phase in
                    if let image = phase.image {
                      image
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .background(.white)
                        .frame(width: 32, height: 32)
                    } else if phase.error != nil {
                      Color.clear
                        .frame(width: 32, height: 32)
                    } else {
                      Color.white
                        .opacity(0.2)
                        .frame(width: 32, height: 32)
                    }
                  }
                  .frame(width: 32, height: 32)
                  .clipShape(Circle())
                  
//                  AsyncImage(url: pictureURL) { img in
//                    img
//                      .interpolation(.high)
//                      .resizable()
//                      .scaledToFit()
//                      .background(.white)
//                  } placeholder: {
//                    Color.white.opacity(0.2)
//                      .frame(width: 32, height: 32)
//                  }
//                  .frame(width: 32, height: 32)
//                  .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                  Text(contributor.username)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                  
                  Text(contributor.webURL.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                }
              }
            }
          }
        }
      }
      .scrollClipDisabled()
    }
    .frame(width: 570, height: 330)
    .background(
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 0) {
          Divider()
          Spacer()
        }
        .frame(height: 330 + 100)
        .offset(x: 250)
      }
    )
    .background(Color.hotlineRed)
    .task {
      await loadContributors()
    }
  }
  
  func loadContributors() async {
    var newContributors: [AboutContributor] = []
    
    if let url = URL(string: "https://api.github.com/repos/mierau/hotline/contributors"),
       let (data, _) = try? await URLSession.shared.data(from: url) {
      if let jsonContributors = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
        for contributor in jsonContributors {
          if let username = contributor["login"] as? String,
             let webURLString = contributor["html_url"] as? String,
             let webURL = URL(string: webURLString) {
            var pictureURL: URL? = nil
            if let pictureURLString = contributor["avatar_url"] as? String {
              pictureURL = URL(string: pictureURLString)
            }
            newContributors.append(AboutContributor(username: username, webURL: webURL, pictureURL: pictureURL))
          }
        }
      }
    }
    
    withAnimation {
      contributors = newContributors
    }
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
