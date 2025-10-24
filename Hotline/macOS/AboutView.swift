import SwiftUI
import SwiftUIIntrospect

struct AboutContributor: Identifiable {
  let id: UUID = UUID()
  let username: String
  let webURL: URL
  let pictureURL: URL?
}

struct AboutContributorView: View {
  @Environment(\.openURL) private var openURL
  
  let contributor: AboutContributor
  
  var body: some View {
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
//    }
//    .accessibilityAddTraits(.isLink)
//    .pointerStyle(.link)
  }
}

struct AboutView: View {
  @Environment(\.openURL) private var openURL
  
  @State private var contributors: [AboutContributor] = []
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      self.brandView
      self.contributorsList
        .background {
          Color.black.blendMode(.softLight).opacity(0.3).ignoresSafeArea()
        }
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
    .task {
      await loadContributors()
    }
  }
  
  private var brandView: some View {
    VStack(alignment: .center, spacing: 4) {
      Spacer()
      
      Image("About Hotline")
      
      Text("Hotline")
        .font(.system(size: 28))
        .fontWeight(.bold)
        .padding(.top, 12)
        .kerning(-1.0)
        .foregroundColor(.white)
      
      let appDetails = getAppVersionAndBuild()
      Button {
        self.openURL(URL(string: "https://github.com/mierau/hotline/releases/tag/\(appDetails.version)beta\(appDetails.build)")!)
      } label: {
        
        Text("Version \(String(format: "%.1f", appDetails.version))b\(appDetails.build)")
          .foregroundColor(.white.opacity(0.756))
          .padding(.vertical, 4)
          .padding(.horizontal, 12)
          .background {
            Capsule()
              .fill(.white.opacity(0.5))
              .blendMode(.softLight)
          }
      }
      .buttonStyle(.plain)
      .buttonBorderShape(.capsule)
      .padding(.bottom, 16)

      Spacer()
    }
    .frame(width: 250)
  }
  
  private var contributorsList: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        self.contributorHeaderView
        ForEach(self.contributors) { contributor in
          Button {
            self.openURL(contributor.webURL)
          } label: {
            AboutContributorView(contributor: contributor)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(.isLink)
          .pointerStyle(.link)
        }
      }
      .frame(maxWidth: .infinity)
      .padding()
    }
    .scrollClipDisabled()
    .scrollContentBackground(.hidden)
//    .introspect(.scrollView, on: .macOS(.v10_15, .v11, .v12, .v13, .v14, .v15, .v26)) { v in
//      v.automaticallyAdjustsContentInsets = false
//    }
  }
  
  private var contributorHeaderView: some View {
    VStack(alignment: .leading, spacing: 4) {
      Link(destination: URL(string: "https://github.com/mierau/hotline")!) {
        HStack(alignment: .center, spacing: 4) {
          Text("Contributors")
            .lineLimit(1)
            .font(.system(size: 16))
            .fontWeight(.semibold)
            .foregroundStyle(.black)
            .opacity(0.8)

          Image(systemName: "arrow.forward.circle.fill")
            .resizable()
            .fontWeight(.bold)
            .scaledToFit()
            .frame(width: 12, height: 12)
            .foregroundStyle(.black)
            .opacity(0.4)
        }
      }
      .accessibilityAddTraits(.isLink)
      .pointerStyle(.link)
      
      Text("Hotline is an open source project made possible by its contributors.")
        .font(.system(size: 11))
        .foregroundStyle(.black)
        .opacity(0.5)
        .padding(.trailing, 32)
    }
    .padding(.bottom, 8)
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
