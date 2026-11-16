import SwiftUI
import AppKit
import Observation

/// A newer build of Hotline, and what's new since this one, to install or not, then its coming in and
/// installing, which quits and relaunches Hotline, all in one window.
struct AppUpdateView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable private var update = AppUpdate.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if case .failed(let message) = self.update.stage {
        self.failure(message)
      }
      else {
        self.header
        self.releaseNotes
        self.actions
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .padding(.top, 8)
    .frame(width: self.isFailure ? 380 : 520)
    .frame(idealHeight: 360)
    .onChange(of: self.update.showWindow) { _, show in
      if !show {
        self.dismiss()
      }
    }
    .onDisappear {
      self.update.windowClosed()
    }
  }

  private var isFailure: Bool {
    if case .failed = self.update.stage {
      return true
    }
    return false
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .shadow(color: Color.black.mix(with: .red, by: 0.4).opacity(0.15), radius: 3, y: 1.5)

      VStack(alignment: .leading, spacing: 2) {
        Text("Hotline \(self.update.version)")
          .font(.title2)
          .fontWeight(.semibold)
        Text("A new version of Hotline is available. 🎉")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var releaseNotes: some View {
    let notes = self.update.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return ScrollView(.vertical) {
      MarkdownText(text: notes.isEmpty ? "_No release notes provided._" : notes, layout: Markdown.Layout(font: .systemFont(ofSize: 12), lineSpacing: 3), inset: NSSize(width: 12, height: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 220, maxHeight: 260)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  /// What can be done, as far as the update's got: installed or not, its download stopped, or
  /// Hotline quit to install it, once something stopped it quitting.
  @ViewBuilder
  private var actions: some View {
    HStack(spacing: 12) {
      switch self.update.stage {
      case .found, .failed:
        Button("Not Now") {
          self.update.notNow()
        }
        .keyboardShortcut(.escape, modifiers: [])
        Spacer()
        Button("Install Update") {
          self.update.install()
        }
        .keyboardShortcut(.defaultAction)
      case .downloading(let received, let expected):
        VStack(alignment: .leading, spacing: 4) {
          if expected > 0 {
            ProgressView(value: Double(min(received, expected)), total: Double(expected))
          }
          else {
            ProgressView()
          }
          Text(Self.progress(received: received, expected: expected))
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .progressViewStyle(.linear)
        Button("Cancel") {
          self.update.cancel()
        }
        .keyboardShortcut(.escape, modifiers: [])
      case .installing:
        VStack(alignment: .leading, spacing: 4) {
          ProgressView()
            .progressViewStyle(.linear)
          Text("Installing… Hotline will open again in a moment.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      case .waitingToQuit:
        Text("The update installs once Hotline quits.")
          .foregroundStyle(.secondary)
        Spacer()
        Button("Quit and Install") {
          self.update.retryQuitting()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .buttonBorderShape(.capsule)
    .controlSize(.large)
  }

  private static func progress(received: UInt64, expected: UInt64) -> String {
    let format = ByteCountFormatStyle(style: .file)
    let done = Int64(received).formatted(format)
    guard expected > 0 else {
      return "Downloading… \(done)"
    }
    return "Downloading… \(done) of \(Int64(expected).formatted(format))"
  }

  private func failure(_ message: AppUpdateMessage) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.multicolor)
          .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text(message.title)
            .font(.title2)
            .fontWeight(.semibold)
          // As many lines as it takes, as the window's only as tall as what's in it.
          Text(message.detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
      }
      HStack(spacing: 12) {
        // One Hotline can't install itself is on GitHub, to download there.
        if let page = message.page {
          Button("Not Now") {
            self.update.acknowledgeFailure()
          }
          .keyboardShortcut(.escape, modifiers: [])
          Spacer()
          Button("Download from GitHub") {
            self.update.download(from: page)
          }
          .keyboardShortcut(.defaultAction)
        }
        else {
          Spacer()
          Button("OK") {
            self.update.acknowledgeFailure()
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .buttonBorderShape(.capsule)
      .controlSize(.large)
    }
  }
}

// MARK: - Release Notes

/// Every build's notes, from Hotline's releases on GitHub: the builds down the side, the newest first,
/// and the notes of the one chosen, which starts as the build that's running. The notes GitHub last
/// gave show straight away, and stay, if it doesn't give them this time. Without any, it says why:
/// no connection, or GitHub's limit for the network, and until when.
struct ReleaseNotesView: View {
  @State private var releases: [ReleaseNotes] = []
  @State private var selection: ReleaseNotes.ID?
  /// The build chosen for you, before you choose one, which the window goes on choosing as newer
  /// notes come in: the build that's running, once there are notes for it.
  @State private var picked: ReleaseNotes.ID?
  /// Why GitHub didn't give the notes, the last time it was asked.
  @State private var failure: GitHubReleases.Failure?
  /// The build whose app is being downloaded, while it is.
  @State private var downloading: ReleaseNotes.ID?
  /// Why the last download didn't work, to say so.
  @State private var downloadFailure: DownloadFailure?
  @Environment(\.openURL) private var openURL

  private let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

  /// A build's app that couldn't be downloaded, and why.
  struct DownloadFailure {
    let version: String
    let reason: String
  }

  /// The build chosen.
  private var chosen: ReleaseNotes? {
    self.releases.first { $0.id == self.selection }
  }

  var body: some View {
    NavigationSplitView {
      // How long ago each came out, kept up to the minute.
      TimelineView(.everyMinute) { context in
        List(self.releases, selection: self.$selection) { release in
          ReleaseNotesRow(release: release, currentBuild: self.currentBuild, now: context.date)
        }
      }
      .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
    } detail: {
      if let release = self.chosen {
        ScrollView(.vertical) {
          ReleaseNotesDetail(release: release, isInstalled: release.build == self.currentBuild)
        }
        // From the top for each build.
        .id(release.id)
      }
      else if let failure = self.failure {
        ContentUnavailableView {
          Label("Couldn't Load Release Notes", systemImage: "exclamationmark.triangle")
        } description: {
          Text(Self.explanation(of: failure))
        } actions: {
          Button("Try Again") {
            Task {
              await self.load()
            }
          }
        }
      }
      else {
        ProgressView()
      }
    }
    .navigationTitle("Release Notes")
    .toolbar {
      self.toolbar
    }
    .alert(
      Text("Couldn't Download Hotline \(self.downloadFailure?.version ?? "")"),
      isPresented: Binding(get: { self.downloadFailure != nil }, set: { if !$0 { self.downloadFailure = nil } }),
      presenting: self.downloadFailure
    ) { _ in
      Button("OK") {}
    } message: { failure in
      Text(failure.reason)
    }
    .task {
      await self.load()
    }
  }

  /// The chosen build's app, to download, and its code and its release, on GitHub.
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem {
      Button {
        if let release = self.chosen {
          self.download(release)
        }
      } label: {
        // A spinner while it's coming.
        if self.downloading != nil, self.downloading == self.selection {
          ProgressView()
            .controlSize(.small)
        }
        else {
          Label("Download", systemImage: "arrow.down.circle")
        }
      }
      .disabled(self.chosen?.download == nil || self.downloading != nil)
      .help(self.chosen.map { Text("Download Hotline \($0.version) to your Downloads folder") } ?? Text("Download"))
    }

    ToolbarSpacer(.fixed)

    ToolbarItemGroup {
      Button {
        if let release = self.chosen {
          self.openURL(release.source)
        }
      } label: {
        Label("View Code", systemImage: "chevron.left.forwardslash.chevron.right")
      }
      .disabled(self.chosen == nil)
      .help(self.chosen.map { Text("View the code for Hotline \($0.version) on GitHub") } ?? Text("View Code"))

      Button {
        if let release = self.chosen {
          self.openURL(release.page)
        }
      } label: {
        Label("Open on GitHub", systemImage: "arrow.up.forward")
      }
      .disabled(self.chosen == nil)
      .help(self.chosen.map { Text("Open Hotline \($0.version)'s release on GitHub") } ?? Text("Open on GitHub"))
    }
  }

  /// Downloads a build's app to the Downloads folder, and shows it there in the Finder, or says why
  /// it couldn't.
  private func download(_ release: ReleaseNotes) {
    self.downloading = release.id
    Task {
      do {
        let file = try await ReleaseDownload.download(release)
        NSWorkspace.shared.activateFileViewerSelecting([file])
      }
      catch {
        self.downloadFailure = DownloadFailure(version: release.version, reason: error.localizedDescription)
      }
      self.downloading = nil
    }
  }

  /// How long ago something was, to the nearest of the biggest unit it's been at least one of, as
  /// GitHub says it: just now, for under a minute, then minutes, hours, days, weeks, months and
  /// years, so 20 days and 23 hours is 3 weeks, and 35 months is 3 years. One day, week, month or
  /// year is yesterday, last week, last month or last year.
  static func howLongAgo(_ date: Date, now: Date) -> String {
    let seconds = now.timeIntervalSince(date)
    guard seconds >= 60 else {
      return String(localized: "Just now")
    }
    let minutes = Int((seconds / 60).rounded())
    let hours = Int((seconds / 3600).rounded())
    let days = seconds / 86400
    let months = Int((days / 30.44).rounded())
    var ago = DateComponents()
    if minutes < 60 {
      ago.minute = -minutes
    }
    else if hours < 24 {
      ago.hour = -hours
    }
    else if days.rounded() < 7 {
      ago.day = -Int(days.rounded())
    }
    else if days < 30 {
      ago.weekOfMonth = -max(1, Int((days / 7).rounded()))
    }
    else if months < 12 {
      ago.month = -max(1, months)
    }
    else {
      ago.year = -max(1, Int((days / 365.25).rounded()))
    }
    return Self.relativeFormatter.localizedString(from: ago)
  }

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    // Capitalized, as it starts the line: Yesterday, Last week.
    formatter.formattingContext = .beginningOfSentence
    return formatter
  }()

  /// Shows the notes GitHub last gave, straight away, then asks it for them again, as one may have
  /// come out since.
  private func load() async {
    self.failure = nil
    if self.releases.isEmpty {
      self.show(ReleaseNotesCache.load())
    }
    do {
      self.show(try await GitHubReleases.fetch())
    }
    catch {
      self.failure = error as? GitHubReleases.Failure ?? .unexpected
    }
  }

  /// Shows builds' notes, with the build that's running chosen, or the newest without notes for it,
  /// unless you've chosen another.
  private func show(_ releases: [ReleaseNotes]) {
    guard !releases.isEmpty else {
      return
    }
    self.releases = releases
    if self.selection == nil || self.selection == self.picked {
      let pick = (releases.first { $0.build == self.currentBuild } ?? releases.first)?.id
      self.picked = pick
      self.selection = pick
    }
  }

  /// Why there aren't any notes, and what to do: wait for GitHub's limit to pass, as long as it
  /// says, or check the connection, or try again.
  static func explanation(of failure: GitHubReleases.Failure, now: Date = .now) -> String {
    switch failure {
    case .limited(let until):
      guard let until, until > now else {
        return String(localized: "GitHub is limiting requests from your network for now. Try again in a little while.")
      }
      let time = until.formatted(date: Calendar.current.isDate(until, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened)
      return String(localized: "GitHub is limiting requests from your network for now. Try again after \(time).")
    case .offline:
      return String(localized: "Check your connection to the internet, then try again.")
    case .unexpected:
      return String(localized: "GitHub didn't send them this time. Try again in a moment.")
    }
  }
}

/// A build in the list of them: its version, in semibold while it's newer than the one running, and
/// how long ago it came out, with a check in a circle on the one running, and a fainter check on those
/// before it, whose changes it has too.
struct ReleaseNotesRow: View {
  let release: ReleaseNotes
  /// The build that's running.
  let currentBuild: Int
  let now: Date

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Hotline \(self.release.version)")
          .fontWeight(self.release.build > self.currentBuild ? .semibold : .regular)
        Text(self.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      if self.release.build == self.currentBuild {
        // In the words' color, which is white on the row's color when it's chosen, with the check
        // cut out of the circle, showing what's under it.
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.primary)
          .help("The version you're using")
          .accessibilityLabel("Installed")
      }
      else if self.release.build < self.currentBuild {
        // The installed one's check, as big and where it is, without its circle, and bold.
        Image(systemName: "checkmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.tertiary, .clear)
          .fontWeight(.bold)
          .help("In the version you're using")
          .accessibilityLabel("In the version you're using")
      }
    }
    .padding(.vertical, 2)
  }

  /// How long ago it came out, and whether it's the build that's running.
  private var subtitle: String {
    let date = self.release.date.map { ReleaseNotesView.howLongAgo($0, now: self.now) }
    let installed = self.release.build == self.currentBuild ? String(localized: "Installed") : nil
    return [date, installed].compactMap { $0 }.joined(separator: " · ")
  }
}

/// One build's notes: Hotline's icon, beside its version, when it came out, and whether it's the one
/// running, then under a line, the notes themselves.
struct ReleaseNotesDetail: View {
  let release: ReleaseNotes
  let isInstalled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 52, height: 52)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 6) {
          Text("Hotline \(self.release.version)")
            .font(.title2)
            .fontWeight(.semibold)
          HStack(spacing: 8) {
            if let date = self.release.date {
              Text(date.formatted(date: .long, time: .omitted))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if self.isInstalled {
              self.installed
            }
          }
        }
      }

      Divider()

      let notes = self.release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      MarkdownText(text: notes.isEmpty ? "_No release notes provided._" : notes, layout: Markdown.Layout(font: .systemFont(ofSize: 13), lineSpacing: 3))
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// That it's the build that's running: Installed, with a check, in white on a green capsule.
  private var installed: some View {
    HStack(spacing: 3) {
      Image(systemName: "checkmark")
        .fontWeight(.bold)
        .accessibilityHidden(true)
      Text("Installed")
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(.green, in: .capsule)
  }
}
