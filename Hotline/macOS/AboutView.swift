import SwiftUI

struct AboutContributor: Identifiable, Codable, Equatable {
  let username: String
  let webURL: URL
  let pictureURL: URL?

  var id: String { self.username }
}

/// The contributors as they last came from GitHub, kept so the About box has them straight away,
/// and when GitHub can't be asked: offline, or past the 60 requests an hour it answers from an
/// address that isn't signed in, which the app's update check, and anything else there, share.
enum AboutContributorsCache {
  struct Kept: Codable {
    let date: Date
    let contributors: [AboutContributor]
  }

  static let fileURL = URL.cachesDirectory.appending(path: "Contributors.json", directoryHint: .notDirectory)
  /// How long what's kept is good for, before GitHub's asked again.
  static let freshness: TimeInterval = 24 * 60 * 60

  static func load(from fileURL: URL = Self.fileURL) -> Kept? {
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    return try? JSONDecoder().decode(Kept.self, from: data)
  }

  static func save(_ contributors: [AboutContributor], date: Date = .now, to fileURL: URL = Self.fileURL) {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(Kept(date: date, contributors: contributors)).write(to: fileURL, options: .atomic)
    }
    catch {
      print("AboutView: Couldn't keep the contributors: \(error)")
    }
  }
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
  
  /// Shows the contributors as they were kept, straight away, and asks GitHub for them again once
  /// they're a day old, or there aren't any yet.
  func loadContributors() async {
    let kept = AboutContributorsCache.load()
    if let kept, !kept.contributors.isEmpty {
      self.show(kept.contributors)
      if Date.now.timeIntervalSince(kept.date) < AboutContributorsCache.freshness {
        return
      }
    }

    // What's on screen stays, if they couldn't be had this time.
    guard let fetched = await Self.fetchContributors(), !fetched.isEmpty else {
      return
    }
    AboutContributorsCache.save(fetched)
    self.show(fetched)
  }

  /// Contributors animate in the first time. Coming back to the window refreshes them in place.
  private func show(_ contributors: [AboutContributor]) {
    guard contributors != self.contributors else {
      return
    }
    if self.contributors.isEmpty {
      withAnimation {
        self.contributors = contributors
      }
    }
    else {
      self.contributors = contributors
    }
  }

  /// The contributors, from GitHub, or nil, saying why, if GitHub didn't give them.
  private static func fetchContributors() async -> [AboutContributor]? {
    guard let url = URL(string: "https://api.github.com/repos/mierau/hotline/contributors") else {
      return nil
    }
    let data: Data
    do {
      let (body, response) = try await URLSession.shared.data(from: url)
      // GitHub says why it didn't, as when it's had its 60 requests this hour, in a message.
      if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["message"] as? String
        print("AboutView: GitHub didn't give the contributors: HTTP \(http.statusCode) \(message ?? "")")
        return nil
      }
      data = body
    }
    catch {
      print("AboutView: Couldn't ask GitHub for the contributors: \(error)")
      return nil
    }

    guard let jsonContributors = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return nil
    }
    return jsonContributors.compactMap { contributor in
      guard let username = contributor["login"] as? String,
            let webURLString = contributor["html_url"] as? String,
            let webURL = URL(string: webURLString) else {
        return nil
      }
      let pictureURL = (contributor["avatar_url"] as? String).flatMap { URL(string: $0) }
      return AboutContributor(username: username, webURL: webURL, pictureURL: pictureURL)
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
