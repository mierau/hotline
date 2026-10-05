import SwiftUI

struct AboutContributor: Identifiable {
  let username: String
  let webURL: URL
  let pictureURL: URL?

  var id: String { self.username }
}

struct AboutContributorView: View {
  let contributor: AboutContributor
  
  var body: some View {
    HStack(spacing: 10) {
      AsyncImage(url: self.contributor.pictureURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
        if let image = phase.image {
          image
            .interpolation(.high)
            .resizable()
            .scaledToFit()
            .background(.white)
            .transition(.opacity)
        } else {
          Color.white.opacity(0.15)
        }
      }
      .frame(width: 32, height: 32)
      .clipShape(.circle)
      
      VStack(alignment: .leading, spacing: 1) {
        Text(self.contributor.username)
          .fontWeight(.semibold)
          .foregroundStyle(.white)
        
        // The profile's address without the https:// in front.
        Text((self.contributor.webURL.host() ?? "") + self.contributor.webURL.path())
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.55))
          .truncationMode(.middle)
      }
      .lineLimit(1)
    }
  }
}

/// The version's soft capsule, from before Liquid Glass.
private struct AboutVersionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white.opacity(0.756))
      .padding(.vertical, 4)
      .padding(.horizontal, 12)
      .background {
        Capsule()
          .fill(.white.opacity(0.5))
          .blendMode(.softLight)
      }
  }
}

private extension View {
  @ViewBuilder
  func aboutVersionButtonStyle() -> some View {
    if #available(macOS 26, *) {
      self.buttonStyle(.glass)
    }
    else {
      self.buttonStyle(AboutVersionButtonStyle())
    }
  }
}

/// A contributor's row, which lights up a little under the pointer and a little more while pressed.
private struct AboutContributorButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    AboutContributorRow(configuration: configuration)
  }
}

private struct AboutContributorRow: View {
  let configuration: ButtonStyleConfiguration
  
  @State private var hovered: Bool = false
  
  var body: some View {
    self.configuration.label
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.white.opacity(self.configuration.isPressed ? 0.14 : (self.hovered ? 0.08 : 0)))
          .animation(.easeOut(duration: 0.15), value: self.hovered)
      }
      .contentShape(.rect(cornerRadius: 10, style: .continuous))
      .onHover { self.hovered = $0 }
  }
}

struct AboutView: View {
  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  
  @State private var contributors: [AboutContributor] = []
  
  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      self.brandView
      self.contributorsList
    }
    .frame(width: 570, height: 281)
    .background {
      // At its own size and centered, so the window trims a little off each edge.
      Image("About Box")
        .ignoresSafeArea()
    }
    // Night sky, so dark glass and scroll bars.
    .environment(\.colorScheme, .dark)
    .task {
      await loadContributors()
    }
  }
  
  private var brandView: some View {
    VStack(alignment: .center, spacing: 20) {
      SpinningBannerLogo(interaction: .dragToSpin, zoom: 4 / 3)
        .frame(width: 220, height: 180)
        // Laid out at the size of the H itself, which is 150 pt tall in the middle of its view, so
        // the spacing and centering go by what you see.
        .padding(.vertical, -15)
        .pointerStyle(.grabIdle)
      
      let appDetails = getAppVersionAndBuild()
      Button {
        self.openURL(URL(string: "https://github.com/mierau/hotline/releases/tag/\(appDetails.version)beta\(appDetails.build)")!)
      } label: {
        Text("Version \(String(format: "%.1f", appDetails.version))b\(appDetails.build)")
      }
      .aboutVersionButtonStyle()
    }
    // Centered between the edge of the window and the contributors, whose names start 20 pt in,
    // so there's as much room on either side.
    .padding(.leading, 20)
    .frame(width: 250)
    // And centered in the whole window, since the titlebar is clear.
    .frame(maxHeight: .infinity)
    .ignoresSafeArea(edges: .top)
  }
  
  private var contributorsList: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 2) {
        self.contributorHeaderView
          .padding(.horizontal, 10)
          .padding(.bottom, 12)
        
        ForEach(Array(self.contributors.enumerated()), id: \.element.id) { index, contributor in
          Button {
            self.openURL(contributor.webURL)
          } label: {
            AboutContributorView(contributor: contributor)
          }
          .buttonStyle(AboutContributorButtonStyle())
          .accessibilityAddTraits(.isLink)
          .pointerStyle(.link)
          .transition(self.contributorTransition(index))
        }
      }
      // Fill the width even before the contributors arrive, or the header starts out centered and
      // slides over when they do.
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.top, 24)
      .padding(.bottom, 10)
    }
    // The titlebar is clear and its buttons sit over the other side, so the list runs to the top
    // of the window.
    .ignoresSafeArea(edges: .top)
  }
  
  private var contributorHeaderView: some View {
    VStack(alignment: .leading, spacing: 4) {
      Link(destination: URL(string: "https://github.com/mierau/hotline")!) {
        Text("Contributors")
          .font(.system(size: 16))
          .fontWeight(.semibold)
          .foregroundStyle(.white)
      }
      .pointerStyle(.link)
      
      Text("Hotline is an open source project made possible by its contributors and sponsors.")
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.trailing, 32)
    }
  }
  
  /// Contributors drift up into place one after another as they arrive.
  private func contributorTransition(_ index: Int) -> AnyTransition {
    let move: AnyTransition = self.reduceMotion ? .identity : .offset(y: 8)
    return AnyTransition.opacity.combined(with: move)
      .animation(.smooth(duration: 0.5).delay(Double(min(index, 12)) * 0.04))
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
    
    // Keep what's on screen if the list couldn't be loaded this time.
    guard !newContributors.isEmpty else {
      return
    }

    // Contributors animate in the first time. Coming back to the window refreshes them in place.
    if self.contributors.isEmpty {
      withAnimation {
        self.contributors = newContributors
      }
    }
    else {
      self.contributors = newContributors
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
